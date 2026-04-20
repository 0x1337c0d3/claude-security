#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.8"
# ///

import json
import os
import sys
import re
from pathlib import Path

LOGGING_ENABLED = os.environ.get("CLAUDE_HOOK_LOGGING", "0") == "1"


def is_dangerous_rm_command(command):
    """
    Comprehensive detection of dangerous rm commands.
    Matches various forms of rm -rf and similar destructive patterns.
    """
    # Normalize command by removing extra spaces and converting to lowercase
    normalized = " ".join(command.lower().split())

    # Pattern 1: Standard rm -rf variations
    patterns = [
        r"\brm\s+.*-[a-z]*r[a-z]*f",  # rm -rf, rm -fr, rm -Rf, etc.
        r"\brm\s+.*-[a-z]*f[a-z]*r",  # rm -fr variations
        r"\brm\s+--recursive\s+--force",  # rm --recursive --force
        r"\brm\s+--force\s+--recursive",  # rm --force --recursive
        r"\brm\s+-r\s+.*-f",  # rm -r ... -f
        r"\brm\s+-f\s+.*-r",  # rm -f ... -r
    ]

    # Check for dangerous patterns
    for pattern in patterns:
        if re.search(pattern, normalized):
            return True

    # Pattern 2: Check for rm with recursive flag targeting dangerous paths
    dangerous_paths = [
        r"/",  # Root directory
        r"/\*",  # Root with wildcard
        r"~",  # Home directory
        r"~/",  # Home directory path
        r"\$HOME",  # Home environment variable
        r"\.\.",  # Parent directory references
        r"\*",  # Wildcards in general rm -rf context
        r"\.",  # Current directory
        r"\.\s*$",  # Current directory at end of command
    ]

    if re.search(r"\brm\s+.*-[a-z]*r", normalized):  # If rm has recursive flag
        for path in dangerous_paths:
            if re.search(path, normalized):
                return True

    return False


CREDENTIAL_PATHS = [
    # AWS — match regardless of prefix (~, $HOME, /Users/x, /home/x, etc.)
    r"\.aws/credentials",
    r"\.aws/config",
    # SSH private keys
    r"\.ssh/id_rsa",
    r"\.ssh/id_ed25519",
    r"\.ssh/id_ecdsa",
    r"\.ssh/id_dsa",
    # Other credential stores
    r"\.gnupg/",
    r"\.netrc",
    r"\.git-credentials",
    r"\.config/gcloud/",
    r"\.kube/config",
    r"\.docker/config\.json",
    r"\.npmrc",
    r"\.pypirc",
]


def is_credential_file_access(tool_name, tool_input):
    """
    Block access to sensitive credential files outside of .env naming.
    """
    if tool_name in ["Read", "Edit", "MultiEdit", "Write", "Bash"]:
        if tool_name in ["Read", "Edit", "MultiEdit", "Write"]:
            file_path = tool_input.get("file_path", "")
            for pattern in CREDENTIAL_PATHS:
                if re.search(pattern, file_path):
                    return True
        elif tool_name == "Bash":
            command = tool_input.get("command", "")
            for pattern in CREDENTIAL_PATHS:
                if re.search(pattern, command):
                    return True
    return False


def is_env_file_access(tool_name, tool_input):
    """
    Check if any tool is trying to access .env files containing sensitive data.
    """
    if tool_name in ["Read", "Edit", "MultiEdit", "Write", "Bash"]:
        # Check file paths for file-based tools
        if tool_name in ["Read", "Edit", "MultiEdit", "Write"]:
            file_path = tool_input.get("file_path", "")
            if ".env" in file_path and not file_path.endswith(".env.sample"):
                return True

        # Check bash commands for .env file access
        elif tool_name == "Bash":
            command = tool_input.get("command", "")
            # Pattern to detect .env file access (but allow .env.sample)
            env_patterns = [
                r"\b\.env\b(?!\.sample)",  # .env but not .env.sample
                r"cat\s+.*\.env\b(?!\.sample)",  # cat .env
                r"echo\s+.*>\s*\.env\b(?!\.sample)",  # echo > .env
                r"touch\s+.*\.env\b(?!\.sample)",  # touch .env
                r"cp\s+.*\.env\b(?!\.sample)",  # cp .env
                r"mv\s+.*\.env\b(?!\.sample)",  # mv .env
            ]

            for pattern in env_patterns:
                if re.search(pattern, command):
                    return True

    return False


def log_event(input_data, filename):
    if not LOGGING_ENABLED:
        return
    log_dir = Path.cwd() / ".claude-logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / filename
    if log_path.exists():
        with open(log_path, "r") as f:
            try:
                log_data = json.load(f)
            except (json.JSONDecodeError, ValueError):
                log_data = []
    else:
        log_data = []
    log_data.append(input_data)
    with open(log_path, "w") as f:
        json.dump(log_data, f, indent=2)


def main():
    try:
        # Read JSON input from stdin
        input_data = json.load(sys.stdin)

        tool_name = input_data.get("tool_name", "")
        tool_input = input_data.get("tool_input", {})

        # Check for credential file access (AWS, SSH keys, GCloud, Kube, etc.)
        if is_credential_file_access(tool_name, tool_input):
            print(
                "BLOCKED: Access to credential files is prohibited",
                file=sys.stderr,
            )
            print(
                "Blocked paths include ~/.aws/credentials, ~/.ssh/id_*, ~/.kube/config, ~/.gnupg/, etc.",
                file=sys.stderr,
            )
            sys.exit(2)

        # Check for .env file access (blocks access to sensitive environment files)
        if is_env_file_access(tool_name, tool_input):
            print(
                "BLOCKED: Access to .env files containing sensitive data is prohibited",
                file=sys.stderr,
            )
            print("Use .env.sample for template files instead", file=sys.stderr)
            sys.exit(2)  # Exit code 2 blocks tool call and shows error to Claude

        # Check for dangerous rm -rf commands
        if tool_name == "Bash":
            command = tool_input.get("command", "")

            # Block rm -rf commands with comprehensive pattern matching
            if is_dangerous_rm_command(command):
                print(
                    "BLOCKED: Dangerous rm command detected and prevented",
                    file=sys.stderr,
                )
                sys.exit(2)  # Exit code 2 blocks tool call and shows error to Claude

        log_event(input_data, "pre_tool_use.json")

        sys.exit(0)

    except json.JSONDecodeError:
        # Gracefully handle JSON decode errors
        sys.exit(0)
    except Exception:
        # Handle any other errors gracefully
        sys.exit(1)


if __name__ == "__main__":
    main()
