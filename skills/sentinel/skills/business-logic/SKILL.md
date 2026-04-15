---
name: business-logic
description: >
  Detect business logic security vulnerabilities. Use when the user asks to
  "check business logic security", "find logic flaws", "audit workflow security",
  "check for coupon abuse", "detect negative amount exploits", "analyze state
  machine security", or mentions "business logic", "workflow bypass", "negative
  amount", "coupon abuse", "self-referral", "state manipulation", or "price
  manipulation" in a security context. Invoke with /sentinel:business-logic.
---

# Business Logic Security (BIZ)

Analyze application business logic for security vulnerabilities including
workflow step bypassing, negative amount manipulation, coupon/discount abuse,
self-referral exploitation, state machine manipulation, and time-based logic
exploits. Business logic flaws are unique to each application and cannot be
detected by generic scanners — they require understanding the intended workflow
and finding ways to subvert it.

## Framework Context

Key CWEs in scope:
- CWE-840: Business Logic Errors
- CWE-841: Improper Enforcement of Behavioral Workflow
- CWE-799: Improper Control of Interaction Frequency
- CWE-837: Improper Enforcement of a Single, Unique Action
- CWE-20: Improper Input Validation

OWASP mapping: A04:2021 (Insecure Design)
STRIDE mapping: T (Tampering), E (Elevation of Privilege)

## Workflow

### Step 1 — Identify Business Logic Files

Prioritize these file patterns:

- Payment and checkout (`**/payments/**`, `**/checkout/**`, `**/billing/**`)
- Order processing (`**/orders/**`, `**/cart/**`, `**/transactions/**`)
- Discount and coupon logic (`**/coupons/**`, `**/discounts/**`, `**/promotions/**`)
- Referral and reward systems (`**/referrals/**`, `**/rewards/**`, `**/loyalty/**`)
- Workflow and state machines (`**/workflows/**`, `**/state/**`, `**/status/**`)
- User account operations (`**/accounts/**`, `**/profiles/**`)

### Step 2 — Run Available Scanners

Run semgrep if available: `semgrep scan --config auto --json --quiet <target>`
Filter for numeric validation, state management, and workflow enforcement patterns.

Note: business logic flaws are primarily detected through manual code analysis,
not automated scanners. Scanner output is supplementary.

### Step 3 — Manual Code Analysis

#### 1. Workflow Step Bypass
Map multi-step workflows (checkout, verification, approval) and verify each step
cannot be skipped by calling later steps directly.

```python
# Vulnerable: step 3 endpoint doesn't verify step 2 was completed
@app.route('/checkout/payment')   # step 2
def payment():
    session['payment_done'] = True

@app.route('/checkout/confirm')   # step 3 — can be called directly
def confirm():
    # No check: was payment actually processed?
    complete_order(session['cart'])
```

#### 2. Negative Amount Manipulation
Find numeric inputs (amounts, quantities, prices) and verify the application
rejects negative values at the server side.

```javascript
// Vulnerable: negative amount passes validation and reverses the charge
const amount = req.body.amount;  // attacker sends -100
await chargeCard(amount);  // results in a $100 credit
```

#### 3. Coupon / Discount Abuse
Find discount application logic and verify coupons cannot be applied multiple
times, stacked beyond intended limits, or used after expiration.

```python
# Vulnerable: no check if coupon already used by this user
if coupon.is_valid():
    order.apply_discount(coupon.amount)
    # Missing: mark coupon as used, check per-user limit
```

#### 4. Self-Referral Exploitation
Find referral systems and verify users cannot refer themselves or create
circular referral chains.

```python
# Vulnerable: no check that referrer != referred user
def apply_referral(referrer_id, new_user_id):
    user = User.get(referrer_id)
    user.credits += REFERRAL_BONUS  # attacker creates accounts, refers themselves
```

#### 5. State Machine Manipulation
Map state transitions and verify invalid transitions are rejected.

```python
# Vulnerable: order can jump from 'pending' to 'delivered' directly
def update_status(order_id, new_status):
    order = Order.get(order_id)
    order.status = new_status  # no transition validation
    order.save()
```

#### 6. Time-Based Logic Exploits
Find logic depending on timestamps and verify it handles timezone manipulation,
clock skew, and deadline race conditions.

```javascript
// Vulnerable: client-supplied timestamp used for discount expiry
if (req.body.timestamp < discount.expiresAt) {
    applyDiscount();  // attacker sends past timestamp
}
```

#### 7. Price Manipulation
Client-supplied prices accepted without server-side verification against the
product catalog.

```python
# Vulnerable: price comes from the client
order = Order(
    product_id=req.body.product_id,
    price=req.body.price,   # attacker sends price=0.01
    quantity=req.body.quantity
)
```

#### 8. Quantity Abuse
No limits on quantities enabling abuse (ordering negative quantities, exceeding
stock, zero-quantity orders).

### Step 4 — Findings Format

```
[BIZ-XXX] Title
Severity: CRITICAL/HIGH/MEDIUM/LOW | CWE: CWE-840/CWE-841
Location: file:line | Confidence: HIGH/MEDIUM/LOW

Business rule violated: [what the intended behavior is]

Exploit scenario:
1. [How attacker subverts the workflow]
2. [What server-side check is missing]
3. [Business impact: financial loss / unfair advantage / data bypass]

Evidence:
  [vulnerable code snippet]

Fix:
  [corrected code enforcing the business rule server-side]
```

## Severity Guidance

| Severity | Criteria |
|----------|----------|
| CRITICAL | Direct financial loss (negative amounts in payments, price manipulation) |
| HIGH | Workflow bypass on security-critical processes, unlimited discount stacking |
| MEDIUM | Self-referral abuse, state manipulation with limited business impact |
| LOW | Minor workflow inconsistencies, cosmetic state issues |

## Sentinel Integration

Business logic findings are by definition missed by Sentinel's SAST scanner.
They complement the Sentinel report as `BIZ-XXX` entries. Map to OWASP A04:2021.
These findings are the highest-value output of the audit layer since they
represent vulnerabilities tools cannot catch.


---

## Report Format

Format your final output following the standard Sentinel report structure defined in
`${CLAUDE_SKILL_DIR}/../../templates/report.md`. Use your skill's domain-specific
finding IDs (e.g. `STRIDE-SPOOF-001`, `RT-SK-001`, `API-001`) in the Finding ID column.
Include the Security Scorecard and Findings sections as a minimum. Omit the
Cross-Validation Summary section if you ran only AI analysis (no tool comparison).
