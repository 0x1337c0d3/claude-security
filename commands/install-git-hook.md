# /install-git-hook

Install the Sentinel pre-commit hook into a target git repository.

## What you do

When the user runs `/install-git-hook`, follow these steps:

### Step 1 — Determine target project

Ask the user for the target project path, or use the current working directory if they don't specify one:

> "Which project should I install the Sentinel pre-commit hook into? (press Enter to use the current directory: `<cwd>`)"

Resolve the path to an absolute path.

### Step 2 — Verify it's a git repository

Check that `<target>/.git` exists. If not, tell the user:

> "❌ `<path>` is not a git repository. Please run this from inside a git project."

And stop.

### Step 3 — Resolve SENTINEL_DIR

The `SENTINEL_DIR` is the absolute path to the `skills/sentinel/` directory inside the installed claude-security plugin. Determine it as follows:

1. Check if `CLAUDE_PLUGIN_ROOT` is set in the environment. If so, `SENTINEL_DIR="$CLAUDE_PLUGIN_ROOT/skills/sentinel"`.
2. Otherwise check if `CLAUDE_SKILL_DIR` is set. If so, compute from it: `SENTINEL_DIR="$(dirname "$CLAUDE_SKILL_DIR")/sentinel"` (since skills are siblings).
3. Otherwise, use the directory containing this command file as a reference: the sentinel skill is at `<commands_dir>/../skills/sentinel`.
4. Verify `$SENTINEL_DIR/scripts/pre-commit.sh` exists. If not, show an error with the resolved path.

### Step 4 — Write the hook

Write the following content to `<target>/.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
# Installed by Sentinel (claude-security plugin)
# Source: https://github.com/anthropics/claude-security
export SENTINEL_DIR="<resolved-absolute-SENTINEL_DIR>"
exec "$SENTINEL_DIR/scripts/pre-commit.sh" "$@"
```

Replace `<resolved-absolute-SENTINEL_DIR>` with the actual resolved path.

Make it executable:

```bash
chmod +x <target>/.git/hooks/pre-commit
```

### Step 5 — Check for existing hook

Before writing, check if `.git/hooks/pre-commit` already exists. If it does:

> "⚠️  A pre-commit hook already exists at `<path>`. Overwrite it? (yes/no)"

Only proceed if the user confirms.

### Step 6 — Report success

Show the user:

```
✅ Sentinel pre-commit hook installed!

   Location:  <target>/.git/hooks/pre-commit
   Sentinel:  <SENTINEL_DIR>

Test it:
   cd <target>
   SENTINEL_SKIP=1 git commit --allow-empty -m "test sentinel hook"   # should pass (bypass)
   git stash && git stash pop                                           # stage something and commit normally

To bypass in an emergency:
   SENTINEL_SKIP=1 git commit ...

The hook will block commits with CRITICAL or HIGH security findings.
```

## Notes

- The hook bakes in an absolute `SENTINEL_DIR` path. If the plugin is moved or reinstalled, re-run `/install-git-hook` to update it.
- For CI/CD scanning, use the GitHub Actions workflow at `.github/workflows/sentinel.yml` in the claude-security repo.
- Hook can be uninstalled with: `rm <target>/.git/hooks/pre-commit`
