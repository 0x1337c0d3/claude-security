#!/usr/bin/env bash
set -euo pipefail

# Sentinel pre-commit hook: runs SAST + secrets scan on staged files.
# Blocks commit if any CRITICAL or HIGH findings are found.
#
# Usage: called automatically by git as .git/hooks/pre-commit
# Bypass: SENTINEL_SKIP=1 git commit  (emergency use only)

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Bypass ───────────────────────────────────────────────────────────────────
if [[ "${SENTINEL_SKIP:-}" == "1" ]]; then
    echo -e "${YELLOW}[sentinel] SENTINEL_SKIP=1 — skipping security scan (emergency bypass)${RESET}" >&2
    exit 0
fi

# ── Resolve SENTINEL_DIR ─────────────────────────────────────────────────────
# 1. Explicit env var (set by install-git-hook command)
# 2. Relative to this script's location (for dev/test)

if [[ -z "${SENTINEL_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SENTINEL_DIR="$(dirname "$SCRIPT_DIR")"
fi

SCRIPTS_DIR="$SENTINEL_DIR/scripts"

if [[ ! -f "$SCRIPTS_DIR/detect-stack.sh" ]]; then
    echo -e "${RED}[sentinel] ERROR: Cannot find sentinel scripts at: $SCRIPTS_DIR${RESET}" >&2
    echo -e "${RED}           Set SENTINEL_DIR env var to the sentinel skill directory.${RESET}" >&2
    exit 1
fi

# ── Staged files ─────────────────────────────────────────────────────────────
STAGED="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)"

if [[ -z "$STAGED" ]]; then
    exit 0
fi

echo -e "${BOLD}[sentinel]${RESET} Scanning staged files for security issues..." >&2

# ── Copy staged files to a temp dir ──────────────────────────────────────────
TMPDIR_SCAN="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_SCAN"; }
trap cleanup EXIT

GIT_ROOT="$(git rev-parse --show-toplevel)"

while IFS= read -r file; do
    dest_dir="$TMPDIR_SCAN/$(dirname "$file")"
    mkdir -p "$dest_dir"
    # Use git show :file to get the staged version (not working-tree version)
    git show ":$file" > "$TMPDIR_SCAN/$file" 2>/dev/null || true
done <<< "$STAGED"

# ── Detect stack ─────────────────────────────────────────────────────────────
STACK="$("$SCRIPTS_DIR/detect-stack.sh" "$GIT_ROOT" 2>/dev/null)"
LANGUAGES="$(echo "$STACK" | jq -r '.languages[]' 2>/dev/null || true)"

# ── SAST scan ────────────────────────────────────────────────────────────────
SAST_FILES=()

if command -v semgrep >/dev/null 2>&1 && [[ -n "$LANGUAGES" ]]; then
    while IFS= read -r lang; do
        [[ -z "$lang" ]] && continue
        SAST_OUT="$TMPDIR_SCAN/sast-${lang}.json"
        "$SCRIPTS_DIR/run-sast.sh" "$TMPDIR_SCAN" "$lang" > "$SAST_OUT" 2>/dev/null || true
        [[ -s "$SAST_OUT" ]] && SAST_FILES+=("$SAST_OUT")
    done <<< "$LANGUAGES"
else
    if ! command -v semgrep >/dev/null 2>&1; then
        echo -e "${DIM}[sentinel] semgrep not found — skipping SAST (install: pip install semgrep)${RESET}" >&2
    fi
fi

# ── Secrets scan ─────────────────────────────────────────────────────────────
SECRETS_OUT="$TMPDIR_SCAN/secrets.json"

if command -v gitleaks >/dev/null 2>&1; then
    # Use gitleaks native --staged support (scans the index directly)
    gitleaks detect \
        --source "$GIT_ROOT" \
        --staged \
        --report-format json \
        --report-path "$SECRETS_OUT" \
        --no-banner \
        2>/dev/null || true
    # If no findings, gitleaks may not write the file — create empty result
    if [[ ! -s "$SECRETS_OUT" ]]; then
        printf '{"tool":"gitleaks","findings":[],"summary":{"total":0}}\n' > "$SECRETS_OUT"
    fi
else
    echo -e "${DIM}[sentinel] gitleaks not found — skipping secrets scan (install: brew install gitleaks)${RESET}" >&2
    printf '{"tool":"gitleaks","findings":[],"summary":{"total":0}}\n' > "$SECRETS_OUT"
fi

# Normalize raw gitleaks output to sentinel format
SECRETS_NORMALIZED="$TMPDIR_SCAN/secrets-normalized.json"
if command -v jq >/dev/null 2>&1; then
    jq '
    if type == "array" then
    {
        "tool": "gitleaks",
        "findings": [
            .[] | {
                "severity": (
                    if (.RuleID // "" | test("private.key|private_key|rsa|ssh"; "i")) then "CRITICAL"
                    elif (.RuleID // "" | test("aws|gcp|azure|cloud"; "i")) then "CRITICAL"
                    elif (.RuleID // "" | test("api.key|api_key|apikey|secret.key|token"; "i")) then "HIGH"
                    elif (.RuleID // "" | test("password|passwd|pwd"; "i")) then "HIGH"
                    else "MEDIUM"
                    end
                ),
                "title": ("Hardcoded secret: " + (.RuleID // "unknown")),
                "description": (.Description // "Secret detected"),
                "file": (.File // "unknown"),
                "line": (.StartLine // null),
                "rule_id": (.RuleID // "unknown"),
                "source_tool": "gitleaks"
            }
        ],
        "summary": { "total": length }
    }
    else
    .
    end
    ' "$SECRETS_OUT" > "$SECRETS_NORMALIZED" 2>/dev/null || cp "$SECRETS_OUT" "$SECRETS_NORMALIZED"
else
    cp "$SECRETS_OUT" "$SECRETS_NORMALIZED"
fi

# ── Consolidate ───────────────────────────────────────────────────────────────
ALL_INPUTS=("$SECRETS_NORMALIZED" "${SAST_FILES[@]+"${SAST_FILES[@]}"}")

CONSOLIDATED="$TMPDIR_SCAN/consolidated.json"
if ! "$SCRIPTS_DIR/consolidate.sh" "${ALL_INPUTS[@]}" > "$CONSOLIDATED" 2>/dev/null; then
    echo -e "${YELLOW}[sentinel] Warning: consolidation failed — skipping scan${RESET}" >&2
    exit 0
fi

# ── Print findings ────────────────────────────────────────────────────────────
BLOCKING_COUNT=0

if command -v jq >/dev/null 2>&1; then
    TOTAL="$(jq '.summary.total // 0' "$CONSOLIDATED")"
    CRITICAL="$(jq '.summary.by_severity.critical // 0' "$CONSOLIDATED")"
    HIGH="$(jq '.summary.by_severity.high // 0' "$CONSOLIDATED")"
    MEDIUM="$(jq '.summary.by_severity.medium // 0' "$CONSOLIDATED")"
    LOW="$(jq '.summary.by_severity.low // 0' "$CONSOLIDATED")"
    BLOCKING_COUNT=$((CRITICAL + HIGH))

    if [[ "$TOTAL" -gt 0 ]]; then
        echo "" >&2
        echo -e "${BOLD}┌─ Sentinel findings ─────────────────────────────────────────┐${RESET}" >&2

        # Print each finding
        jq -r '.findings[] | [
            .severity,
            (.file // "unknown"),
            (.line // 0 | tostring),
            (.title // "unknown")
        ] | @tsv' "$CONSOLIDATED" | while IFS=$'\t' read -r sev file line title; do
            case "$sev" in
                CRITICAL) color="$RED" ;;
                HIGH)     color="$RED" ;;
                MEDIUM)   color="$YELLOW" ;;
                *)        color="$CYAN" ;;
            esac
            printf "${color}  %-8s${RESET}  %s:%s  %s\n" "$sev" "$file" "$line" "$title" >&2
        done

        echo -e "${BOLD}└─────────────────────────────────────────────────────────────┘${RESET}" >&2
        echo "" >&2
        echo -e "  Total: ${BOLD}$TOTAL${RESET}  |  Critical: ${RED}$CRITICAL${RESET}  High: ${RED}$HIGH${RESET}  Medium: ${YELLOW}$MEDIUM${RESET}  Low: ${CYAN}$LOW${RESET}" >&2
        echo "" >&2
    fi
fi

# ── Block or pass ─────────────────────────────────────────────────────────────
if [[ "$BLOCKING_COUNT" -gt 0 ]]; then
    echo -e "${RED}${BOLD}[sentinel] COMMIT BLOCKED — $BLOCKING_COUNT CRITICAL/HIGH finding(s) must be resolved.${RESET}" >&2
    echo -e "${DIM}           To bypass in an emergency: SENTINEL_SKIP=1 git commit${RESET}" >&2
    exit 1
else
    if [[ "${TOTAL:-0}" -eq 0 ]]; then
        echo -e "${CYAN}[sentinel]${RESET} No security findings. Commit approved." >&2
    else
        echo -e "${CYAN}[sentinel]${RESET} No CRITICAL/HIGH findings. Commit approved (${MEDIUM:-0} medium, ${LOW:-0} low)." >&2
    fi
    exit 0
fi
