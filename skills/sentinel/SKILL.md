---
name: sentinel
description: >
  Orchestrates security scanning combining AI-driven OWASP analysis with Semgrep
  SAST and CodeQL taint analysis. Cross-validates findings, calculates a risk score,
  and produces prioritised security audit reports. Invoke with /sentinel or when the
  user asks to "run security audit", "audit this project", "security scan", or
  "scan for vulnerabilities".
---

# Sentinel — AI + SAST Security Audit

Runs a full security audit of a target project combining AI-driven analysis
(OWASP Top 10, injection, auth, secrets, config, etc.) with Semgrep SAST
scanning, then cross-validates and consolidates both sets of findings into
a single prioritised report.

## Role

You are a security audit specialist. Your mission: systematically identify
security vulnerabilities, assess risks, and recommend security improvements.
Defense in depth requires multiple layers of validation — this skill combines
AI-driven context-aware analysis with automated SAST pattern detection to
achieve maximum coverage.

Key principles:
1. **Trust but verify**: both tools produce false positives and false negatives
2. **Context matters**: some issues require human judgment to confirm
3. **Prioritise by impact**: fix what matters most first
4. **Automate everything**: both tools should run in CI/CD
5. **Track progress**: measure security improvements over time

## Supported Flags

| Flag | Behaviour |
|------|-----------|
| `--path <dir>` | Target project directory to audit. Default: current working directory. |
| `--severity <low\|medium\|high\|critical>` | Minimum severity to include in report. Default: `low`. |
| `--skip-semgrep` | Skip the Semgrep SAST scan (Phase 2). Useful when semgrep is not installed. |
| `--skip-codeql` | Skip the CodeQL taint analysis (Phase 2b). Useful when codeql is not installed or the project has no build environment. |
| `--skip-crossval` | Skip cross-validation (Phase 3). Implies `--skip-semgrep` and `--skip-codeql`. |
| `--quiet` | Suppress progress messages; output findings only. |
| `--format <md\|json>` | Output format for consolidated report. Default: `md`. |

## Workflow

The audit runs in 5 phases. Phase 4 is reference material used when writing
recommendations; it does not produce output files of its own.

**Parallelisation**: Phase 1, Phase 2, and Phase 2b are fully independent —
run all three in parallel using the Agent tool (3 subagents). Phase 3
(cross-validation) must wait for all three to complete.

---

### Phase 1: AI-Driven Security Analysis *(run in parallel with Phase 2 + 2b)*

#### Step 1.1: Resolve Target Path

Parse `--path <dir>` from the user's invocation. If not supplied, use `$PWD`.
Validate the path exists:

```bash
TARGET="${FLAG_PATH:-$PWD}"
if [[ ! -d "$TARGET" ]]; then
  echo "Error: target directory not found: $TARGET"
  exit 1
fi
cd "$TARGET"
```

#### Step 1.2: Security Inventory

Before reading source files, build a quick inventory:

```bash
# Identify tech stack
find . -name "package.json" -o -name "requirements.txt" -o -name "go.mod" \
       -o -name "pom.xml" -o -name "*.csproj" -o -name "Gemfile" \
  | grep -v node_modules | grep -v .git | head -20

# Count lines of code (rough)
git ls-files 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 || true

# List entry points (main files, routes, handlers)
find . \( -name "main.*" -o -name "app.*" -o -name "server.*" -o -name "routes.*" \) \
  | grep -v node_modules | grep -v .git | head -20
```

Produce a Security Inventory:

```markdown
## Security Inventory
### Authentication
- Type: [JWT/Session/OAuth/API Key/None — detected from code]
- Password hashing: [bcrypt/argon2/scrypt/plaintext/none]
- MFA: [Yes/No]

### Authorization
- Type: [RBAC/ABAC/ACL/None]
- Coverage: [Fine/Coarse/Missing]

### Data Protection
- Encryption at rest: [Yes/No/Unknown]
- Encryption in transit: [Yes/No/Partial]
- PII handling: [Proper/Needs review/Unknown]

### Secrets Management
- Method: [Env vars/Secrets manager/Hardcoded — detected from grep]

### Infrastructure
- HTTPS enforced: [Yes/No/Unknown]
- Security headers present: [Yes/No/Partial]
- Rate limiting: [Implemented/None]
```

#### Step 1.3: Automated Pattern Scanning

Run these bash checks to gather evidence before deeper code reading:

