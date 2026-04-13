# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

A **Claude Code security plugin** combining two tools into a single installable package:
- **Sentinel** — autonomous security scanning (SAST, secrets, dependency audits, risk scoring)
- **Prompt Injection Defender** — real-time hook that detects indirect prompt injection in tool outputs

## Structure

```
claude-security/
├── README.md
├── .claude-plugin/
│   ├── plugin.json           # Plugin manifest (name: claude-security)
│   └── marketplace.json      # Marketplace definition
├── skills/                   # Loaded by the plugin system
│   ├── sentinel/             # /sentinel:* commands
│   │   ├── SKILL.md
│   │   ├── scripts/          # 9 shell scripts (detect, scan, score, report)
│   │   ├── configs/semgrep-rules/  # 82 SAST rules across 8 languages
│   │   ├── templates/        # report.md, issue.md, sarif.json
│   │   ├── references/       # DREAD and STRIDE threat models
│   │   ├── tests/            # Shell test suites + fixtures
│   │   └── skills/           # Sub-skills: audit, red-team, stride, api, etc.
│   └── prompt-injection-defender/
│       ├── SKILL.md
│       ├── patterns.yaml     # Detection patterns (5 attack categories)
│       ├── hooks/defender-python/   # Hook implementation + tests
│       ├── cookbook/         # Interactive install/modify/test workflows
│       └── docs/             # README, INSTALLATION.md, screenshots
├── hooks/
│   └── hooks.json            # Registers PostToolUse defender hook for the plugin
├── commands/                 # /install and /prime commands
│   ├── install.md
│   └── prime.md
└── .claude/                  # Local dev config (not distributed)
    ├── hooks/
    │   ├── pre_tool_use.py   # Safety hook: blocks dangerous rm / .env access
    │   └── post_tool_use.py  # Logging hook
    └── settings.json         # Wires up hooks for working on this repo itself
```

## Hooks

Claude Code hooks fire on lifecycle events: `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SubagentStop`.

- **Plugin hooks** (`hooks/hooks.json`) — registered when users install this plugin; uses `${CLAUDE_PLUGIN_ROOT}` for paths
- **Local dev hooks** (`.claude/settings.json`) — active when working on this repo; uses `$CLAUDE_PROJECT_DIR` for paths

Hook scripts should:
- Be self-contained and executable (`chmod +x`)
- Include a shebang; prefer POSIX-compatible shell or Python
- Exit 0 to allow Claude to proceed; exit non-zero to block (for `PreToolUse` gatekeepers)
- Write feedback to stdout — Claude Code surfaces this back to the model

## Skills

Skills are Markdown files (`SKILL.md`) that Claude loads as instruction sets, invoked via `/skill-name` commands.

- `SKILL.md` is the entry point — keep it focused on what Claude should *do*, not documentation
- Reference files (patterns, rules, templates) are loaded by the skill at runtime via relative paths from `${CLAUDE_SKILL_DIR}`
- Sentinel sub-skills in `skills/sentinel/skills/` are invoked as `/claude-security:sentinel`, `/claude-security:audit`, etc.

## Installation (for users)

```bash
# Local install
/plugin marketplace add /path/to/claude-security
/plugin install claude-security@claude-security

# Or load directly for testing
claude --plugin-dir /path/to/claude-security
```

## Conventions

- No build system — don't add one unless there's a clear need
- Shell scripts communicate via JSON on stdout, logs on stderr
- Patterns in `patterns.yaml` use Python regex syntax
- Keep `README.md` as the single-product entry point; deep docs live inside each skill's folder
