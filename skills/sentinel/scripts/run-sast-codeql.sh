#!/usr/bin/env bash
set -euo pipefail

# Runs CodeQL taint analysis on a project and outputs normalized JSON findings.
# Silently exits with empty findings if codeql is not installed.
#
# Usage: run-sast-codeql.sh <project-path> [language]
#
# If language is omitted, it is auto-detected from file extensions.
# Outputs normalized JSON to stdout (same schema as run-sast.sh).

PROJECT_PATH="${1:-}"
EXPLICIT_LANG="${2:-}"

if [[ -z "$PROJECT_PATH" ]]; then
    echo "Error: project path is required as first argument" >&2
    exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Error: project directory not found: $PROJECT_PATH" >&2
    exit 1
fi

PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

# --- Verify codeql is available ---

# Support both standalone `codeql` and `gh codeql` extension
if command -v codeql >/dev/null 2>&1; then
    CODEQL_CMD="codeql"
elif command -v gh >/dev/null 2>&1 && gh codeql version >/dev/null 2>&1; then
    CODEQL_CMD="gh codeql"
else
    echo "Warning: codeql not installed — skipping CodeQL analysis." >&2
    echo "Install with: gh extension install github/gh-codeql" >&2
    echo '{"tool":"codeql","language":"none","findings":[],"summary":{"total":0,"errors":0,"skipped":true,"reason":"codeql not installed"}}'
    exit 0
fi

# --- Detect language ---