```bash
# Dependency vulnerabilities
npm audit --audit-level=high 2>/dev/null || true
pip-audit 2>/dev/null || safety check 2>/dev/null || true
go mod verify 2>/dev/null || true

# Hardcoded secrets / credentials
grep -rn \
  -E "(password|secret|api_key|token|auth|passwd|credential)\s*=\s*['\"][^'\"]{6,}['\"]" \
  --include="*.py" --include="*.js" --include="*.ts" --include="*.go" \
  --include="*.java" --include="*.cs" --include="*.rb" --include="*.php" \
  --include="*.yaml" --include="*.yml" --include="*.json" \
  --exclude-dir=node_modules --exclude-dir=.git \
  . 2>/dev/null | head -40 || true

# eval / exec usage
grep -rn -E "eval\(|exec\(|shell_exec\(|system\(" \
  --include="*.py" --include="*.js" --include="*.ts" --include="*.php" \
  --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null | head -20 || true

# SQL injection patterns
grep -rn -E "(SELECT|INSERT|UPDATE|DELETE).*[\+\$\{].*" \
  --include="*.py" --include="*.js" --include="*.ts" --include="*.php" \
  --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null | head -20 || true

# Hardcoded IPs / internal URLs
grep -rn -E "https?://[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" \
  --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null | head -20 || true

# Private key material
grep -rn -E "BEGIN (RSA|EC|DSA|OPENSSH|PGP) PRIVATE KEY" \
  --exclude-dir=.git . 2>/dev/null | head -10 || true

# Additional secret / leak scanners (run if available)
gitleaks detect --source=. 2>/dev/null || true
trufflehog filesystem . --no-update 2>/dev/null || true

# Language-specific quick SAST
bandit -r . -ll 2>/dev/null || true           # Python
eslint --plugin security . 2>/dev/null || true # JS/TS (if configured)
snyk test 2>/dev/null || true                  # all ecosystems
```

#### Step 1.4: OWASP Top 10 Code Review

Read source files (prioritise routes, controllers, auth, DB access layers) and
assess each OWASP category. For each finding, record:

- **ID**: `VULN-NNN` (sequential, zero-padded to 3 digits)
- **Title**: short description
- **File**: relative path and line number
- **Severity**: Critical / High / Medium / Low
- **Category**: OWASP A0X or other framework
- **Description**: what the vulnerability is and why it matters
- **PoC / Evidence**: code snippet or grep result confirming the issue
- **Recommendation**: specific, actionable fix with a code example

Cover all 10 categories at minimum:

| Category | Key Checks |
|----------|-----------|
| **A01 Broken Access Control** | IDOR, missing authz on endpoints, metadata manipulation, CORS, path traversal |
| **A02 Cryptographic Failures** | HTTP data transmission, weak algos (MD5/SHA1 for passwords), hardcoded keys, data in logs |
| **A03 Injection** | SQL, NoSQL, command, LDAP injection; parameterised query usage |
| **A04 Insecure Design** | Missing rate limiting, no account lockout, weak password policy, undefined trust boundaries |
| **A05 Security Misconfiguration** | Default creds, unnecessary features, verbose errors, missing security headers, debug mode |
| **A06 Vulnerable Components** | Outdated deps with CVEs; unmaintained packages |
| **A07 Authentication Failures** | Brute-force protection, session tokens in URLs, sessions not invalidated on logout |
| **A08 Software Integrity Failures** | Missing lock files, insecure CI/CD, unsafe deserialization |
| **A09 Logging Failures** | No security event logging, sensitive data in logs, insufficient audit trail |
| **A10 SSRF** | User-controlled URLs in server requests, missing URL allowlist validation |

Also check for secrets, privilege escalation, and AWS/cloud-specific
misconfigurations if infrastructure code is present.

##### A03 Injection — Key Vulnerable vs. Safe Patterns

**JavaScript/Node.js**
```javascript
// ❌ SQL Injection
db.query("SELECT * FROM users WHERE id = " + req.params.id);
// ✅ Parameterised
db.query("SELECT * FROM users WHERE id = $1", [req.params.id]);

// ❌ Command Injection
exec("ls " + userInput);
// ✅ Safe
spawn("ls", [userInput]);
```

**Python**
```python
# ❌ SQL Injection
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
# ✅ Parameterised
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))

# ❌ Command Injection
os.system(f"ls {user_input}")
# ✅ Safe
subprocess.run(["ls", user_input], check=True)
```

