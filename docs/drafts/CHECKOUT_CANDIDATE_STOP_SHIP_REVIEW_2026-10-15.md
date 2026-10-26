# Stop-Ship Review: Checkout Candidate vs Locked Inventory and Payment Contract
**Date:** 2026-10-15  
**Branch:** `fix/secure-checkout-edge-function`  
**Status:** REVIEW FINDINGS ONLY — no production changes; no SQL in this document is executable.

## Decision
**Do not apply `CHECKOUT_VARIANT_STOCK_RESERVATION_CANDIDATE.sql` and do not promote the current checkout branch to production.** The candidate is internally inconsistent with the locked parent-plus-variant inventory requirement and does not close the end-to-end payment/idempotency failure modes.

## Evidence reviewed
- `docs/drafts/CHECKOUT_VARIANT_STOCK_RESERVATION_CANDIDATE.sql`
- `docs/drafts/CHECKOUT_STOCK_RESERVATION_PATCH_DRAFT.sql`
- `docs/drafts/CHECKOUT_CALLER_INVENTORY.md`
- `docs/drafts/CHECKOUT_LIFECYCLE_FOLLOWUP_AUDIT.md`
- `docs/drafts/CHECKOUT_ISOLATED_TEST_RUNBOOK.md`
- `supabase/functions/create-customer-order/index.ts`
- `supabase/functions/razorpay-payment/index.ts`
- Read-only live schema/function/privilege audit recorded in `LIVE_CHECKOUT_COIN_STOCK_DEEP_AUDIT_2026-10-15.md`

## P0 — Parent and variant inventory contract is contradictory
The locked ShubhMart requirement is that a variant checkout accounts for quantity in both `products.stock` (parent total/ceiling) and `product_variants.stock` (variant availability), atomically. The candidate explicitly says “Variant owns its inventory: do not also decrement parent product stock.” It updates only variant stock for a variant line. This violates the locked requirement and can allow aggregate parent inventory to drift or oversell if parent stock is the shared ceiling.

**Required correction before SQL is authored:** document the exact inventory meaning of both columns, confirm every seller/admin/import/return/restock path, then make checkout and every restore/adjustment path obey one shared invariant. For variant line quantity Q, both guarded decrements must succeed in the same transaction; any failure rolls both back. Non-variant line decrements parent stock only. Restoration must use durable per-line reservation data and restore both decremented counters exactly once. Do not simply add a parent decrement to the current candidate: its cancellation/admin/seller/return paths must be coordinated too.

## P0 — Reservation flag is too coarse for mixed historical data
The candidate sets `Orders.stock_reserved = true` for the order, while existing cancellation routines use the flag to decide whether to restore stock and currently restore either variant or parent stock. A single boolean cannot tell whether each line reserved parent, variant, both, or neither, and historical orders may have missing `variant_id`.

**Required correction:** persist an immutable reservation record per order item (or equivalent ledger) that records exact product ID, variant ID, quantity, which counters were decremented, reservation state, and one-time restoration state. All cancellation/payment-failure/return/admin/seller paths must consume this record under locks. Historical orders without reliable reservation evidence must go to reconciliation/manual review; never infer stock movement from the boolean alone.

## P0 — Idempotency is still absent from runtime contract
Both `index.html` and `customer/customer-app.js` call the same Edge Function with different payloads; neither passes an idempotency key, and only the customer app sends ShubhCoins. The candidate RPC has no key/fingerprint/replay contract. Browser storage or Edge Function memory cannot make the database transaction idempotent.

**Required correction:** one canonical request contract across both clients; authenticated-customer-scoped idempotency key + server-computed fingerprint; unique database constraint; atomic result, order/items, reservation, payment intent and coin ledger writes. Same key/same request returns the original stable result. Same key/different request returns conflict without mutation. Concurrent duplicate calls must yield one committed result. A cancelled/cleaned-up key must never recreate an order.

## P0 — Coupon behavior regression risk
The candidate hard-codes `WELCOME10` and a 10%/₹200 cap instead of using the live `public.coupons` rules (observed columns include `min_order`, `discount_amount`, active dates and category). That can change customer pricing or bypass the intended coupon policy.

**Required correction:** trace existing coupon validation and semantics from all callers, including category eligibility and whether `discount_amount` means fixed or percentage. Implement only the verified existing contract, server-side, and add tests for inactive/not-yet-active/expired coupons, minimum order, category mismatch, repeated coupon use if applicable, and rounding. Do not ship guessed coupon math.

## P0 — Razorpay order creation can orphan provider-side orders
The candidate Edge Function creates the Razorpay order first and only then calls `attach_razorpay_order`. If the database attachment fails or the HTTP response is lost, a provider order may exist without durable local mapping. Retrying can create another provider order. The existing runbook itself records the grant mismatch as a blocker for the live version.

