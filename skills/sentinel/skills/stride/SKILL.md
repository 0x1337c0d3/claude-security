---
name: stride
description: >
  STRIDE threat modeling. Use when the user asks to "run STRIDE", "threat model
  with STRIDE", "check for spoofing/tampering/repudiation/info disclosure/DoS/
  privilege escalation", or invokes /sentinel:stride. Analyzes the codebase across
  all 6 STRIDE threat categories (Spoofing, Tampering, Repudiation, Information
  Disclosure, Denial of Service, Elevation of Privilege).
---

# STRIDE Threat Model

Analyze the codebase across all 6 STRIDE threat categories. Each category maps
to a violated security property and a set of concrete code patterns to detect.

## Framework Reference

Load `../../references/stride.md` for the full STRIDE category definitions,
applicable controls, CWE mappings, and OWASP cross-references.

## Usage

```
/sentinel:stride                          # Full STRIDE analysis (all 6 categories)
/sentinel:stride --only S,E               # Only Spoofing and Elevation of Privilege
/sentinel:stride --depth deep             # Trace data flows across trust boundaries
/sentinel:stride --fix                    # Include fix suggestions inline
```

## Category Overview

| Letter | Category | Security Property | Finding Prefix | Focus |
|--------|----------|-------------------|----------------|-------|
| S | Spoofing | Authentication | `SPOOF` | Token forgery, session fixation, credential theft, identity impersonation |
| T | Tampering | Integrity | `TAMP` | SQL injection, parameter tampering, MITM, file modification, XSS |
| R | Repudiation | Non-repudiation | `REPUD` | Missing audit logs, log tampering, insufficient forensic evidence |
| I | Information Disclosure | Confidentiality | `DISC` | Error message leaks, sensitive data in logs, cleartext transmission |
| D | Denial of Service | Availability | `DOS` | Resource exhaustion, ReDoS, no rate limiting, decompression bombs |
| E | Elevation of Privilege | Authorization | `PRIV` | Broken access control, IDOR, JWT manipulation, role confusion |

## Workflow

### Step 1 — Scope

Default scope: full codebase. Build a focused file list for each category:

| Category | File Patterns to Prioritize |
|----------|---------------------------|
| S - Spoofing | Auth controllers, session middleware, token validation, login/register routes |
| T - Tampering | Input handlers, database queries, API endpoints, file operations |
| R - Repudiation | Logging config, audit trail, transaction records, security event handlers |
| I - Info Disclosure | Error handlers, API responses, log statements, config files, env vars |
| D - DoS | Input parsers, regex patterns, resource allocation, file uploads, rate limiting |
| E - Privilege Escalation | Authorization middleware, role checks, admin routes, RBAC config |

### Step 2 — Analyze Each Category

Work through each relevant category (all 6 by default, or `--only` selection).

For each category, look for the patterns below and produce findings.

---

### S — Spoofing Patterns

- JWT with `alg: none` accepted or algorithm not validated
- Session tokens generated with `Math.random()` or non-cryptographic RNG
- Session fixation: session ID not rotated after login
- Password comparison with `==` instead of constant-time comparison
- OAuth `state` parameter missing or not validated
- Token expiry not enforced (no `exp` claim check)
- Cookie missing `HttpOnly`, `Secure`, or `SameSite` flags
- Auth bypass via HTTP method override or `X-HTTP-Method-Override`

---

### T — Tampering Patterns

- User input directly concatenated into SQL queries (SQLi)
- User input reflected in HTML without encoding (XSS)
- Server-side template injection (user input in template strings)
- Command injection (user input in shell commands, `exec`, `system`)
- File path traversal (`../` in file operations)
- Mass assignment: request body bound to model without allowlist
- Prototype pollution in JavaScript
- Deserialization of untrusted data without type/integrity checks

---

### R — Repudiation Patterns

- Security-sensitive actions (login, password change, payment) not logged
- Logs do not include: user identity, timestamp, IP, action, outcome
- Application-level log deletion or modification is possible
- No tamper-evident logging (logs writable by application process)
- Admin actions not recorded in audit log
- Log aggregation to remote store not configured

---

### I — Information Disclosure Patterns

- Stack traces or exception details returned in production responses
- Internal hostnames, IPs, or paths in error messages
- Sensitive fields (passwords, tokens, SSNs) included in API responses
- Secrets or credentials logged
- Debug endpoints active in production (`/debug`, `/metrics` with internals)
- Directory listing enabled on static file server
- Source maps exposed in production build

---

### D — Denial of Service Patterns

- Regular expressions vulnerable to catastrophic backtracking (ReDoS)
- No rate limiting on authentication endpoints
- No maximum payload size enforced on file upload or JSON body
- Recursive or deeply nested input parsing without depth limit
- Unbounded database queries (no `LIMIT`, no pagination)
- XML/YAML parsing without entity expansion protection (XXE, Billion Laughs)
- No timeout on external HTTP calls
- Resource-intensive operations callable without authentication

---

### E — Elevation of Privilege Patterns

- Authorization check missing on sensitive endpoints (only authentication checked)
- IDOR: resource accessed by ID without ownership validation
- Role check performed on client side only
- Horizontal privilege escalation: user can access other users' data by changing ID
- Admin routes accessible to non-admin roles
- JWT `role` or `isAdmin` claim modifiable without signature verification
- RBAC misconfiguration: overly permissive wildcard permissions
- Privileged operation available via indirect reference (e.g., batch API)

---

### Step 3 — Findings Format

For each finding:

```
[STRIDE-XXX] Title
Category: [S/T/R/I/D/E] | Severity: CRITICAL/HIGH/MEDIUM/LOW | CWE: CWE-XXX
Location: file:line | Confidence: HIGH/MEDIUM/LOW

STRIDE category: [Category name] — [Security property violated]

Attack scenario:
1. [Attacker action]
2. [What the code fails to do]
3. [Impact]

Evidence:
  [vulnerable code snippet]

Fix:
  [corrected code + one-line explanation]

OWASP: [OWASP 2021 category] | Compliance: [relevant frameworks]
```

### Step 4 — Per-Element Threat Matrix

Build a matrix showing which STRIDE categories produced findings per component:

```
| Component | S | T | R | I | D | E | Findings |
|-----------|---|---|---|---|---|---|----------|
| Auth controller | X | | | | | X | SPOOF-001, PRIV-002 |
| API gateway | | X | | X | X | | TAMP-001, DISC-003 |
```

### Step 5 — Report

Produce findings ranked by severity. Then the threat matrix. Then write report:

```bash
OUTPUT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
REPORT_FILE="${OUTPUT_DIR}/stride-$(date +%Y%m%d).md"
```

Save the full report to `${REPORT_FILE}`.

### Step 6 — Sentinel Integration

If Sentinel has run recently (check for `reports/security-*.md`):
- Cross-reference STRIDE findings with Sentinel SENTINEL-XXX findings
- Map each Sentinel finding to its STRIDE category
- Note findings Sentinel found but STRIDE did not (tool-detected vs architecture)
- Note findings STRIDE found but Sentinel did not (logic/architecture vs code patterns)
- Produce combined summary: "Sentinel detected N tool-level findings. STRIDE identified M architectural threats. X overlap."

## Severity Guidance

| Severity | Criteria |
|----------|----------|
| CRITICAL | Auth bypass (S/E), RCE via injection (T), mass data disclosure (I) |
| HIGH | SQLi, stored XSS, IDOR on sensitive data, no rate limit on auth |
| MEDIUM | Reflected XSS, log gaps, excessive data exposure, ReDoS on public input |
| LOW | Missing security headers, verbose errors, minor info disclosure |
