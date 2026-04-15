# Security Report — [PROJECT NAME]

**Date:** [SCAN DATE]
**Skill:** [e.g. Sentinel / sentinel:stride / sentinel:red-team]
**Stack:** [DETECTED STACK]
**Tools Used:** [e.g. semgrep, gitleaks, codeql, npm-audit]
**Tools Unavailable:** [any tools that were skipped and why]

---

## Security Inventory

| Area | Status | Detail |
|------|--------|--------|
| Authentication | [JWT/Session/OAuth/None] | [e.g. bcrypt hashing, no MFA] |
| Authorization | [RBAC/ABAC/None] | [coverage: fine/coarse/missing] |
| Data Protection | [Yes/Partial/No] | [encryption at rest/in transit] |
| Secrets Management | [Env vars/Hardcoded/Secrets manager] | — |
| HTTPS | [Enforced/Not enforced] | — |
| Security Headers | [Present/Partial/Missing] | [list missing headers] |
| Rate Limiting | [Yes/No] | — |

---

## Security Scorecard

**Score: [SCORE]/100 — [RISK LEVEL]**

`[score bar, e.g. ██████████░░░░]`

| Severity | Count | Points Deducted |
|----------|-------|-----------------|
| CRITICAL | [N] | −[N×15] |
| HIGH | [N] | −[N×8] |
| MEDIUM | [N] | −[N×3] |
| LOW | [N] | −[N×1] |

<!-- If a previous report exists, include this section -->
<!-- ## Changes Since Last Scan ([PREVIOUS DATE])
| Status | Count |
|--------|-------|
| New | [N] |
| Fixed | [N] |
| Persistent | [N] |
**Score Change:** [+N / −N] -->

---

## Cross-Validation Summary

<!-- Omit this section for sub-skills that don't run multiple tools -->

| Finding | AI | Semgrep | CodeQL | Confidence | Status |
|---------|----|---------|--------|------------|--------|
| [description file:line] | ✅/❌ | ✅/❌ | ✅/❌ | All 3 / 2 tools / AI only / ... | CONFIRMED/NEW |

---

## Findings

<!-- One section per finding, sorted CRITICAL → HIGH → MEDIUM → LOW -->

### [[SEVERITY]] [TITLE]

- **ID:** [FINDING-ID] — e.g. SENTINEL-001, STRIDE-SPOOF-001, RT-SK-001
- **File:** [file/path.ext]:[line]
- **CWE:** [CWE-XX]
- **OWASP:** [A0X:2021]
- **Source:** [semgrep / codeql / gitleaks / ai / multiple]
- **Status:** [confirmed / ai-only / tool-only]

<!-- For CodeQL taint findings, include: -->
<!-- **Taint Flow:** `source/file.ext:10 → handler.ext:45 → db/query.ext:89` -->

#### Description

[What the vulnerability is and why it matters in the context of this codebase.]

#### Impact

[What an attacker could achieve if this is exploited — be specific to this codebase.]

#### Evidence

```
[code snippet or grep output confirming the issue]
```

#### Proposed Fix

```diff
- [vulnerable code]
+ [safe replacement]
```

#### Compliance

[SOC 2 Trust Service Criteria / PCI-DSS requirement / HIPAA safeguard — only include relevant frameworks]

---

## False Positives

[List any tool findings dismissed after manual review, with reasoning.]

| Finding | Tool | Reason Dismissed |
|---------|------|-----------------|
| [description] | [semgrep/codeql] | [e.g. pattern in test file, ORM protects against injection] |

---

## Recommendations

[3–5 highest-priority actions. Include specific commands where applicable.]

1. **[Critical/High priority action]** — [specific guidance]
2. ...

---

## Appendix: Tool Versions

[Output of `semgrep --version`, `gitleaks version`, `codeql version`, etc.]