**Required correction:** design a durable payment-intent/outbox state machine and stable provider idempotency/reference strategy supported by the provider. Before an external order is created, ensure the local intent and retry identity are committed. If provider success/local persistence is ambiguous, reconcile the same intent; do not blindly create a new provider order. Test provider-created/DB-attach-failed and DB-commit/HTTP-timeout cases in sandbox/mock.

## P0 — Paid transition and cancellation still need one serialization point
Server-to-server payment entity verification is a useful candidate improvement, but it does not by itself prevent a race between payment confirmation, customer cancellation, admin/seller cancellation, stock restoration, refund creation and coin release. The live paid-state RPC lacks the required shared order lock according to the read-only audit. Local “Pending/Failed” state or browser dismissal is not proof that a provider payment can no longer be captured.

**Required correction:** all payment/cancel/reconcile/refund/coin-release transitions lock the same order first, then a specific payment attempt, reservation and ledger rows in deterministic order. Keep attempts and evidence; do not delete them during unpaid cleanup. If outcome is ambiguous, keep it indeterminate and reconcile rather than restoring coins/stock prematurely. Test late capture after cancellation and duplicate/out-of-order webhook delivery.

## P1 — Payment attempts need an explicit cardinality contract
Read-only branch notes state that `payments.order_id` has no unique index, despite zero duplicate rows in the inspected snapshot. Zero current duplicates do not prevent concurrent duplicates. The current candidate and payment functions assume one matching payment row in some places but update/select rows broadly or use non-deterministic `LIMIT 1`.

**Required correction:** decide whether the model is one payment intent per order or multiple attempts per order. Prefer explicit payment-attempt IDs with a unique provider-order mapping and stable attempt sequence; do not add a unique constraint until current data and supported retry behavior are reviewed. All RPCs must address a specific attempt and use exact row-count assertions.

## P1 — Multi-seller semantics remain a release blocker
The current order RPC creates one order for the cart and does not establish item-level seller attribution. Stock correctness alone does not define seller ownership, commission, settlement, cancellation, refund, RLS, or order notifications for a cart with multiple sellers.

**Required correction:** establish and test a parent checkout / seller child-order model or explicitly reject multi-seller carts until that model is ready. Never infer seller ownership from mutable product rows after checkout; persist it on order items at checkout.

## P1 — Lock order and deadlock strategy must be global
A local `ORDER BY` in one checkout loop does not prove a global lock order across checkout, admin edits, seller stock updates, cancellation, refund and coin ledger routines. Mixed product/variant locks can deadlock if other routines lock in a different order.

**Required correction:** publish one lock-order contract for all lifecycle functions (including parent product IDs sorted first, then variant IDs sorted, followed by order/payment/reservation/wallet/ledger as designed). Review every function/trigger that touches more than one of these rows. Add two-session deadlock/race tests and safe retry handling for PostgreSQL serialization/deadlock SQLSTATEs.

## P1 — Privileged function boundary must be tested as deployed
The candidate RPC allows `service_role` based on `auth.role()` and otherwise checks `auth.uid()`. The Edge Function uses a service-role client after verifying the bearer token. This can be safe only if the Edge Function is the sole exposed path, validates identity every time, the RPC is not customer-callable, and effective EXECUTE grants—including PUBLIC inheritance—are verified. The old live RPC's grant state is not changed by a branch SQL file.

**Required correction:** keep privileged checkout RPC server-only until the entire design is approved; explicitly audit `PUBLIC`, `anon`, `authenticated`, `service_role`, function owner, nested calls, and RLS bypass. Verify effective `has_function_privilege` in isolated tests after the exact migration. Use `SET search_path = ''` and fully qualified object names for SECURITY DEFINER functions after dependency review.

## Required next action (safe sequence)
1. Treat this candidate as rejected pending redesign; do not apply it as-is.
2. Complete the call-site map for every checkout, cancellation, admin/seller status, stock update, return/refund, payment attempt, webhook, scheduled job and coin award/release.
3. Agree inventory semantics and multi-seller order model.
4. Create a complete additive migration draft with explicit rollback/reconciliation plan only after exact schema/trigger/constraint review.
5. Build disposable local PostgreSQL/Supabase fixtures with synthetic data; run concurrent transactions and failure injection with all relevant triggers enabled.
6. Run Deno/type/runtime tests and Razorpay sandbox/mock tests; test both frontend checkout callers.
7. Verify the exact candidate commit in CI/Cloudflare preview; prior commits' passing tests do not validate a new commit.
8. Keep PR #62 Draft. No production DDL/DML, grants, Edge Function deploy, merge, live checkout, or real payment until the user explicitly approves the release step.

## Safety statement
This review is defensive, scoped to ShubhMart's own repository/database, and does not include exploit instructions against third-party systems. No system can honestly be promised “unhackable”; the release goal is atomic money/stock behavior, least privilege, evidence retention, deterministic reconciliation, and fail-closed behavior.