detect_language() {
    local dir="$1"
    local counts=()
    for ext_lang in "py:python" "js:javascript" "ts:javascript" "jsx:javascript" "tsx:javascript" \
                    "java:java" "go:go" "cs:csharp" "rb:ruby" "cpp:cpp" "c:cpp" "swift:swift"; do
        local ext="${ext_lang%%:*}"
        local lang="${ext_lang##*:}"
        local count
        count=$(find "$dir" -name "*.${ext}" \
            -not -path "*/node_modules/*" -not -path "*/.git/*" \
            -not -path "*/vendor/*" -not -path "*/.venv/*" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$count" -gt 0 ]]; then
            echo "$lang"
            return
        fi
    done
    echo ""
}

if [[ -n "$EXPLICIT_LANG" ]]; then
    CODEQL_LANG="$EXPLICIT_LANG"
else
    CODEQL_LANG="$(detect_language "$PROJECT_PATH")"
fi

if [[ -z "$CODEQL_LANG" ]]; then
    echo "Warning: could not detect a supported CodeQL language — skipping." >&2
    echo '{"tool":"codeql","language":"none","findings":[],"summary":{"total":0,"errors":0,"skipped":true,"reason":"unsupported language"}}'
    exit 0
fi

echo "CodeQL language: $CODEQL_LANG" >&2

# --- Set up temp directory for database and results ---

WORK_DIR="$(mktemp -d /tmp/sentinel-codeql-XXXXXX)"
DB_PATH="$WORK_DIR/codeql-db"
SARIF_PATH="$WORK_DIR/results.sarif"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# --- Create CodeQL database ---

echo "Creating CodeQL database..." >&2
if ! $CODEQL_CMD database create "$DB_PATH" \
    --language="$CODEQL_LANG" \
    --source-root="$PROJECT_PATH" \
    --overwrite \
    2>&1 | tail -3 >&2; then
    echo "Warning: CodeQL database creation failed — skipping." >&2
    echo '{"tool":"codeql","language":"'"$CODEQL_LANG"'","findings":[],"summary":{"total":0,"errors":1,"skipped":true,"reason":"database creation failed"}}'
    exit 0
fi

# --- Run security analysis ---

QUERY_PACK="codeql/${CODEQL_LANG}-queries"
QUERY_SUITE="${QUERY_PACK}:codeql-suites/${CODEQL_LANG}-security-and-quality.qls"

# --- Ensure query pack is downloaded ---

if ! ls "$HOME/.codeql/packages/$QUERY_PACK" >/dev/null 2>&1; then
    echo "Downloading CodeQL query pack: $QUERY_PACK ..." >&2
    if ! $CODEQL_CMD pack download "$QUERY_PACK" >&2 2>&1; then
        echo "Warning: could not download $QUERY_PACK — skipping." >&2
        echo '{"tool":"codeql","language":"'"$CODEQL_LANG"'","findings":[],"summary":{"total":0,"errors":1,"skipped":true,"reason":"pack download failed"}}'
        exit 0
    fi
fi

echo "Running CodeQL security-and-quality analysis..." >&2
if ! $CODEQL_CMD database analyze "$DB_PATH" \
    "$QUERY_SUITE" \
    --format=sarif-latest \
    --output="$SARIF_PATH" \
    2>&1 | tail -3 >&2; then
    echo "Warning: CodeQL analysis failed — skipping." >&2
    echo '{"tool":"codeql","language":"'"$CODEQL_LANG"'","findings":[],"summary":{"total":0,"errors":1,"skipped":true,"reason":"analysis failed"}}'
    exit 0
fi

if [[ ! -f "$SARIF_PATH" ]]; then
    echo "Warning: no SARIF output produced — skipping." >&2
    echo '{"tool":"codeql","language":"'"$CODEQL_LANG"'","findings":[],"summary":{"total":0,"errors":0,"skipped":true,"reason":"no output"}}'
    exit 0
fi

# --- Parse SARIF to normalized JSON ---

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for SARIF parsing. Install with: brew install jq" >&2
    exit 1
fi

jq --arg lang "$CODEQL_LANG" '
def severity_from_sarif:
    . as $r |
    ($r.properties.severity // $r.properties["problem.severity"] // "warning") as $sev |
    ($r.properties.precision // $r.properties["problem.precision"] // "medium") as $prec |
    if $sev == "error" then
        if ($prec == "high" or $prec == "very-high") then "HIGH"
        else "MEDIUM"
        end
    elif $sev == "warning" then "MEDIUM"
    else "LOW"
    end;

def extract_cwe(rules):
    . as $rule_id |
    (rules // []) | map(select(.id == $rule_id)) | .[0] as $rule |
    ($rule.properties.tags // []) |
    map(select(startswith("external/cwe/cwe-"))) |
    .[0] |
    if . then "CWE-" + (split("cwe-")[1] | ascii_upcase) else null end;

def extract_owasp(rules):
    . as $rule_id |
    (rules // []) | map(select(.id == $rule_id)) | .[0] as $rule |
    ($rule.properties.tags // []) |
    map(select(startswith("external/owasp/"))) |
    .[0] |
    if . then ascii_upcase | gsub("EXTERNAL/OWASP/"; "") else null end;

.runs[0] as $run |
($run.tool.driver.rules // []) as $rules |
{
    "tool": "codeql",
    "language": $lang,
    "findings": [
        ($run.results // [])[] |
        . as $result |
        ($result.locations[0].physicalLocation // {}) as $loc |
        {
            "severity": ($result | severity_from_sarif),
            "title": ($result.message.text // $result.ruleId // "unknown"),
            "description": ($result.message.text // ""),
            "file": ($loc.artifactLocation.uri // "unknown"),
            "line": ($loc.region.startLine // 0),
            "end_line": ($loc.region.endLine // ($loc.region.startLine // 0)),
            "column": ($loc.region.startColumn // 0),
            "code_snippet": ($loc.region.snippet.text // ""),
            "rule_id": ($result.ruleId // ""),
            "cwe": ($result.ruleId | extract_cwe($rules)),
            "owasp": ($result.ruleId | extract_owasp($rules)),
            "confidence": (
                ($rules | map(select(.id == $result.ruleId)) | .[0].properties.precision // "medium") |
                if . == "very-high" or . == "high" then "HIGH"
                elif . == "medium" then "MEDIUM"
                else "LOW"
                end
            ),
            "taint_flow": (
                if $result.codeFlows then
                    ($result.codeFlows[0].threadFlows[0].locations //[] |
                     map(.location.physicalLocation.artifactLocation.uri + ":" +
                         (.location.physicalLocation.region.startLine // 0 | tostring)) |
                     join(" → "))
                else null
                end
            ),
            "source_tool": "codeql"
        }
    ],
    "summary": {
        "total": (($run.results // []) | length),
        "errors": 0
    }
}
' "$SARIF_PATH"