**Go**
```go
// ❌ SQL Injection
db.Query(fmt.Sprintf("SELECT * FROM users WHERE id = %s", userId))
// ✅ Parameterised
db.Query("SELECT * FROM users WHERE id = $1", userId)
```

**C#**
```csharp
// ❌ SQL Injection
command.CommandText = $"SELECT * FROM users WHERE id = {userId}";
// ✅ Parameterised
var cmd = new SqlCommand("SELECT * FROM users WHERE id = @Id", conn);
cmd.Parameters.AddWithValue("@Id", userId);
```

**PHP**
```php
// ❌ SQL Injection
$query = "SELECT * FROM users WHERE id = $userId";
// ✅ Prepared statement
$stmt = $pdo->prepare("SELECT * FROM users WHERE id = ?");
$stmt->execute([$userId]);
```

##### A05 Security Misconfiguration — Required Security Headers

Verify all of these are present in HTTP responses:

| Header | Recommended Value |
|--------|-------------------|
| `Content-Security-Policy` | `default-src 'self'; script-src 'self'` |
| `X-Frame-Options` | `DENY` or `SAMEORIGIN` |
| `X-Content-Type-Options` | `nosniff` |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | restrict unnecessary browser features |

#### Step 1.5: Determine Output Paths

Before writing any report files, resolve the output directory and generate a
timestamp so all reports from this run share the same timestamp suffix:

```bash
OUTPUT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")/reports"
mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${OUTPUT_DIR}/security-audit-${TIMESTAMP}.md"
CONSOLIDATED_FILE="${OUTPUT_DIR}/security-audit-consolidated-${TIMESTAMP}.md"
SEMGREP_JSON="${OUTPUT_DIR}/semgrep-results.json"
CODEQL_SARIF="${OUTPUT_DIR}/codeql-results.sarif"
```

#### Step 1.6: Write Primary Audit Report

Save the full findings to the project root:

```bash
cat > "${REPORT_FILE}" << 'REPORTEOF'
# Security Audit Report

## Executive Summary
- **Project**: [detected project name]
- **Audit Date**: [today's date]
- **Auditor**: Claude (AI-driven) via /sentinel
- **Overall Risk Level**: [Critical / High / Medium / Low]

## Security Inventory
[from Step 1.2]

## Findings Summary
| Severity | Count | Fixed | Remaining |
|----------|-------|-------|-----------|
| 🔴 Critical | X | 0 | X |
| 🟠 High     | X | 0 | X |
| 🟡 Medium   | X | 0 | X |
| 🟢 Low      | X | 0 | X |

## Detailed Findings
[one section per VULN-NNN]

### [VULN-001] [Title]
**Severity**: [Critical/High/Medium/Low]
**Category**: [OWASP A0X]
**File**: `path/to/file.ext:line`

**Description**: [what it is and why it matters]

**Evidence**:
```
[code snippet or grep output]
```

**Recommendation**: [specific fix with code example]

## Positive Observations
[good security practices found in the codebase]

## Quick Remediation Commands
```bash
[dependency upgrade commands, config fixes, etc.]
```
REPORTEOF
```

Report **must** be written to `${REPORT_FILE}` (inside `reports/`, never a temp directory).

---

### Phase 2: Semgrep SAST Scan *(run in parallel with Phase 1 + 2b)*

Skip this phase if `--skip-semgrep` or `--skip-crossval` was supplied.

#### Step 2.1: Check semgrep Availability

```bash
if ! command -v semgrep >/dev/null 2>&1; then
  echo "[appsec] Warning: semgrep not found — skipping SAST scan."
  echo "[appsec] Install with: pip install semgrep"
  # Set SEMGREP_AVAILABLE=false and continue to Phase 3 note
fi
```

#### Step 2.2: Run Semgrep

```bash
echo "[appsec] Running Semgrep SAST scan..."
semgrep scan --json --config=auto --output="${SEMGREP_JSON}" . || true
# Exit code 1 from semgrep means findings were detected — not a fatal error
```

Output is written to `${SEMGREP_JSON}` (inside the `reports/` directory).

#### Step 2.3: Parse and Summarise Semgrep Findings

The Semgrep JSON schema:

```json
{
  "results": [
    {
      "check_id": "rule-id",
      "path": "file/path",
      "start": {"line": 10, "col": 5},
      "end":   {"line": 10, "col": 20},
      "extra": {
        "message": "Finding description",
        "severity": "ERROR|WARNING|INFO",
        "metadata": {
          "category": "security",
          "cwe": ["CWE-79"],
          "owasp": ["A03:2021"]
        }
      }
    }
  ],
  "errors": []
}
```

