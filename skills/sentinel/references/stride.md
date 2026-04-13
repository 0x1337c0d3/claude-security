# STRIDE Threat Modeling Framework

STRIDE is a threat modeling methodology developed by Microsoft. It identifies
six categories of security threats, each mapped to a violated security property.

---

## Categories

### S — Spoofing Identity
**Security property violated**: Authentication

**Definition**: Impersonating something or someone else.

**Examples**:
- Forging authentication tokens (JWT, cookies, session IDs)
- ARP spoofing, DNS spoofing
- Replay attacks using captured credentials
- Phishing — impersonating a trusted entity

**Applicable Controls**:
- Strong authentication (MFA, certificate-based)
- Mutual TLS for service-to-service communication
- Secure token generation and validation

**CWEs**: CWE-287, CWE-290, CWE-294, CWE-295, CWE-346, CWE-384

---

### T — Tampering with Data
**Security property violated**: Integrity

**Definition**: Modifying data or code without authorization.

**Examples**:
- SQL injection modifying database records
- Parameter tampering via URL or form fields
- Man-in-the-middle attacks modifying data in transit
- Code injection (XSS, SSTI, command injection)

**Applicable Controls**:
- Input validation and parameterised queries
- Data integrity checks (HMAC, digital signatures)
- Principle of least privilege for file/database access
- Encryption in transit (TLS)

**CWEs**: CWE-20, CWE-74, CWE-79, CWE-89, CWE-94, CWE-345

---

### R — Repudiation
**Security property violated**: Non-repudiation

**Definition**: Claiming to not have performed an action.

**Examples**:
- Performing a transaction and then denying it
- Deleting audit logs to cover tracks
- Manipulating log entries
- Missing audit trails for high-value operations

**Applicable Controls**:
- Comprehensive audit logging (who, what, when, from where)
- Log integrity protection (append-only, remote logging)
- Non-repudiation through digital signatures

**CWEs**: CWE-117, CWE-223, CWE-532, CWE-778

---

### I — Information Disclosure
**Security property violated**: Confidentiality

**Definition**: Exposing information to unauthorized individuals.

**Examples**:
- Error messages revealing internal details (stack traces, DB schema)
- Sensitive data in logs, URLs, or browser history
- Verbose API responses exposing internal fields
- Unencrypted data in transit or at rest

**Applicable Controls**:
- Generic error messages in production
- Minimum necessary data in API responses
- Encryption at rest and in transit

**CWEs**: CWE-200, CWE-209, CWE-312, CWE-313, CWE-532

---

### D — Denial of Service
**Security property violated**: Availability

**Definition**: Exhausting resources to deny service to legitimate users.

**Examples**:
- Resource exhaustion via large payloads or high request volume
- Algorithmic complexity attacks (ReDoS)
- Memory leaks leading to OOM crashes
- Billion laughs XML expansion

**Applicable Controls**:
- Rate limiting on all public endpoints
- Input size limits and timeouts
- Resource quotas per user/tenant
- Circuit breakers

**CWEs**: CWE-400, CWE-770, CWE-776

---

### E — Elevation of Privilege
**Security property violated**: Authorization

**Definition**: Gaining capabilities without proper authorization.

**Examples**:
- Vertical privilege escalation — regular user gains admin rights
- Horizontal privilege escalation — accessing another user's data (IDOR)
- Exploiting insecure direct object references
- JWT algorithm confusion attacks (RS256 → HS256)

**Applicable Controls**:
- Principle of least privilege
- Server-side ownership checks on every resource access
- Proper role validation (not just authentication)

**CWEs**: CWE-269, CWE-284, CWE-285, CWE-639, CWE-862, CWE-863

---

## STRIDE ↔ OWASP Top 10 Mapping

| STRIDE | Primary OWASP Categories |
|--------|--------------------------|
| Spoofing (S) | A07 Authentication Failures |
| Tampering (T) | A03 Injection, A08 Integrity Failures |
| Repudiation (R) | A09 Logging Failures |
| Information Disclosure (I) | A02 Cryptographic Failures, A05 Misconfiguration |
| Denial of Service (D) | A04 Insecure Design |
| Elevation of Privilege (E) | A01 Broken Access Control |

---

## Applying STRIDE to Data Flow Diagrams

| DFD Element | Applicable STRIDE |
|-------------|------------------|
| External Entity (user/system) | S, R |
| Process | S, T, R, I, D, E |
| Data Store | T, R, I, D |
| Data Flow | T, I, D |
| Trust Boundary | All (S, T, R, I, D, E) |
