---
name: sentinel
description: "Orchestrates security scanning: Semgrep SAST, CodeQL taint analysis, gitleaks secrets scanning, dependency audits, and AI-driven OWASP code review. Consolidates findings with cross-validation, calculates risk scores, and proposes code fixes. Invoke with /sentinel."
---

# Sentinel — Security Orchestrator

## When to Invoke

- User requests security scan, vulnerability audit, or security review
- User says "check for secrets", "find security issues", "scan dependencies", "security audit"
- Before production deployments
- After adding new dependencies or authentication flows
- User invokes `/sentinel`

## Modes

| Mode | Trigger | What Runs |
|------|---------|-----------|
| **quick** | `/sentinel` or `/sentinel quick` | Full scan: SAST + CodeQL + secrets + package audit + dependency freshness + AI OWASP review |
| **fix** | `/sentinel fix` | Re-analyze existing report and propose fixes |
| **verify** | `/sentinel verify` | Re-scan to confirm fixes resolved findings |
| **score** | `/sentinel score` | Calculate and display security scorecard only |
| **outdated** | `/sentinel outdated` | Check for outdated dependencies (major/minor/patch behind) |

---

## Execution Protocol

### Phase 1 — Prerequisites Check

Run `scripts/check-prereqs.sh` from the skill directory. This checks for:
- `jq` (required for JSON processing)
- `semgrep` — SAST scanner
- `gitleaks` — secrets scanner
- `codeql` — taint analysis (optional; skip gracefully if missing)
- Package audit tools: `npm audit`, `pip-audit`, `composer audit`
- Ecosystem tools: `govulncheck` (Go), `bundle-audit` (Ruby), `cargo-audit` (Rust), `dotnet` (.NET), `mvn`/`gradle` (Java), `trivy` (containers)

Report which tools are available and which are missing with installation instructions.
If no tools are available at all, stop and provide installation guidance.
If at least one tool is available, proceed with what's available.

### Phase 2 — Stack Detection

Run `scripts/detect-stack.sh` in the target project directory. Outputs JSON:

```json
{
  "languages": ["javascript", "typescript"],
  "frameworks": ["express", "react"],
  "package_manager": "npm",
  "has_dockerfile": true,
  "has_docker_compose": true,
  "entry_points": ["src/index.ts", "src/app.ts"]
}
```

### Phase 3 — Security Inventory (AI-Driven)

Before running tools, build a quick inventory by reading key files (package manifests, entry points, auth modules, config files):

```markdown
## Security Inventory
### Authentication
- Type: [JWT/Session/OAuth/API Key/None]
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
- Method: [Env vars/Secrets manager/Hardcoded]

### Infrastructure
- HTTPS enforced: [Yes/No/Unknown]
- Security headers: [Yes/No/Partial]
- Rate limiting: [Implemented/None]
```

### Phase 4 — Parallel Tool Scanning

Run all available tools in parallel:

**SAST (Semgrep):**
```bash
scripts/run-sast.sh <project-path> <language>
```
Uses language-specific rules from `configs/semgrep-rules/`.

**Secrets (gitleaks):**
```bash
scripts/run-secrets.sh <project-path>
```
Scans entire repository for hardcoded secrets, API keys, tokens.

**SCA (Package Audit):**
```bash
scripts/run-sca.sh <project-path> <package-manager>
```
Runs the appropriate audit command for the detected package manager.

**Dependency Freshness:**
```bash
scripts/run-outdated.sh <project-path> <package-manager>
```
Checks for outdated dependencies (MAJOR, MINOR, PATCH behind).

**CodeQL Taint Analysis (if available):**
```bash
scripts/run-sast-codeql.sh <project-path> <language>
```
Runs inter-procedural taint analysis. Exits silently with empty findings if `codeql` is not installed. Adds `taint_flow` field showing source→sink data paths for inter-file vulnerabilities.

### Phase 5 — AI-Driven OWASP Code Review

Read source files (prioritise routes, controllers, auth modules, DB access layers) and assess each OWASP Top 10 category. Run these pattern checks first to guide file selection:

