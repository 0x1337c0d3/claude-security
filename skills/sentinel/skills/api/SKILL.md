---
name: api
description: >
  API security audit aligned with OWASP API Top 10. Use when the user asks to
  "check API security", "audit REST API", "find BOLA vulnerabilities", "check
  for mass assignment", "analyze API rate limiting", "detect excessive data
  exposure", or mentions "API security", "BOLA", "IDOR", "mass assignment",
  "rate limiting", "broken function-level authorization", "excessive data
  exposure", or "OWASP API Top 10". Invoke with /sentinel:api.
---

# API Security (API)

Analyze REST and RPC APIs for security vulnerabilities aligned with the OWASP
API Security Top 10 (2023), including Broken Object-Level Authorization (BOLA),
mass assignment, missing rate limiting, broken function-level authorization, and
excessive data exposure.

## Framework Context

OWASP API Security Top 10 (2023):
- API1:2023 Broken Object-Level Authorization (BOLA)
- API2:2023 Broken Authentication
- API3:2023 Broken Object Property-Level Authorization
- API4:2023 Unrestricted Resource Consumption
- API5:2023 Broken Function-Level Authorization
- API6:2023 Unrestricted Access to Sensitive Business Flows
- API7:2023 Server-Side Request Forgery
- API8:2023 Security Misconfiguration
- API9:2023 Improper Inventory Management
- API10:2023 Unsafe Consumption of APIs

Key CWEs:
- CWE-639: Authorization Bypass Through User-Controlled Key (BOLA)
- CWE-915: Improperly Controlled Modification of Dynamically-Determined Object Attributes
- CWE-770: Allocation of Resources Without Limits (rate limiting)
- CWE-862: Missing Authorization (function-level auth)
- CWE-200: Exposure of Sensitive Information (excessive data)

## Workflow

### Step 1 — Identify API Files

Prioritize these file patterns:

- Route/endpoint definitions (`**/routes/**`, `**/api/**`, `**/endpoints/**`)
- Controllers and handlers (`**/controllers/**`, `**/handlers/**`, `**/views/**`)
- Serializers and DTOs (`**/serializers/**`, `**/dto/**`, `**/schemas/**`)
- Middleware (`**/middleware/**`, `**/middlewares/**`)
- Rate limiting configuration (`**/config/**`, `**/limiters/**`)

### Step 2 — Run Available Scanners

Run if available:
- `semgrep scan --config auto --json --quiet <target>` — filter for BOLA, mass assignment, authorization patterns
- `bandit -r <target> -f json -q` — Python API security patterns
- `brakeman -q -f json -o /dev/stdout` — Rails mass assignment, authorization

### Step 3 — Manual Code Analysis

#### 1. BOLA — Broken Object-Level Authorization (API1:2023)
API endpoints that accept resource IDs and return data without verifying the
requesting user owns or is authorized to access that resource.

```python
# Vulnerable: no ownership check — any authenticated user can access any order
@app.route('/api/orders/<order_id>')
@require_auth
def get_order(order_id):
    return Order.get(order_id)  # Missing: verify order belongs to current user
```

#### 2. Mass Assignment (API3:2023)
Request body fields bound directly to model attributes without explicit allowlisting.

```javascript
// Vulnerable: attacker can set role, isAdmin, balance
const user = await User.create(req.body);  // all fields accepted
// Fix: User.create({ name: req.body.name, email: req.body.email })
```

#### 3. Missing Rate Limiting (API4:2023)
No rate limiting on authentication, data-intensive, or mutation endpoints.

```javascript
// Vulnerable: unlimited login attempts
app.post('/api/auth/login', async (req, res) => {
    const user = await authenticate(req.body);  // no rate limit
    ...
});
```

#### 4. Broken Function-Level Authorization (API5:2023)
Admin or privileged endpoints accessible to regular users because they check
authentication but not authorization role/permissions.

```python
# Vulnerable: checks login but not admin role
@app.route('/api/admin/users')
@require_login
def list_all_users():
    return User.query.all()  # Missing: @require_admin
```

#### 5. Excessive Data Exposure (API3:2023)
API responses include sensitive fields the client does not need.

```javascript
// Vulnerable: returns password hash, internal tokens, PII
res.json(await User.findById(req.params.id));
// Fix: res.json({ id: user.id, name: user.name, email: user.email })
```

#### 6. Missing Input Validation
API endpoints accept unbounded inputs with no max length or type validation.

```python
# Vulnerable: no max length on search term (ReDoS potential)
results = db.search(req.query.get('q'))
```

#### 7. API Versioning / Shadow Endpoints (API9:2023)
Deprecated API versions still routed and accessible. Check for:
- `/api/v1/` still active when `/api/v2/` is current
- Admin endpoints not in OpenAPI spec
- Debug endpoints active in production

### Step 4 — Findings Format

```
[API-XXX] Title
Severity: CRITICAL/HIGH/MEDIUM/LOW | OWASP API: API1:2023/API3:2023/...
Location: file:line | Confidence: HIGH/MEDIUM/LOW

OWASP API category: [Category name]

Attack scenario:
1. [Attacker sends crafted request]
2. [Missing control in code]
3. [Data/access obtained]

Evidence:
  [vulnerable code snippet]

Fix:
  [corrected code with ownership check / allowlist / rate limit]

CWE: [CWE-XXX] | Sentinel OWASP mapping: [OWASP 2021 category]
```

## Severity Guidance

| Severity | Criteria |
|----------|----------|
| CRITICAL | BOLA on sensitive data (financial, medical, PII), mass assignment on role/privilege fields |
| HIGH | BOLA on user-scoped data, missing auth on admin endpoints, mass assignment on price/status |
| MEDIUM | Missing rate limiting on auth endpoints, excessive data exposure of non-critical fields |
| LOW | Minor data over-exposure, rate limit too generous but present |

## Sentinel Integration

API security findings complement Sentinel's SAST scan. Sentinel's semgrep rules
catch some injection and auth issues in API handlers; this skill adds
authorization logic, data exposure, and rate limiting checks Sentinel misses.
Map findings to SENTINEL-XXX findings where they overlap. API findings map to
OWASP A01 (Broken Access Control), A04 (Insecure Design), and A05 (Misconfiguration).
