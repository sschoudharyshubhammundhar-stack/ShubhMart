# ShubhMart Payment Recovery and Coin Release Review — 2026-10-14

**Classification:** Draft release-blocker review. Source-level observations only. No live payment was initiated, no production SQL was run, and no deployed function was changed.

## Scope inspected

- `customer/customer-app.js` on `fix/secure-checkout-edge-function`
- `supabase/functions/razorpay-payment/index.ts` on `fix/secure-checkout-edge-function`
- `docs/drafts/20261012_secure_razorpay_payment_transition_candidate.sql`

This review does not prove that the currently deployed Edge Function or database routine matches the branch.

## Finding PAY-RECOVERY-01 — browser-driven coin release can race payment reconciliation

The customer UI calls `releaseShubhCoinsForOrder(orderId)` when the Razorpay modal is dismissed, the SDK emits a payment-failed event, or payment verification returns an error. The helper calls the database RPC `release_shubhcoins_for_order` directly from the browser client.

A client-side dismissal or error is not authoritative evidence that the provider has no captured payment. A payment can be captured while the browser loses connectivity, closes, or fails to receive a callback. The current payment Edge Function explicitly has a recoverable path where the provider payment is verified but the privileged database Paid-state update fails; it returns a reconciliation-needed response. If a browser then releases coins based only on the UI error, the order/payment/coin states may diverge unless the release RPC itself safely checks the full lifecycle.

**Important uncertainty:** the body and deployed version of `release_shubhcoins_for_order` were not verified in this source snapshot. Therefore this is a high-priority invariant to prove, not a claim that the RPC definitely lacks guards.

### Required remediation contract

1. Browser UI may request a reconciliation/retry, but must not be the authority deciding that a payment is terminally failed.
2. Coin release must be a server-side, transactional state transition that locks the order/payment attempt and verifies that no captured payment exists (through trusted provider reconciliation or a verified terminal failure state).
3. If provider status is unknown, timeout, pending, or captured-but-not-yet-reflected in the database, preserve the reservation and mark the order for reconciliation; do not release coins automatically.
4. A coin debit and its release must be ledger-idempotent. A repeated failure callback or repeated modal-dismiss event must not credit twice.
5. The release transaction must not mark an order cancelled/refunded or restock inventory unless that same transition is authorized and coordinated with the stock lifecycle.
6. Keep the provider secret and service-role key server-side. Never let the browser set payment status or coin balance.

## Finding PAY-RECOVERY-02 — provider order creation can leave an orphan on DB attachment failure

The branch's payment Edge Function creates a Razorpay order first, then calls `attach_razorpay_order`. If the database attachment fails, the function returns a retry/support error after the provider order already exists. The draft attachment RPC intentionally rejects replacing a different already-attached gateway order ID. A retry that blindly creates a new provider order can therefore create orphan provider orders or repeatedly fail attachment.

### Required remediation contract

- A stable internal checkout/payment-attempt ID must map to at most one provider order.
- Before creating a provider order, transactionally claim the internal payment attempt; retries must reuse that attempt.
- Persist a recoverable provider-order creation state and reconcile provider order IDs after ambiguous network/database failures.
- Do not assume an HTTP timeout means the provider did not create an order.
- Do not create another provider order until the previous attempt has been reconciled or explicitly superseded under a documented state transition.
- Receipt/notes fields help operations but are not, by themselves, a database uniqueness guarantee.

## Finding PAY-RECOVERY-03 — idempotency is not yet wired end-to-end

The customer checkout frontend does not send a database-backed checkout idempotency key to `create-customer-order`. The schema candidate itself says the table alone does not stop duplicate orders until atomic claim/replay is implemented in the order RPC. Therefore static checks passing cannot establish protection against refresh, retry, double-submit from another tab/device, or a lost HTTP response after commit.

### Required remediation contract

- Generate a cryptographically random UUID idempotency key once per checkout attempt and persist it across network retries for that attempt.
- Bind it to the authenticated customer and a canonical server-computed fingerprint of address, cart + variant, delivery, coupon, payment method and requested coins.
- Same key + same fingerprint returns the same logical order/result.
- Same key + different fingerprint returns conflict without side effects.
- The unique claim, order/items, stock reservation, coin debit/ledger, payment attempt and replay result must be transactionally consistent.
- Cancellation/deletion must not make replay of a completed key silently create a new purchase.

## Mandatory isolated test scenarios

| Test | Setup / action | Required assertion |
|---|---|---|
| PR-01 | Provider reports captured; browser reports error and requests coin release | Coins remain reserved; order is reconciled to Paid or explicit support state |
| PR-02 | Provider status is unknown/timeout | No automatic coin release, restock or false failure |
| PR-03 | Repeat release request 10 times | At most one compensating ledger entry |
| PR-04 | Payment captured, DB Paid-state update fails, then retry verification | Same payment/order reconciles; no new provider order or coin release |
| PR-05 | Provider order created, DB attachment times out | Retry finds/reconciles original attempt; no blind duplicate |
| PR-06 | Two browser tabs submit the same checkout key simultaneously | One order, one stock reservation, one coin debit, one payment attempt |
| PR-07 | Same key is submitted with a different cart/address/coin amount | Conflict and zero additional side effects |
| PR-08 | Callback arrives after cancellation or timeout cleanup | State-machine rules prevent contradictory Paid/Cancelled states |
| PR-09 | Two distinct payment IDs attempt to pay one order concurrently | At most one is accepted; second payment is reconciled, not attached silently |
| PR-10 | Duplicate/out-of-order callbacks and provider webhook retries | State transitions and ledger effects are idempotent |

## Evidence gate before deployment

- [ ] Read the exact SQL body and effective grants for `release_shubhcoins_for_order`.
- [ ] Confirm whether that routine checks order/payment status, provider reconciliation state, ownership, lock ordering and ledger idempotency.
- [ ] Confirm the deployed Edge Function version equals the reviewed branch commit.
- [ ] Implement a server-owned payment-attempt state machine and atomic checkout idempotency.
- [ ] Run synthetic integration and concurrency tests on an isolated database.
- [ ] Verify all rollback/compensation cases before any production migration.
- [ ] Review the resulting diff and all CI checks before requesting merge approval.

## Release decision

**Do not release checkout/payment changes yet.** The branch has passed source syntax checks and secret scanning, but those checks do not test PostgreSQL transaction semantics, provider behavior, RLS/grants, race conditions, or deployed-version parity. No production changes are authorized by this document.