```bash
# Hardcoded secrets
grep -rn -E "(password|secret|api_key|token|auth)\s*=\s*['\"][^'\"]{6,}['\"]" \
  --include="*.py" --include="*.js" --include="*.ts" --include="*.go" \
  --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null | head -40

# Injection patterns
grep -rn -E "(SELECT|INSERT|UPDATE|DELETE).*[\+\$\{]|eval\(|exec\(|shell_exec\(" \
  --include="*.py" --include="*.js" --include="*.ts" --include="*.php" \
  --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null | head -20

# Private key material
grep -rn -E "BEGIN (RSA|EC|DSA|OPENSSH|PGP) PRIVATE KEY" \
  --exclude-dir=.git . 2>/dev/null | head -10
```

For each finding, record an AI finding as `VULN-NNN` (sequential, zero-padded to 3 digits):
- **ID**, **Title**, **File:Line**, **Severity**, **OWASP Category**, **Description**, **PoC/Evidence**, **Recommendation**

OWASP categories to cover:

| Category | Key Checks |
|----------|-----------|
| **A01 Broken Access Control** | IDOR, missing authz on endpoints, CORS, path traversal |
| **A02 Cryptographic Failures** | HTTP transmission, weak algos (MD5/SHA1), hardcoded keys, PII in logs |
| **A03 Injection** | SQL, NoSQL, command, LDAP injection; parameterised query usage |
| **A04 Insecure Design** | Missing rate limiting, no account lockout, weak password policy |
| **A05 Security Misconfiguration** | Default creds, verbose errors, missing security headers, debug mode |
| **A06 Vulnerable Components** | Outdated deps with CVEs; unmaintained packages |
| **A07 Authentication Failures** | Brute-force protection, session tokens in URLs, no logout invalidation |
| **A08 Software Integrity Failures** | Missing lock files, insecure CI/CD, unsafe deserialization |
| **A09 Logging Failures** | No security event logging, sensitive data in logs |
| **A10 SSRF** | User-controlled URLs in server requests, missing allowlist |

Required security headers to verify:

| Header | Recommended Value |
|--------|------------------|
| `Content-Security-Policy` | `default-src 'self'; script-src 'self'` |
| `X-Frame-Options` | `DENY` or `SAMEORIGIN` |
| `X-Content-Type-Options` | `nosniff` |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |

### Phase 6 — Cross-Validation

Merge tool findings with AI findings into a unified list.

Build a comparison table to track what each source found:

| Finding | AI | Semgrep | CodeQL | Confidence | Status |
|---------|-----|---------|--------|------------|--------|
| SQL Injection auth.py:45 | ✅ | ✅ | ✅ | **All 3** | CONFIRMED |
| CVE-2023-12345 in requests | ❌ | ✅ | ❌ | Semgrep | NEW |
| IDOR in user endpoint | ✅ | ❌ | ❌ | AI | NEW (design flaw) |
| Taint flow: req→db.query | ❌ | ❌ | ✅ + flow | CodeQL | NEW |

**Confidence tiers:**
- **All 3 tools**: highest confidence — include without question
- **2 tools**: high confidence — include
- **AI only**: include for business logic, design flaws, multi-file chains; note why SAST missed it
- **Semgrep only**: include with note
- **CodeQL only**: include; add taint flow path

**Deduplication rules:**
1. Same file + line → same finding
2. Same vulnerability type within ±5 lines → same finding
3. Semantically equivalent description → same finding

**Severity reconciliation**: when tools disagree, use the highest severity across all sources.

After cross-validation, assign unified `SENTINEL-XXX` IDs (sequentially, zero-padded to 3 digits) to all confirmed findings, sorted by severity: CRITICAL → HIGH → MEDIUM → LOW.

Run `scripts/calculate-score.sh` — but **only after assigning SENTINEL IDs** — by constructing a JSON input with the consolidated findings.

### Phase 7 — Risk Score Calculation

Run `scripts/calculate-score.sh` on the consolidated findings JSON.

Scoring formula (100 = perfect, 0 = critical risk):
- Start at 100
- Each CRITICAL finding: −15 points
- Each HIGH finding: −8 points
- Each MEDIUM finding: −3 points
- Each LOW finding: −1 point
- Minimum: 0

Display as: `Security Score: 72/100 [██████████░░░░] MEDIUM RISK`

Thresholds:
- 90–100: LOW RISK
- 70–89: MEDIUM RISK
- 40–69: HIGH RISK
- 0–39: CRITICAL RISK

### Phase 8 — Report Generation

Generate the report following the structure in `templates/report.md`.
Save to `reports/security-YYYY-MM-DD.md` in the project root.

