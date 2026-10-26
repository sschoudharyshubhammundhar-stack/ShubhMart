# ShubhMart — Coin-release remediation design gate (2026-10-15)

**Status: DESIGN ONLY / RELEASE BLOCKER. No production SQL or deployment.**

This document exists to prevent a dangerous partial fix. The current browser directly calls `release_shubhcoins_for_order`; the live routine is SECURITY DEFINER, executable by authenticated users, and decides release from the order's `payment_status` without consulting the authoritative Razorpay payment state. Removing only the browser call may strand coins; revoking only the grant may break checkout recovery; adding only an Edge Function without an atomic database transition is not a fix.

## Must remain true in every state

1. Browser events (dismiss, SDK failure, lost response, thrown error, tab close) are signals to reconcile, never proof of terminal payment failure.
2. Provider state is fetched server-side using credentials from secrets. Client-supplied payment status, order IDs, amounts, signatures, or "failed" flags are not accepted as release evidence.
3. The reconciliation service checks the internal order, every known payment attempt for its gateway order, and provider payment records. Any captured payment, unknown payment, authorized/pending payment, provider timeout/error, incomplete pagination/history, amount/currency/order mismatch, or conflicting attempt blocks coin release.
4. Only a server-verified, terminal no-capture outcome for the complete attempt set may request release. "Failed" for one attempt is not sufficient if another attempt may still capture.
5. Database transaction locks the order first, then payment attempts in deterministic ID order, then redeem ledger/wallet rows. Every code path uses the same lock order to avoid deadlocks.
6. The transaction rechecks that the order is not Paid and no captured/authorized/pending/unknown attempt is present in persisted verified reconciliation evidence. It inserts one release ledger row and updates wallet balance/lifetime_spent atomically. Duplicate calls are successful no-ops, not extra credits.
7. Payment-success transition locks the same order and payment rows and refuses to mark Paid if coin release has already committed. If the provider says captured after a release, raise an incident/reconciliation state; never silently allow both.
8. The release routine is not executable by `anon`, `authenticated`, or `PUBLIC`. Only a narrowly scoped service-role path may call it. The Edge Function must independently authenticate the user's JWT and prove order ownership before provider lookups. The service-role key never reaches the browser.
9. All SECURITY DEFINER functions use `SET search_path = ''` and fully qualified object names. Effective grants must be verified from the database catalog, not inferred from migration text.
10. CORS is a browser boundary, not authorization. Do not introduce an allowlist until actual production web origins are enumerated; never use CORS as a substitute for auth/ownership checks.

## Required data model decision before coding

Do not treat a new evidence table as automatically trustworthy. Design a private, append-only reconciliation record containing at minimum:
- internal order ID and payment-attempt ID;
- provider gateway order ID;
- result enum such as `captured`, `terminal_no_capture`, `indeterminate`;
- verified amount in integer paise and currency;
- provider payment IDs/statuses examined and pagination-complete marker;
- server-generated checked-at timestamp and stable idempotency/request key;
- a unique constraint that prevents duplicate release decisions for the same order/attempt-set fingerprint.

The application must decide how long Razorpay's order can remain payable and how it closes/expirs an order before declaring a terminal no-capture result. If provider semantics cannot prove the order is no longer capturable, keep coins reserved and route to retry/manual reconciliation. Do not invent a timeout after which release is assumed safe.

## Required implementation sequence

A. Inventory all callers of the existing RPC, all order/payment statuses, all payment creation paths, cancellation/cleanup paths, coin redemption/release ledger constraints, and deployed function versions.

B. In an isolated disposable database cloned from the exact current schema:
- add the evidence schema and constraints;
- implement server-only reconciliation persistence and atomic release;
- coordinate the paid transition and cancellation/cleanup functions with the same lock order;
- revoke the legacy browser RPC only in the same coordinated change that removes all browser callers;
- test grants for `anon`, `authenticated`, `service_role`, owner, and PUBLIC.

C. Add Edge Function reconciliation:
- verify JWT server-side and check order ownership;
- query the exact provider order and exhaustively inspect payment history;
- reject unexpected states and mismatches;
- record evidence through a narrowly scoped server-only RPC;
- call atomic release only after the DB rechecks the evidence and current payment state;
- return generic errors with a correlation ID; never leak provider payloads or secrets.

D. Change frontend callbacks to request reconciliation only. A verification error must display "payment status is being checked" when indeterminate; it must not claim payment failed or coins returned unless the server returns a confirmed state.

E. Prove with synthetic isolated tests:
- captured at provider, DB stale;
- captured payment with browser error/dismissal;
- one failed attempt and another pending attempt;
- authorized payment;
- provider timeout, 5xx, malformed response, incomplete pagination;
- wrong amount/currency/order/customer;
- duplicate and concurrent reconciliation calls;
- reconciliation vs payment success race;
- release vs cancellation/stock-restoration race;
- late capture after a purported terminal result;
- two customers trying each other's order IDs;
- wallet and ledger invariant after every injected transaction failure.

## Acceptance criteria (all mandatory)

- [ ] No direct browser call to the legacy release RPC remains.
- [ ] Legacy RPC is not executable by authenticated/anon/PUBLIC.
- [ ] Provider state and complete attempt history are checked server-side.
- [ ] Indeterminate states never release coins.
- [ ] Wallet and ledger update exactly once and atomically.
- [ ] Paid and released states cannot coexist without an explicit audited exception process.
- [ ] Concurrency, late-capture, and fault-injection tests pass in isolated environment.
- [ ] Actual deployed Edge Function versions and effective DB grants match the reviewed code.
- [ ] Secret scan, syntax tests, all regression tests, rollback plan, and post-deploy verification are green.

## Explicit non-actions

This design file does not apply SQL, alter production grants, modify Auth settings, deploy functions, merge the PR, initiate real payments, or touch customer balances. A static regex test is not evidence of transaction safety. Do not release this fix based on source inspection alone.
