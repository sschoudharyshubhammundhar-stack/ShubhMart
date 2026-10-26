# ShubhMart Checkout / ShubhCoins Adversarial Test Plan
**Status:** Test specification only. Not a claim that tests have run.  
**Target:** `fix/secure-checkout-edge-function` / PR #62  
**Production boundary:** Do not deploy Edge Functions, apply SQL, revoke grants, merge this PR, or use real payment credentials as part of this plan.

## Purpose and safety rule

This plan targets money/credit integrity and inventory consistency. The system must fail closed whenever provider state, order ownership, or transaction history is incomplete. Browser events, redirect URLs, client-supplied payment status, and a list of failed attempts are signals—not proof that a payment can never be captured.

A passing source/regex test is not proof of runtime correctness. Required evidence includes database integration tests, concurrent transaction tests, provider-mock tests, and a reviewed migration against an isolated copy of the real schema.

## Non-negotiable invariants

1. **One owner:** Every order, payment attempt, coin redemption, cancellation, and reconciliation action is scoped to the authenticated owner or a narrowly authorized server identity.
2. **One terminal decision:** An order cannot both release redeemed coins and later transition to paid without an explicit compensating, auditable workflow.
3. **No client proof:** Never accept client-supplied `paid`, `failed`, `captured`, amount, currency, provider order ID, or “all attempts failed” as authoritative.
4. **Fail closed:** Timeout, malformed JSON, provider 4xx/5xx, missing pages, pagination cap, unknown status, amount/currency/order mismatch, duplicate IDs, or database error means “indeterminate; do not release.”
5. **Atomicity:** Order state, payment-attempt state, stock, wallet balance, and ledger must transition in one database transaction where applicable, using a documented lock order.
6. **Idempotency:** Replaying the same checkout request, webhook, payment verification, cancel request, or reconciliation request must not duplicate an order, stock decrement, coin credit, or ledger entry.
7. **Immutable evidence:** Preserve provider attempt identifiers and reconciliation evidence; do not delete the only record needed to investigate a late capture.
8. **Least privilege:** No browser role may execute a privileged coin-release function or write provider evidence. SECURITY DEFINER functions must have a fixed empty search_path and fully qualified object references.
9. **Inventory correctness:** Parent-product and variant stock must both be validated and reserved atomically; cancellation restores exactly the quantities reserved, once.
10. **Honest UI:** “Pending/unknown” must never be displayed as “failed,” “refunded,” “coins restored,” or “order cancelled.”

## Adversarial cases required before release

| ID | Attack / race | Required expected result |
|---|---|---|
| AUTH-01 | Anonymous caller invokes reconciliation/release | Reject; no database mutation |
| AUTH-02 | Customer A supplies Customer B's order UUID | Generic denial; no state or timing leak beyond necessary response |
| AUTH-03 | Valid JWT but expired/revoked session where supported by policy | Reject sensitive operation |
| AUTH-04 | Client edits order/customer IDs in request body | Server derives actor from verified JWT and verifies ownership |
| RPC-01 | Browser calls legacy `release_shubhcoins_for_order` directly | Permission denied after coordinated migration; until then this is a known live risk |
| RPC-02 | Caller invokes function via PUBLIC inheritance, not explicit role grant | Permission denied after migration; inspect effective ACLs, not just explicit grants |
| PAY-01 | Browser says payment failed while provider says captured | Never release coins; mark/reconcile payment as paid |
| PAY-02 | Browser says paid but signature/provider details mismatch | Reject; no paid transition |
| PAY-03 | Correct signature but wrong provider order ID, payment ID, currency, or amount | Reject; no paid transition |
| PAY-04 | Amount is off by one paisa or overflows/uses non-integer values | Reject; amounts represented and compared as exact integer paise |
| PAY-05 | Duplicate payment verification/webhook delivered concurrently | One logical transition and one ledger effect |
| PAY-06 | Two distinct payment IDs race for one order | Serialize; explicitly handle duplicate/late capture without double fulfilment |
| PAY-07 | Provider request times out after provider may have captured | Indeterminate; do not release or delete evidence |
| PAY-08 | Provider response malformed, empty, truncated, or has unexpected status | Indeterminate; no release |
| PAY-09 | Pagination has more pages than configured limit | Indeterminate; never infer “all attempts failed” |
| PAY-10 | Attempt is authorized, created, pending, or unknown—not captured | Do not release |
| PAY-11 | All currently listed attempts are failed, but provider order may accept a new attempt | Do not release until authoritative non-capturability/closure is established |
| PAY-12 | Provider API key missing/rotated or returns 401/403/429/5xx | Fail closed; safe operational alert, no secret in logs |
| RACE-01 | Coin release and paid transition run simultaneously | A single serializable outcome; no order can be both coin-released and paid without explicit compensation |
| RACE-02 | Coin release races with `cancel_customer_order` | Same order lock/transition protocol; no bypass through internal caller |
| RACE-03 | Cancel races with late provider capture | Preserve evidence; do not erase attempt; route to reconciliation/incident handling |
| RACE-04 | `cancel_unpaid_order` races with payment capture | Do not delete order/payment evidence while capture is possible |
| RACE-05 | Two checkout calls with same idempotency key arrive concurrently | Exactly one order; the other returns the same result |
| RACE-06 | Same key reused with different cart/address/coins | Reject key conflict; never replay a different order |
| RACE-07 | Two checkout requests without key target last unit of stock | At most one succeeds; no negative parent or variant stock |
| RACE-08 | Cancellation repeated or concurrent | Stock and coins restored at most once |
| RACE-09 | Paid webhook arrives after cancellation/coin release | No silent overwrite; durable exception state and reconciliation alert |
| COIN-01 | Duplicate coin-release request | At most one positive release ledger entry and one wallet credit |
| COIN-02 | Redeem ledger missing, duplicated, malformed, or inconsistent with wallet | No automatic release; manual/automated reconciliation alert |
| COIN-03 | Client submits a different coin amount | Ignore client amount; calculate from authoritative ledger |
| COIN-04 | Negative/zero/overflowing wallet or ledger values | Reject and preserve ledger invariants |
| STOCK-01 | Variant has stock but parent has zero (or inverse) | Reject checkout atomically |
| STOCK-02 | Parent and variant stock reservation partially fails | Roll back every stock and order mutation |
| STOCK-03 | Same cancellation retries after partial/uncertain response | Idempotent result; no double restock |
| DB-01 | Database deadlock/serialization failure/statement timeout | Transaction rolls back; safe retry only with idempotency |
| DB-02 | Trigger/function raises after wallet update but before ledger insert | Entire transaction rolls back |
| DB-03 | Search path is attacker-controlled or shadow object exists | SECURITY DEFINER function still resolves only qualified intended objects |
| DB-04 | New function created with default PUBLIC EXECUTE | CI/schema check fails until ACL explicitly restricted |
| DATA-01 | Provider secret/service role key appears in frontend bundle, logs, test fixture, or committed file | Secret scan fails; rotate exposed secret if real |
| DATA-02 | Logs include full JWT, provider secret, card/payment-sensitive data | Test fails; redact secrets and minimize personal data |
| UI-01 | User closes payment modal while state is unknown | UI says “checking/pending”; no claim coins were restored |
| UI-02 | Network disconnects after server commit but before response | Refresh/retry reads authoritative state; no duplicate action |
| UI-03 | Browser replays an old verification response | Server rechecks current authoritative state; stale response cannot reverse state |