Severity mapping from Semgrep to standard scale:

| Semgrep | Standard |
|---------|----------|
| `ERROR` | Critical / High |
| `WARNING` | Medium |
| `INFO` | Low |

Categorise results:

- **SAST**: code vulnerabilities (injection, XSS, path traversal, etc.)
- **SCA**: dependency CVEs (`semgrep-supply-chain` or `r2c-security-audit`)
- **Secrets**: hardcoded credentials / API keys
- **Best Practices**: hygiene / quality rules

Count findings per category and severity for use in Phase 3.

---

### Phase 2b: CodeQL Taint Analysis *(run in parallel with Phase 1 + 2)*

Skip this phase if `--skip-codeql` or `--skip-crossval` was supplied.

#### Step 2b.1: Check CodeQL Availability

Use `gh codeql` (the GitHub CLI extension) as the preferred runner. Fall back
to the standalone `codeql` binary only if `gh` is unavailable.

```bash
if gh codeql --version >/dev/null 2>&1; then
  CODEQL_CMD="gh codeql"
elif command -v codeql >/dev/null 2>&1; then
  CODEQL_CMD="codeql"
else
  echo "[appsec] Warning: neither 'gh codeql' nor 'codeql' found — skipping taint analysis."
  echo "[appsec] Install with: gh extension install github/gh-codeql"
  echo "[appsec]           OR: brew install codeql"
  CODEQL_AVAILABLE=false
fi
```

#### Step 2b.2: Detect Language

Map the project's primary language to a CodeQL language identifier:

| Detected file(s) | CodeQL language |
|------------------|----------------|
| `*.py` | `python` |
| `*.js`, `*.ts`, `*.jsx`, `*.tsx` | `javascript` |
| `*.java`, `pom.xml`, `*.gradle` | `java` |
| `*.go`, `go.mod` | `go` |
| `*.cs`, `*.csproj` | `csharp` |
| `*.rb`, `Gemfile` | `ruby` |
| `*.cpp`, `*.c`, `*.h` | `cpp` |
| `*.swift` | `swift` |

```bash
# Detect dominant language by file count
CODEQL_LANG=""
for ext_lang in "py:python" "js:javascript" "ts:javascript" "java:java" "go:go" "cs:csharp" "rb:ruby" "cpp:cpp" "swift:swift"; do
  ext="${ext_lang%%:*}"; lang="${ext_lang##*:}"
  count=$(find . -name "*.${ext}" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l)
  if [[ $count -gt 0 ]]; then CODEQL_LANG="$lang"; break; fi
done

if [[ -z "$CODEQL_LANG" ]]; then
  echo "[appsec] Could not detect a supported CodeQL language — skipping."
  CODEQL_AVAILABLE=false
fi
```

#### Step 2b.3: Create CodeQL Database

```bash
echo "[appsec] Creating CodeQL database (language: ${CODEQL_LANG})..."
$CODEQL_CMD database create .codeql-db \
  --language="${CODEQL_LANG}" \
  --source-root=. \
  --overwrite \
  2>&1 | tail -5 || {
    echo "[appsec] Warning: CodeQL database creation failed — skipping taint analysis."
    CODEQL_AVAILABLE=false
  }
```

