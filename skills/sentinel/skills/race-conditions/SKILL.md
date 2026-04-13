---
name: race-conditions
description: >
  Detect race condition vulnerabilities. Use when the user asks to "check for
  race conditions", "find TOCTOU bugs", "analyze concurrency issues", "detect
  double-spend vulnerabilities", "check for check-then-act patterns", or
  mentions "race condition", "TOCTOU", "double-spend", "concurrency",
  "atomicity", or "thread safety" in a security context. Invoke with
  /sentinel:race-conditions.
---

# Race Conditions (RACE)

Analyze source code for race condition vulnerabilities including time-of-check
to time-of-use (TOCTOU), double-spend, check-then-act without locking, file
system race conditions, shared state across async boundaries, and non-atomic
counter operations. Race conditions are among the hardest bugs to detect through
testing because they depend on timing — making static analysis essential.

## Framework Context

Key CWEs in scope:
- CWE-362: Concurrent Execution Using Shared Resource with Improper Synchronization
- CWE-367: Time-of-Check Time-of-Use (TOCTOU) Race Condition
- CWE-820: Missing Synchronization
- CWE-821: Incorrect Synchronization

STRIDE mapping: T (Tampering), E (Elevation of Privilege)

## Workflow

### Step 1 — Identify High-Risk Files

Prioritize these file patterns:

- Database transaction handlers (`**/services/**`, `**/handlers/**`, `**/models/**`)
- Payment and financial logic (`**/payments/**`, `**/billing/**`, `**/wallet/**`)
- File system operations (`**/storage/**`, `**/upload/**`, `**/fs/**`)
- Async/concurrent code (`**/workers/**`, `**/tasks/**`, `**/jobs/**`)
- Counter and state management (`**/counters/**`, `**/state/**`, `**/cache/**`)

### Step 2 — Run Available Scanners

Check for and run:
- `semgrep` — run with `semgrep scan --config auto --json --quiet <target>`, filter for race/TOCTOU/concurrency rules
- `go vet -race ./...` — Go race detection (if Go project)
- `bandit -r <target> -f json -q` — Python threading issues (if Python project)

Record which scanners ran and which are missing.

### Step 3 — Manual Code Analysis

Regardless of scanner availability, analyze for these patterns:

#### 1. Check-Then-Act Without Lock
Any pattern where a condition is checked and the result is assumed to hold
when the action executes — without atomic guarantees.

```python
# Vulnerable: balance checked then debited in separate non-atomic steps
if user.balance >= amount:      # check
    user.balance -= amount      # act (race window between check and act)
    db.save(user)
```

#### 2. TOCTOU in File Operations
File existence or permission checks followed by file operations in a separate call.

```python
# Vulnerable: attacker can replace file between check and open
if os.path.exists(filename):
    with open(filename) as f:   # file could be different now
        data = f.read()
```

#### 3. Shared State Across Await/Yield
Mutable state read before an await point and used after it without re-validation.

```javascript
// Vulnerable: balance could change while awaiting payment processor
const balance = await getBalance(userId);  // read
await chargePaymentProcessor(amount);      // yield — balance may change
await deductBalance(userId, balance);      // act on stale value
```

#### 4. Non-Atomic Read-Modify-Write
Counter increments, sequence generators, or flag toggles without synchronization.

```javascript
// Vulnerable: two concurrent requests both read 5, both write 6
let count = await getCount();
count++;
await setCount(count);
```

#### 5. Missing Database Transaction Isolation
Financial operations using default (READ COMMITTED) isolation when SERIALIZABLE
or row-level locking is needed.

```python
# Vulnerable: SELECT then UPDATE without FOR UPDATE lock
balance = db.query("SELECT balance FROM accounts WHERE id = ?", user_id)
if balance >= amount:
    db.execute("UPDATE accounts SET balance = balance - ? WHERE id = ?", amount, user_id)
# Should use: SELECT ... FOR UPDATE or SERIALIZABLE transaction
```

#### 6. Double-Spend in Financial Flows
Lack of idempotency or deduplication on payment/credit operations.

#### 7. Parallel Iteration Over Shared Collection
Modifying a shared list, map, or set from concurrent goroutines, threads, or async tasks.

### Step 4 — Findings Format

```
[RACE-XXX] Title
Severity: CRITICAL/HIGH/MEDIUM/LOW | CWE: CWE-362/CWE-367
Location: file:line | Confidence: HIGH/MEDIUM/LOW

Race window: [what happens between check and act]

Exploit scenario:
1. [Request 1 reads state]
2. [Context switch / await — Request 2 reads same state]
3. [Both requests proceed with stale value]
4. [Impact: double-spend / bypass / corruption]

Evidence:
  [vulnerable code snippet]

Fix:
  [corrected code using atomic operation, lock, or SELECT FOR UPDATE]
```

## Severity Guidance

| Severity | Criteria |
|----------|----------|
| CRITICAL | Double-spend in financial operations, authentication bypass via race |
| HIGH | TOCTOU in security-sensitive file operations, check-then-act on authorization |
| MEDIUM | Non-atomic counters affecting business logic, shared state across await |
| LOW | Theoretical races with no clear exploit path, cosmetic counter inaccuracies |

## Sentinel Integration

Race condition findings complement Sentinel's SAST scan. Map findings to the
Sentinel consolidated report as `RACE-XXX` entries. Race conditions often
correspond to OWASP A04:2021 (Insecure Design) or A07:2021 (Auth Failures)
when they affect authentication or financial flows.
