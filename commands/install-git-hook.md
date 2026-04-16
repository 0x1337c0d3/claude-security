# /install-git-hook

Install the Sentinel pre-commit hook — either into a single git repository
(default) or globally for every git repository on the machine (`--global`).

## Flags

| Flag | Behaviour |
|------|-----------|
| *(none)* | Install into a single repository's `.git/hooks/` |
| `--global` | Install into a user-level global hooks directory; applies to **all** git repos automatically via `core.hooksPath` |

## What you do

### Step 1 — Detect install mode

If the user passed `--global`, set `MODE=global`. Otherwise `MODE=local`.

---

## Local mode (MODE=local)

### Step 2L — Determine target project

Ask the user for the target project path, or use the current working directory if they don't specify one:

> "Which project should I install the Sentinel pre-commit hook into? (press Enter to use the current directory: `<cwd>`)"

Resolve the path to an absolute path.

### Step 3L — Verify it's a git repository

Check that `<target>/.git` exists. If not, tell the user:

> "❌ `<path>` is not a git repository. Please run this from inside a git project."

And stop.

### Step 4L — Resolve SENTINEL_DIR (see shared Step below)

### Step 5L — Check for existing hook

Before writing, check if `<target>/.git/hooks/pre-commit` already exists. If it does:

> "⚠️  A pre-commit hook already exists at `<path>`. Overwrite it? (yes/no)"

Only proceed if the user confirms.

### Step 6L — Write the hook

Ensure the hooks directory exists:

```bash
mkdir -p <target>/.git/hooks
```

Write the following content to `<target>/.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
# Installed by Sentinel (claude-security plugin)
# Source: https://github.com/anthropics/claude-security
export SENTINEL_DIR="<resolved-absolute-SENTINEL_DIR>"
exec "$SENTINEL_DIR/scripts/pre-commit.sh" "$@"
```

Make it executable:

```bash
chmod +x <target>/.git/hooks/pre-commit
```

### Step 7L — Report success

Show the user:

```
✅ Sentinel pre-commit hook installed!

   Location:  <target>/.git/hooks/pre-commit
   Sentinel:  <SENTINEL_DIR>
   Scope:     this repository only

Test it:
   cd <target>
   SENTINEL_SKIP=1 git commit --allow-empty -m "test sentinel hook"

To bypass in an emergency:
   SENTINEL_SKIP=1 git commit ...

The hook will block commits with CRITICAL or HIGH security findings.
```

---

## Global mode (MODE=global)

Requires git ≥ 2.9. The global `core.hooksPath` setting points git at a
single hooks directory for every repository on the machine.

### Step 2G — Resolve SENTINEL_DIR (see shared Step below)

### Step 3G — Determine global hooks directory

Use `~/.config/sentinel/hooks` as the default global hooks directory.
If the user's git config already has `core.hooksPath` set to a different path,
ask whether to reuse that path or switch to the default:

```bash
git config --global core.hooksPath   # check for existing value
```

> "⚠️  git already has core.hooksPath set to `<existing-path>`.
>    Use that directory (recommended) or switch to `~/.config/sentinel/hooks`?"

If using an existing path, add the hook there without changing git config.
If using the default, proceed with `~/.config/sentinel/hooks`.

### Step 4G — Check for existing hook

Before writing, check if `<hooks-dir>/pre-commit` already exists. If it does:

> "⚠️  A global pre-commit hook already exists at `<path>`. Overwrite it? (yes/no)"

Only proceed if the user confirms.

### Step 5G — Write the hook and configure git

Create the directory and write the hook:

```bash
mkdir -p <hooks-dir>
```

Write the following content to `<hooks-dir>/pre-commit`:

```bash
#!/usr/bin/env bash
# Installed by Sentinel (claude-security plugin) — GLOBAL HOOK
# Source: https://github.com/anthropics/claude-security
export SENTINEL_DIR="<resolved-absolute-SENTINEL_DIR>"
exec "$SENTINEL_DIR/scripts/pre-commit.sh" "$@"
```

Make it executable and register with git:

```bash
chmod +x <hooks-dir>/pre-commit
git config --global core.hooksPath "<hooks-dir>"
```

### Step 6G — Report success

Show the user:

```
✅ Sentinel pre-commit hook installed globally!

   Hook:      <hooks-dir>/pre-commit
   Sentinel:  <SENTINEL_DIR>
   Scope:     ALL git repositories on this machine
              (via git config --global core.hooksPath)

Test it in any repo:
   SENTINEL_SKIP=1 git commit --allow-empty -m "test sentinel hook"

To bypass in an emergency:
   SENTINEL_SKIP=1 git commit ...

To uninstall globally:
   git config --global --unset core.hooksPath

The hook will block commits with CRITICAL or HIGH security findings.
```

---

## Shared: Resolve SENTINEL_DIR

The `SENTINEL_DIR` is the absolute path to the `skills/sentinel/` directory
inside the installed claude-security plugin. Determine it as follows:

1. Check if `CLAUDE_PLUGIN_ROOT` is set in the environment. If so, `SENTINEL_DIR="$CLAUDE_PLUGIN_ROOT/skills/sentinel"`.
2. Otherwise check if `CLAUDE_SKILL_DIR` is set. If so, compute from it: `SENTINEL_DIR="$(dirname "$CLAUDE_SKILL_DIR")/sentinel"` (since skills are siblings).
3. Otherwise, use the directory containing this command file as a reference: the sentinel skill is at `<commands_dir>/../skills/sentinel`.
4. Verify `$SENTINEL_DIR/scripts/pre-commit.sh` exists. If not, show an error with the resolved path.

---

## Notes

- The hook bakes in an absolute `SENTINEL_DIR` path. If the plugin is moved or reinstalled, re-run `/install-git-hook` (or `/install-git-hook --global`) to update it.
- Global mode does **not** interfere with per-repo hooks that were installed before `core.hooksPath` was set — git uses `core.hooksPath` exclusively once set, so any old `.git/hooks/pre-commit` files in individual repos will be ignored.
- For CI/CD scanning, use the GitHub Actions workflow at `.github/workflows/sentinel.yml` in the claude-security repo.
- To scope only to specific repos after a global install, unset `core.hooksPath` globally and re-run the local install per repo.