Database creation requires a working build environment for compiled languages (Java, C#, C++). For interpreted languages (Python, JS, Ruby) it works without a build step.

#### Step 2b.4: Run Security Analysis

```bash
echo "[appsec] Running CodeQL security-extended analysis..."
$CODEQL_CMD database analyze .codeql-db \
  "codeql/${CODEQL_LANG}-queries:codeql-suites/${CODEQL_LANG}-security-extended.qls" \
  --format=sarif-latest \
  --output="${CODEQL_SARIF}" \
  2>&1 | tail -5 || true
```

#### Step 2b.5: Parse SARIF Output

CodeQL produces SARIF 2.1.0. Key fields:

```json
{
  "runs": [{
    "results": [{
      "ruleId": "py/sql-injection",
      "message": { "text": "..." },
      "locations": [{ "physicalLocation": {
        "artifactLocation": { "uri": "app/db.py" },
        "region": { "startLine": 42 }
      }}],
      "properties": { "severity": "error", "precision": "high" }
    }],
    "tool": { "driver": { "rules": [{
      "id": "py/sql-injection",
      "properties": { "tags": ["security","correctness","external/cwe/cwe-089"] }
    }] }}
  }]
}
```

Severity mapping:

| CodeQL `severity` | Standard |
|-------------------|----------|
| `error` + `precision: high/very-high` | Critical / High |
| `error` + `precision: medium` | High / Medium |
| `warning` | Medium |
| `recommendation` | Low |

For taint-flow findings, extract the full **source → sink** path from `codeFlows` if present — this is CodeQL's differentiating value over Semgrep.

Count findings per severity for use in Phase 3.

---

### Phase 3: Cross-Validation & Consolidated Report *(after Phases 1, 2, 2b complete)*

Skip this phase if `--skip-crossval` was supplied.
If semgrep or codeql was skipped or produced no output, produce a note in the
consolidated report explaining the gap.

#### Step 3.1: Load All Reports

```bash
cat "${REPORT_FILE}"
cat "${SEMGREP_JSON}" 2>/dev/null || echo "{}"
cat "${CODEQL_SARIF}" 2>/dev/null || echo "{}"
```

#### Step 3.2: Cross-Validation Analysis

Build a comparison table:

| Finding | Claude Audit | Semgrep | CodeQL | Final Severity | Status |
|---------|-------------|---------|--------|----------------|--------|
| SQL Injection in auth.py:45 | ✅ | ✅ | ✅ | Critical | CONFIRMED (all 3) |
| CVE-2023-12345 in requests | ❌ | ✅ | ❌ | High | NEW (Semgrep) |
| IDOR in user endpoint | ✅ | ❌ | ❌ | High | NEW (AI) |
| Taint flow: req→db.query | ❌ | ❌ | ✅ | Critical | NEW (CodeQL) |

Confidence tiers:
- **All 3 tools**: highest confidence — include without question
- **2 tools (any combination)**: high confidence — include
- **AI only**: include if business logic / design / multi-file; note why SAST missed it
- **Semgrep only**: include; note that CodeQL may have missed due to language support
- **CodeQL only**: include; add the taint flow path if available

Deduplication rules:
1. Match by **file + line number** (exact) → same finding
2. Match by **vulnerability type within ±5 lines** → same finding
3. Match by **semantic description similarity** → likely same finding

Severity reconciliation — when tools disagree, use the **highest** across all tools
and document each tool's assessment:

| Semgrep severity | Standard |
|-----------------|----------|
| `ERROR` | Critical / High |
| `WARNING` | Medium |
| `INFO` | Low |

For Semgrep-only CVE findings, map CVSS score: ≥9.0 → Critical, ≥7.0 → High,
≥4.0 → Medium, <4.0 → Low.

#### Step 3.3: Gap Analysis and False Positives

Categorise findings into:
- **Confirmed** (multiple tools): highest confidence
- **Semgrep-only**: typically CVEs, SCA, pattern-based code issues
- **CodeQL-only**: typically taint flows and inter-procedural chains that pattern matching misses
- **AI-only**: typically business logic, design flaws, multi-file semantic chains

For each tool-only finding, note *why* the others likely missed it:

| Category | Why Claude missed | Why Semgrep missed | Why CodeQL missed |
|----------|------------------|--------------------|-------------------|
| CVEs / SCA | no CVE DB lookup | n/a | n/a |
| Pattern injection | possible, check context | n/a | n/a |
| Taint flow (cross-file) | possible | single-file / no dataflow | n/a |
| Business logic | n/a | no semantic understanding | rule-based only |
| Multi-file chains | n/a | single-file analysis | may catch if taint-reachable |
| Architecture flaws | n/a | rule-based only | rule-based only |
| Unsupported language | n/a | broad language support | limited language support |

**False Positives Analysis**

Before including a finding in the consolidated report, assess whether it is a
false positive:
- Semgrep: check if the flagged string is in a comment, test file, or example
- Claude: verify with actual code context — does the vulnerable pattern have
  surrounding protections (middleware, ORM, validator) that neutralise the risk?

Document any discarded false positives and the reasoning in the consolidated
report (Part 4 — False Positives Analysis).

#### Step 3.4: Write Consolidated Report

```bash
cat > "${CONSOLIDATED_FILE}" << 'CONSOLIDATEDEOF'
# Consolidated Security Audit Report

## Executive Summary
**Audit Date**: [today]
**Project**: [name]
**Audit Methods**: AI-Driven (Claude /sentinel) + Semgrep SAST + CodeQL Taint Analysis

### Key Findings
- **Total Unique Vulnerabilities**: [N]
- **Confirmed by All 3 Tools**: [N]
- **Confirmed by 2 Tools**: [N]
- **AI-Only**: [N]
- **Semgrep-Only**: [N]
- **CodeQL-Only**: [N]

### Severity Breakdown
| Severity | Count |
|----------|-------|
| 🔴 Critical | X |
| 🟠 High     | X |
| 🟡 Medium   | X |
| 🟢 Low      | X |

---

## Part 1: Confirmed Vulnerabilities
> Issues detected by multiple tools — highest confidence

### [VULN-CONF-001] [Title]
- **File**: `path/to/file:line`
- **Severity**: [Critical/High/Medium/Low]
- **CWE**: CWE-XX
- **OWASP**: A0X:2021
- **Detection**:
  - ✅ Claude: [original finding ID]
  - ✅ Semgrep: rule `rule-id`
  - ✅ CodeQL: rule `codeql/lang-queries:path/to/Rule.ql` (taint path: [source → sink])

**Description**: [what it is and why it matters]

**Evidence**:
```
[code snippet]
```

**Recommendation**: [specific fix with code example]

---

## Part 2: Semgrep-Specific Findings
> Issues detected by Semgrep (SAST/SCA) but not in AI audit

### [VULN-SEM-001] [Title]
- **File**: `path/to/file:line`
- **Severity**: [severity]
- **Semgrep Rule**: `rule-id`
- **Category**: [SCA/SAST/Secrets]
- **CWE**: CWE-XX

**Why Claude missed this**: [likely reason: specific CVE, pattern-based, etc.]

**Description**: [from Semgrep message]

**Recommendation**: [how to fix]

---

## Part 2b: CodeQL-Specific Findings
> Issues detected by CodeQL taint analysis but not found by AI audit or Semgrep

### [VULN-CQL-001] [Title]
- **File**: `path/to/file:line`
- **Severity**: [severity]
- **CodeQL Rule**: `rule-id`
- **CWE**: CWE-XX
- **Taint Flow**: `[source location] → [sanitizer skip / call chain] → [sink location]`

**Why other tools missed this**: [e.g. cross-file dataflow requires inter-procedural analysis]

**Description**: [from CodeQL message]

**Recommendation**: [how to fix — break the taint chain]

---

## Part 3: AI-Specific Findings
> Issues detected by Claude but not flagged by Semgrep or CodeQL

### [VULN-COP-001] [Title]
- **File**: `path/to/file:line`
- **Severity**: [severity]
- **Original ID**: [from SECURITY_AUDIT_REPORT.md]

**Why Semgrep missed this**: [likely reason: business logic, multi-file chain, design flaw]

**Description**: [from AI audit]

**Recommendation**: [from AI audit]

---

## Part 4: False Positives Analysis

### Semgrep False Positives
- [Any Semgrep findings discarded after manual review]

### AI False Positives
- [Any Claude findings where surrounding context neutralises the risk]

---

## Part 5: Dependency Vulnerabilities (SCA)

| Dependency | Version | CVE | Severity | CVSS | Fix Version |
|------------|---------|-----|----------|------|-------------|

### Remediation Commands
```bash
# Python
pip install --upgrade <package>==<fixed_version>

# Node.js
npm audit fix

# Go
go get <module>@<fixed_version>
```

---

## Part 6: Secrets Detected

| Type | File | Line | Severity | Action |
|------|------|------|----------|--------|

**Immediate actions**:
1. Rotate all exposed credentials
2. Scan git history: `gitleaks detect --source=. --log-opts="HEAD~50..HEAD"`
3. Add secret scanning to CI/CD pre-commit hooks

---

## Part 7: Prioritised Remediation Plan

### 🚨 Critical (fix now — within 24 h)

### 🔥 High (fix this week)

### ⚠️ Medium (fix this sprint)

### ℹ️ Low (backlog)

---

## Part 8: Tool Comparison Insights

### Claude Strengths
- ✅ Context-aware analysis
- ✅ Business logic vulnerabilities
- ✅ Architecture and design flaws
- ✅ Multi-file vulnerability chains
- ✅ Custom actionable remediation guidance

### Claude Limitations
- ❌ May miss specific CVEs in dependencies
- ❌ Less comprehensive SCA coverage

### Semgrep Strengths
- ✅ Comprehensive SCA / dependency CVEs
- ✅ Known vulnerability patterns (CWE / OWASP mapped)
- ✅ Consistent, deterministic, fast

### Semgrep Limitations
- ❌ No business logic understanding
- ❌ Cannot detect context-specific issues
- ❌ Rule-based only (no inference)
- ❌ May produce false positives

### CodeQL Strengths
- ✅ Inter-procedural taint analysis (tracks data flow across files)
- ✅ Finds vulnerability chains that pattern matchers miss
- ✅ High-precision results with low false-positive rate
- ✅ CWE / OWASP mapped; SARIF output

### CodeQL Limitations
- ❌ Requires build environment for compiled languages (Java, C#, C++)
- ❌ Slower than Semgrep (minutes vs. seconds)
- ❌ Limited language support vs. Semgrep
- ❌ No SCA / dependency CVE coverage

---

## Part 9: Coverage Metrics

```
Total Files Scanned:        [N]
Total Lines of Code:        [N]
Files with Vulnerabilities: [N]
Vulnerability Density:      [vulns per 1000 LOC]

Claude Detections:    [N]
Semgrep Detections:   [N]
Overlapping:          [N] ([%]%)
Unique to Claude:     [N]
Unique to Semgrep:    [N]
Total Unique Issues:  [N]
```

---

## Part 10: Next Steps

### Immediate (today)
- [ ] Review and validate all Critical findings
- [ ] Rotate any exposed credentials immediately
- [ ] Create tracking tickets for all open findings
- [ ] Notify security team of critical issues

### Short-term (this week)
- [ ] Implement fixes for Critical and High findings
- [ ] Update dependencies to patched versions
- [ ] Add `semgrep scan --config=auto` to CI/CD pipeline
- [ ] Configure pre-commit hooks for secret detection

### Long-term (this month)
- [ ] Address Medium and Low findings
- [ ] Establish regular security audit schedule
- [ ] Track metrics over time; perform quarterly audits

---

## Appendix
- Source: Primary audit report (`reports/security-audit-${TIMESTAMP}.md`)
- Semgrep results: `reports/semgrep-results.json`
- CodeQL results: `reports/codeql-results.sarif`
- OWASP Top 10: https://owasp.org/Top10/
- CWE Database: https://cwe.mitre.org/
- CodeQL query packs: https://docs.github.com/en/code-security/codeql-cli/getting-started-with-the-codeql-cli/about-the-codeql-cli
CONSOLIDATEDEOF
```

The file **must** be written to `${CONSOLIDATED_FILE}` (inside `reports/`).

---

### Phase 4: Risk Score Calculation

After completing the consolidated report, calculate a numeric security score from the
finding counts recorded in the Severity Breakdown table.

Scoring formula (100 = perfect security, 0 = critical risk):
- Start at 100
- Each Critical finding: −15 points
- Each High finding: −8 points
- Each Medium finding: −3 points
- Each Low finding: −1 point
- Minimum score: 0

Score thresholds:

| Score | Risk Level |
|-------|------------|
| 90–100 | 🟢 LOW RISK |
| 70–89 | 🟡 MEDIUM RISK |
| 40–69 | 🟠 HIGH RISK |
| 0–39 | 🔴 CRITICAL RISK |

Render the score as a 20-block progress bar (filled blocks = `score ÷ 5`, rounded down):

```
Security Score: 72/100 [██████████████░░░░░░] MEDIUM RISK
```

Append the scorecard to `${CONSOLIDATED_FILE}` before the Appendix:

```markdown
---

## Security Score

**Score: [SCORE]/100** — [RISK LEVEL]

```
Security Score: [SCORE]/100 [████████████████░░░░] [RISK LEVEL]
```

| Severity | Count | Penalty |
|----------|-------|---------|
| 🔴 Critical | [N] | −[N×15] |
| 🟠 High     | [N] | −[N×8]  |
| 🟡 Medium   | [N] | −[N×3]  |
| 🟢 Low      | [N] | −[N×1]  |
| **Total deducted** | | **−[total]** |
```

---

### Phase 5: Remediation Reference

This phase is **reference material** — use it when writing recommendations in
the reports above. Do not execute these examples; adapt them to the actual
vulnerable code found in the target project.

#### Authentication Hardening

**Password hashing** — use bcrypt (min cost 12) or argon2id:

```python
# Python
import bcrypt
hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12))
valid  = bcrypt.checkpw(password.encode(), hashed)
```

```javascript
// Node.js
const bcrypt = require('bcrypt');
const hash  = await bcrypt.hash(password, 12);
const valid = await bcrypt.compare(password, hash);
```

**Rate limiting** — cap auth endpoints:

```javascript
// Node.js / Express
const rateLimit = require('express-rate-limit');
app.post('/login', rateLimit({ windowMs: 15*60*1000, max: 5 }), loginHandler);
```

```python
# Flask
from flask_limiter import Limiter
limiter = Limiter(app, key_func=lambda: request.remote_addr)
@app.route('/login', methods=['POST'])
@limiter.limit('5 per 15 minutes')
def login(): ...
```

#### Secrets Management

**Never hardcode secrets.** Use environment variables at minimum; prefer a
secrets manager:

```python
# ❌ Bad
API_KEY = 'sk-1234567890'

# ✅ Good — env var
import os
API_KEY = os.environ['API_KEY']  # raises KeyError if missing

# ✅ Better — AWS Secrets Manager
import boto3, json
def get_secret(name):
    client = boto3.client('secretsmanager', region_name='ap-southeast-2')
    return json.loads(client.get_secret_value(SecretId=name)['SecretString'])
```

#### Input Validation

```python
# Python — Pydantic
from pydantic import BaseModel, EmailStr, Field
class UserInput(BaseModel):
    email: EmailStr
    name: str = Field(min_length=2, max_length=100)
```

```javascript
// Node.js — Zod
import { z } from 'zod';
const schema = z.object({ email: z.string().email(), name: z.string().min(2).max(100) });
const result = schema.safeParse(req.body);
if (!result.success) return res.status(400).json(result.error);
```

#### XSS Prevention

```python
# Python — markupsafe / bleach
from markupsafe import escape
safe = escape(user_input)
```

```javascript
// Node.js — sanitize-html
const sanitizeHtml = require('sanitize-html');
const clean = sanitizeHtml(userInput, { allowedTags: ['b','i','em','strong'] });
```

#### Security Headers (Node.js / Helmet)

```javascript
const helmet = require('helmet');
app.use(helmet({
  contentSecurityPolicy: { directives: { defaultSrc: ["'self'"], scriptSrc: ["'self'"] } },
  hsts: { maxAge: 31536000, includeSubDomains: true }
}));
```

---

### Phase 6: Final Summary

After writing both report files, output a brief terminal summary:

```
[sentinel] Security audit complete.
[sentinel] ─────────────────────────────────────────────────────
[sentinel]   Target:         <absolute path>
[sentinel]   AI findings:    X critical, X high, X medium, X low
[sentinel]   Semgrep:        X findings (or: skipped)
[sentinel]   CodeQL:         X findings (or: skipped / unsupported language)
[sentinel]   Total unique:   X issues (X confirmed by multiple tools)
[sentinel] ─────────────────────────────────────────────────────
[sentinel]   Security Score: [SCORE]/100 [████████████░░░░░░░░] [RISK LEVEL]
[sentinel] ─────────────────────────────────────────────────────
[sentinel]   Reports (./reports/):
[sentinel]     ${REPORT_FILE}
[sentinel]     ${CONSOLIDATED_FILE}
[sentinel]     ${SEMGREP_JSON}
[sentinel]     ${CODEQL_SARIF}
[sentinel] ─────────────────────────────────────────────────────
[sentinel]   Next: address Critical and High findings first.
[sentinel]   Run /sentinel --path . to re-audit after fixes.
```

---

## Analysis Guidelines

### Severity Matrix

| Severity | Description | Response Time |
|----------|-------------|---------------|
| 🔴 Critical | RCE, auth bypass, exposed secrets | Immediate |
| 🟠 High | Data breach, privilege escalation | Within 24 h |
| 🟡 Medium | Limited-impact exploits | Within 1 week |
| 🟢 Low | Minor concerns, hygiene issues | Next sprint |

### Audit Priorities

1. **Authentication / Authorisation**: can attackers bypass access controls?
2. **Injection**: can attackers inject malicious code or queries?
3. **Data Protection**: is sensitive data (PII, credentials) properly protected?
4. **Dependencies**: are there known CVEs in third-party packages?
5. **Configuration**: is the system properly hardened?

Every audit should:
- Find vulnerabilities before attackers do
- Prioritise by real-world risk and blast radius
- Provide clear, actionable remediation with code examples
- Track fixes to completion
- Improve overall security posture over time