The report must include:
1. **Security Inventory** (from Phase 3)
2. **Scorecard** with score, risk level, and severity breakdown
3. **Cross-validation summary** table
4. **Findings** — one section per SENTINEL-XXX finding:
   - CWE, OWASP category, source tool(s), file:line
   - Description, Impact, PoC/Evidence
   - Proposed fix (before/after diff)
   - Compliance mapping (SOC 2, PCI-DSS, HIPAA where relevant)
   - CodeQL taint flow path (if available)
5. **False positives** noted and dismissed with reasoning
6. **Recommendations** summary

If a previous report exists in `reports/`, perform **baseline diff**:
- **NEW**: findings not in previous report
- **FIXED**: findings in previous report but not current
- **PERSISTENT**: findings in both reports

### Phase 9 — User Interaction

Present a summary table to the user:
- Severity counts, security score, NEW/FIXED/PERSISTENT breakdown

Then ask: **"How would you like to proceed?"**

Options:
1. **Review findings** — Walk through each finding with explanation and fix
2. **Apply fixes** — One by one / by severity / report only
3. **Create GitHub issues** — One issue per finding using this format:

```markdown
## [SEVERITY] TITLE

**Finding ID:** SENTINEL-XXX
**CWE:** CWE-XX | **OWASP:** A0X:2021
**Location:** `file:line`

### Description
[what it is and why it matters]

### Impact
[what an attacker could achieve]

### Proposed Fix
\`\`\`diff
[before/after diff]
\`\`\`

### Compliance
[SOC 2 / PCI-DSS / HIPAA references]

### References
- [CWE-XX](https://cwe.mitre.org/data/definitions/XX.html)
- [OWASP A0X:2021](https://owasp.org/Top10/)
```

4. **Generate SARIF** — Output in SARIF format for GitHub Security tab
5. **Export compliance report** — Compliance-focused summary

### Phase 10 — Fix Verification (Optional)

After fixes are applied, offer to re-run the scan to verify resolution.
Compare before/after scores and show improvement.

---

## Important Constraints

- ALWAYS ask before creating GitHub issues (they notify the team)
- ALWAYS ask before applying code changes
- Reports may contain sensitive exploit details — warn before committing to public repos

---

## Compliance Mapping Reference

| OWASP 2021 | SOC 2 | PCI-DSS | CWE Examples |
|------------|-------|---------|--------------|
| A01 Broken Access Control | CC6.1, CC6.3 | 6.5.8, 7.1 | 22, 284, 285, 639 |
| A02 Cryptographic Failures | CC6.1, CC6.7 | 3.4, 4.1, 6.5.3 | 259, 327, 328 |
| A03 Injection | CC6.1 | 6.5.1 | 20, 74, 79, 89 |
| A04 Insecure Design | CC3.2, CC5.2 | 6.3 | 209, 256, 501 |
| A05 Security Misconfiguration | CC6.1, CC7.1 | 2.2, 6.5.10 | 16, 611 |
| A06 Vulnerable Components | CC6.1 | 6.3.2 | 1035 |
| A07 Auth Failures | CC6.1, CC6.2 | 6.5.10, 8.1 | 287, 384 |
| A08 Data Integrity Failures | CC7.2 | 6.5.8 | 345, 502 |
| A09 Logging Failures | CC7.2, CC7.3 | 10.1 | 117, 223, 778 |
| A10 SSRF | CC6.1 | 6.5.9 | 918 |

---

## Available Sub-Skills

| Command | Description |
|---------|-------------|
| `/sentinel:audit` | Deep AI reasoning on findings — attack chains, false positive analysis, IaC review |
| `/sentinel:red-team` | Adversarial analysis from 6 attacker personas (script kiddie, insider, organized crime, nation state, hacktivist, supply chain) |
| `/sentinel:stride` | STRIDE threat modeling — Spoofing, Tampering, Repudiation, Info Disclosure, DoS, Elevation of Privilege |
| `/sentinel:race-conditions` | Detect TOCTOU, double-spend, check-then-act, non-atomic operations |
| `/sentinel:business-logic` | Find workflow bypass, negative amounts, coupon abuse, state machine manipulation |
| `/sentinel:api` | OWASP API Top 10 — BOLA, mass assignment, missing rate limiting, excessive data exposure |
| `/sentinel:attack-surface` | Map all entry points, classify by exposure level, identify shadow/unauthenticated endpoints |
