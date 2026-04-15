#!/usr/bin/env bash
set -euo pipefail

# Merges multiple tool scan output JSON files into a single consolidated findings report.
# Each input file must follow the normalized output schema produced by run-sast.sh,
# run-secrets.sh, run-sca.sh, and run-sast-codeql.sh.
#
# Usage: consolidate.sh <file1.json> [file2.json ...]
# Outputs consolidated JSON to stdout.

if [[ $# -eq 0 ]]; then
    echo "Error: at least one JSON input file is required" >&2
    echo "Usage: consolidate.sh <file1.json> [file2.json ...]" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required. Install with: brew install jq" >&2
    exit 1
fi

# Build a JSON array of all input file paths for jq to load
FILES_ARGS=()
for f in "$@"; do
    if [[ -f "$f" ]]; then
        FILES_ARGS+=("--slurpfile" "tool_output_$(( ${#FILES_ARGS[@]} / 2 ))" "$f")
    else
        echo "Warning: skipping missing file: $f" >&2
    fi
done

if [[ ${#FILES_ARGS[@]} -eq 0 ]]; then
    echo '{"findings":[],"summary":{"total":0,"by_severity":{"critical":0,"high":0,"medium":0,"low":0},"by_tool":{},"by_cwe":{}},"metadata":{"scan_date":"","tools_used":[],"tools_skipped":[]}}'
    exit 0
fi

# Use jq null input with each file slurped in as a variable
JQ_SCRIPT='null'
JQ_ARGS=()
FILE_VARS=()

IDX=0
for f in "$@"; do
    if [[ -f "$f" ]]; then
        JQ_ARGS+=("--slurpfile" "f${IDX}" "$f")
        FILE_VARS+=("\$f${IDX}[]")
        IDX=$(( IDX + 1 ))
    fi
done

# Build the array expression for jq
ARRAY_EXPR="$(IFS=", "; echo "${FILE_VARS[*]}")"

jq "${JQ_ARGS[@]}" --null-input --arg scan_date "$(date -u +%Y-%m-%d)" \
    --argjson inputs "$(
        # Collect all inputs into a single JSON array for pre-processing
        PARTS=()
        for f in "$@"; do
            [[ -f "$f" ]] && PARTS+=("$(cat "$f")")
        done
        printf '%s\n' "${PARTS[@]}" | jq -s '.'
    )" '
$inputs as $all_tools |

# Flatten all findings from all tool outputs
($all_tools | [.[] | .findings // [] | .[]] ) as $raw_findings |

# Assign sequential SENTINEL IDs and normalize fields
[$raw_findings | to_entries[] | {
    "id": ("SENTINEL-" + ((.key + 1) | tostring | if length < 3 then "00"[0:3-length] + . else . end)),
    "severity": (.value.severity // "MEDIUM"),
    "title": (.value.title // .value.description // "unknown"),
    "description": (.value.description // ""),
    "file": (.value.file // "unknown"),
    "line": (.value.line // 0),
    "end_line": (.value.end_line // null),
    "column": (.value.column // null),
    "code_snippet": (.value.code_snippet // .value.evidence // null),
    "rule_id": (.value.rule_id // null),
    "cwe": (.value.cwe // null),
    "owasp": (.value.owasp // null),
    "confidence": (.value.confidence // "MEDIUM"),
    "source_tool": (.value.source_tool // .value.tool // "unknown"),
    "taint_flow": (.value.taint_flow // null),
    "tags": (.value.tags // []),
    "status": "confirmed"
}] as $findings |

# Count by severity (lowercase keys)
{
    "critical": ([$findings[] | select(.severity == "CRITICAL")] | length),
    "high":     ([$findings[] | select(.severity == "HIGH")]     | length),
    "medium":   ([$findings[] | select(.severity == "MEDIUM")]   | length),
    "low":      ([$findings[] | select(.severity == "LOW")]      | length)
} as $by_severity |

# Count by tool
([$findings[] | .source_tool] | group_by(.) | map({(.[0]): length}) | add // {}) as $by_tool |

# Count by CWE (exclude nulls)
([$findings[] | select(.cwe != null) | .cwe] | group_by(.) | map({(.[0]): length}) | add // {}) as $by_cwe |

# Determine which tools were run and which skipped
($all_tools | [.[] | (.tool // "unknown")] | unique) as $tools_used |
($all_tools | [.[] | select((.summary.skipped // false) == true) | (.tool // "unknown")] | unique) as $tools_skipped |

{
    "findings": $findings,
    "summary": {
        "total": ($findings | length),
        "by_severity": $by_severity,
        "by_tool": $by_tool,
        "by_cwe": $by_cwe
    },
    "metadata": {
        "scan_date": $scan_date,
        "tools_used": $tools_used,
        "tools_skipped": $tools_skipped
    }
}
'