## Test design / execution gates

### Gate A — static source checks
- Verify frontend has no direct call to `release_shubhcoins_for_order`.
- Verify all reconciliation responses are treated as untrusted until server-validated.
- Verify errors never become implicit permission to release coins.
- Verify secrets and privileged keys are absent from browser files.
- Static tests are necessary but insufficient.

### Gate B — isolated database integration
- Create a disposable test project/database from the current schema and migrations; never use production as the test target.
- Seed two customers, orders, product/variant inventory, redeem ledger entries, wallet balances, and multiple payment attempts.
- Assert before/after balances, ledger row counts, order state, payment state, and stock exactly.
- Verify actual function ownership, SECURITY DEFINER setting, search_path, effective EXECUTE ACLs (including PUBLIC), RLS policies, and all internal callsites.
- Do not infer the live schema from a candidate SQL file; first compare function signatures, table columns, constraints, triggers, and indexes with the isolated schema snapshot.

### Gate C — concurrency / fault injection
- Use independent DB connections and barriers to force both possible transaction orderings for every RACE case.
- Inject provider timeouts both before and after the mock provider records capture.
- Simulate duplicate/out-of-order webhooks, partial network responses, pagination truncation, DB rollback, deadlocks, and process restart.
- Run each race repeatedly; verify no negative stock, duplicate order, double coin credit, lost provider evidence, or paid-and-released contradiction.
- Capture SQLSTATE, state transitions, and ledger diffs without logging secrets.

### Gate D — security review and rollout
- Build a caller/callee graph for every function that reads/writes orders, payments, wallet, coin ledger, stock, and cancellations.
- Migrate all internal callers before revoking the legacy function grant; do not leave a hidden dependency.
- Apply schema changes only to an isolated environment first; run Supabase security advisors and review each finding.
- Deploy only after explicit user approval, a reviewed migration, passing runtime tests, and a rollback/forward-recovery plan.
- After deployment (only with approval), verify the exact deployed function version and permissions; source on a Git branch is not evidence of deployed behavior.

## STOP conditions

Stop and do not auto-release coins if the provider cannot authoritatively prove an order/attempt is no longer capturable, if attempt history is incomplete, if a lock/transaction guarantee is missing, or if live schema differs from the reviewed migration. Route to reconciliation/manual review rather than guessing.

## Current known limitation

The branch function `reconcile-shubhcoins-payment` intentionally does not release coins. This is a fail-closed stub, not a complete remediation. The live project still has the previously documented legacy release path until a coordinated, reviewed migration is approved and deployed. This document adds no runtime code and makes no production change.
