# DREAD Risk Scoring Framework

DREAD is a quantitative risk scoring model used by red team agents to score
the exploitability and impact of attack scenarios.

---

## Factors

Each factor is scored 1–3. Total DREAD = average of all five factors.

### D — Damage Potential

How much damage results if the vulnerability is exploited?

| Score | Meaning |
|-------|---------|
| 1 | Minor — inconvenience, non-sensitive data, limited blast radius |
| 2 | Moderate — data loss, partial service disruption, sensitive data of limited users |
| 3 | Severe — complete system compromise, mass PII/credential exposure, RCE |

### R — Reproducibility

How easily can the attack be reproduced?

| Score | Meaning |
|-------|---------|
| 1 | Difficult — requires specific preconditions, timing, or access |
| 2 | Moderate — reproducible with some effort or specific account type |
| 3 | Trivial — anyone can reproduce it with a simple script or request |

### E — Exploitability

What technical skill is required to launch the attack?

| Score | Meaning |
|-------|---------|
| 1 | Expert — requires deep knowledge, custom tooling, or insider access |
| 2 | Intermediate — requires programming skill or moderate security knowledge |
| 3 | Low — script kiddie level; off-the-shelf tools, no skill required |

### A — Affected Users

How many users or systems are impacted?

| Score | Meaning |
|-------|---------|
| 1 | Few — single user or isolated component |
| 2 | Some — subset of users or specific tenant |
| 3 | All — entire user base or critical shared infrastructure |

### D — Discoverability

How easily can the vulnerability be found?

| Score | Meaning |
|-------|---------|
| 1 | Hard — requires internal access, source code, or sophisticated analysis |
| 2 | Moderate — found with some probing or knowledge of common patterns |
| 3 | Easy — visible in public documentation, browser dev tools, or simple scan |

---

## Scoring Formula

```
DREAD Total = (Damage + Reproducibility + Exploitability + Affected + Discoverability) / 5
```

| Total Score | Risk Level | Suggested Response |
|-------------|------------|-------------------|
| 2.5 – 3.0 | **Critical** | Fix immediately; may warrant emergency release |
| 2.0 – 2.4 | **High** | Fix within 24–72 hours |
| 1.5 – 1.9 | **Medium** | Fix within 1–2 weeks |
| 1.0 – 1.4 | **Low** | Fix in next sprint or quarterly cycle |

---

## Example Scoring

**SQL Injection on public login endpoint**:
- Damage: 3 (credential exposure, account takeover)
- Reproducibility: 3 (trivial with sqlmap)
- Exploitability: 3 (public endpoint, no auth required)
- Affected Users: 3 (all users)
- Discoverability: 3 (common first thing attackers try)
- **Total: 3.0 — Critical**

**Reflected XSS in admin-only panel**:
- Damage: 2 (session hijack, limited to admins)
- Reproducibility: 2 (requires crafting URL)
- Exploitability: 2 (needs social engineering admin)
- Affected Users: 1 (only admin users)
- Discoverability: 2 (requires testing with devtools)
- **Total: 1.8 — Medium**
