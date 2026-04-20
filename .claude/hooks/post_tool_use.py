#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.8"
# ///

import json
import os
import sys
from pathlib import Path

LOGGING_ENABLED = os.environ.get("CLAUDE_HOOK_LOGGING", "0") == "1"


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

        log_event(input_data, "post_tool_use.json")

        sys.exit(0)

    except json.JSONDecodeError:
        # Handle JSON decode errors gracefully
        sys.exit(0)
    except Exception:
        # Exit cleanly on any other error
        sys.exit(0)


if __name__ == "__main__":
    main()
