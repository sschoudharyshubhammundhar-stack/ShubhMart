# ShubhMart Checkout Security Gate — Adversarial Design Review
**Date:** 2026-10-15  
**Branch:** `fix/secure-checkout-edge-function`  
**Status:** DESIGN ONLY — NOT A MIGRATION; NOT DEPLOYED  
**Production safety:** All production inspection to date was SELECT/catalog-only. This document adds no database changes, grants, secrets, payment calls, deployments, or merges.

## 0. Non-negotiable release rule
Do not ship checkout changes until the same reviewed transaction model covers cart snapshot, pricing/coupons, parent+variant stock, order items, payment attempts, idempotency, ShubhCoins redemption/release, cancellation, webhook/late capture, and stock restoration. A patch that fixes only one function is rejected.

## 1. Fresh evidence from live catalog (read-only)
The following are confirmed from the connected live schema/functions at review time:
- `cart` has `product_id`, `variant_id`, `quantity`, `customer_id`; its current unique constraint is on `(customer_id, product_id)`, not `(customer_id, product_id, variant_id)`. This prevents a customer from holding separate cart rows for two variants of the same product and needs a deliberate compatibility-safe cart-key migration/design. A simple three-column UNIQUE constraint is not sufficient for NULL variant IDs under ordinary PostgreSQL NULL semantics; use a reviewed pair of partial unique indexes (variant IS NULL / variant IS NOT NULL) or an equivalent NULLS NOT DISTINCT constraint only after PostgreSQL version compatibility is verified.
- `Order_items` already has nullable `variant_id`; the live coin checkout omits it. Existing cancel functions restore either variant stock OR parent stock, not both.
- `Orders.stock_reserved` exists, defaults false. It is a coarse flag, not proof of which inventory quantities were reserved or whether restoration already happened.
- `payments` has a UUID row ID and gateway order/payment identifiers, but no inspected idempotency key or attempt-sequence field was observed in the listed columns. The complete schema still needs an index/constraint check before choosing a design.
- `coupons` columns observed are `code`, `min_order`, `discount_amount`, `start_date`, `end_date`, `category`, `active`. Do not invent percentage semantics or replace live rules with hard-coded `WELCOME10`; first inspect all callers and actual product/category semantics.
- Existing `Orders` triggers include financial recalculation, seller-update guard, customer notifications, and ShubhCoins award-on-delivery. Existing `payments` triggers guard customer inserts/updates; product and variant update triggers protect marketplace/admin fields. A new transition must be tested with these triggers enabled, not only in a simplified test schema.
- Live `create_order_from_cart_with_coins` is SECURITY DEFINER, uses `search_path=public`, checks parent stock but does not decrement it, does not lock product rows, does not read cart variant IDs, does not write Order_items.variant_id, and does not set stock_reserved explicitly.
- Live `release_shubhcoins_for_order` is SECURITY DEFINER and authenticated users have effective EXECUTE privilege. It trusts local payment status and lacks provider-verified terminal evidence and a shared order-row lock.
- Live `cancel_customer_order` calls the legacy release function internally. `cancel_unpaid_order` deletes payment attempts and order evidence. `mark_razorpay_paid_secure` lacks an order-row lock and does not cryptographically verify provider signatures in SQL; caller-side server verification must be enforced and proven.
- No production function, policy, grant, schema, row, or payment has been changed as part of this review.

## 2. Inventory invariant — required before SQL implementation
For this roadmap, adopt and enforce this single model:
1. `products.stock` is the parent product's remaining sellable total / ceiling.
2. For a variant line, checkout must reserve the same quantity from both `products.stock` and the selected `product_variants.stock` in the same database transaction. Both conditional updates must succeed or the whole transaction rolls back.
3. For a non-variant line, reserve only `products.stock`.
4. Validate `variant.product_id = cart.product_id`, active/approved product state, active/sellable variant state, non-null and non-negative quantity, price validity, and stock sufficiency while holding row locks.
5. Acquire product and variant row locks in a deterministic global order (sorted UUIDs); do not rely on cart row locks to serialize stock.
6. Persist `variant_id` and the exact server-calculated unit price/quantity on each order item. The server, never the browser, is authoritative for price, discount, tax, delivery and payable amount.
7. Persist reservation detail durably per order item (or in a dedicated reservation ledger) with parent quantity, variant quantity, reservation state, and one-time restoration state. `stock_reserved=true` alone is not enough to safely reconcile mixed historical orders.
8. Cancellation/payment-failure restoration must lock the order first, then reservation rows in deterministic order, and restore exactly the quantities recorded as reserved. Mark restoration in the same transaction. Repeated cancellation/retry must not increment stock twice.
9. Product/variant stock edits, seller inventory updates, admin adjustments, imports, returns, and order restoration must follow the same parent+variant accounting contract. If any existing path violates it, it is a release blocker; do not compensate by patching checkout alone.
10. Historical orders with `stock_reserved=false` or missing `variant_id` must never be “restored” by guessing. Reconcile using durable order/payment/reservation evidence or leave for manual review.

## 3. Checkout transaction protocol
A single database transaction must:
1. Authenticate via trusted server context; derive customer identity from verified auth, not a client-supplied customer UUID alone.
2. Claim a per-customer idempotency key under a unique constraint and store a canonical request fingerprint. The fingerprint covers address ID, payment method, delivery method, coupon code, requested coin count, and a canonical sorted cart snapshot (product, variant, quantity). Same key + same fingerprint returns the original order/result; same key + different fingerprint rejects; concurrent duplicate calls wait/return the one order.
3. Snapshot and validate cart rows. Decide whether cart changes after the snapshot are rejected or ignored for this attempt; never silently recalculate from a different cart midway through the same request.
4. Lock/validate products and variants in deterministic order and reserve stock as in section 2. Any failed line rolls back every prior decrement.
5. Calculate all prices and discounts from authoritative rows. Preserve documented coupon semantics from the live application; do not hard-code coupon codes or accept client-submitted discounts. Verify minimum order, active dates, category applicability, and discount cap exactly as current product contract defines.
6. Lock wallet after order/product/payment lock-order policy has been agreed and applied consistently to all flows. Validate available coins and cap; create one redemption ledger row protected by an appropriate unique constraint and decrement wallet atomically. Repeated idempotent checkout must not redeem twice.
7. Insert order, order items (including variant IDs), payment attempt, reservation records, and idempotency result atomically. Set `stock_reserved=true` only after the complete reservation has succeeded; transaction rollback must undo all effects.
8. Never make a network call to Razorpay inside the database transaction. Create the local pending order/attempt atomically, then create provider order server-side using a stable idempotency strategy and persist the provider ID. A timeout is indeterminate, not proof of failure.
9. Keep error messages safe: no SQL internals, credentials, tokens, stack traces, or cross-customer data.

## 4. One transition state machine for payment, cancellation, coins
Required conceptual states (map to actual enum/text values only after checking all existing app callers):
- pending: local order exists, provider outcome not yet terminal;
- provider_indeterminate: timeout, missing attempt, incomplete pagination, mismatch, or unknown provider state;
- paid: only after server-side provider verification of exact gateway order ID, payment ID, amount in paise, currency, and captured/paid status;
- cancel_requested / cancelled_reconciling: user requested cancellation but provider may still capture;
- terminal_non_capturable: durable, authoritative evidence establishes that this attempt/order can no longer be captured;
- refunded/return states handled separately from unpaid cancellation.
Never treat browser modal dismissal, client callback, HTTP error, webhook absence, or a locally marked failed payment as proof of terminal non-capturability.

Every paid/cancel/reconcile/release transition must:
- lock the same order row first;
- lock the specific payment attempt (not arbitrary `LIMIT 1`) and relevant reservation/ledger rows in deterministic order;
- be idempotent on duplicate webhooks and retries;
- reject contradictory terminal transitions instead of overwriting them;
- retain provider identifiers and audit evidence; do not delete payments/order items/orders as an unpaid-cancel shortcut;
- use service-only database functions for trusted provider transitions, with every caller reviewed;
- store provider amount as exact integer paise (or otherwise use an explicit exact-decimal conversion) and compare currency and all identifiers;
- use `SET search_path = ''` plus fully schema-qualified object names for SECURITY DEFINER functions after dependency review.

### ShubhCoins release hard rule
No customer-callable RPC may mint/re-credit coins based only on a browser claim or local `payment_status`. The replacement release transaction must lock the order, require durable trusted provider terminal evidence, prove no successful capture exists for any attempt, prove exactly one redeem entry exists, enforce one release per order via a database uniqueness guarantee, and update wallet + ledger atomically. If provider semantics cannot prove non-capturability, leave the order indeterminate and do not auto-release coins. Migrate internal callers before revoking the legacy client EXECUTE grant; then verify effective privileges for `anon`, `authenticated`, `service_role`, and `PUBLIC` with `has_function_privilege`.

## 5. Cart compatibility and idempotency pitfalls
- Current unique key `(customer_id, product_id)` cannot represent two variant choices for the same product. Before changing it, search every cart upsert/delete/query path in browser, seller/admin tools, and server functions. Use a safe migration plan and test existing cart rows.
- If two partial unique indexes are used, one enforces one non-variant row per customer/product (`variant_id IS NULL`), another enforces one row per customer/product/variant (`variant_id IS NOT NULL`). Upsert statements must target the matching index predicate. Confirm deployed PostgreSQL version before relying on newer NULL uniqueness syntax.
- Idempotency key must not be trusted as authorization. Scope it to authenticated customer; impose length/format bounds; retain fingerprint and resulting order ID; define expiration only after provider and refund reconciliation; do not let clients choose another customer's key namespace.
- Never clear cart or return success before transaction commit. Define whether cart rows are retained until order commit and how concurrent cart edits are handled.

## 6. Attack and failure test matrix (must run against isolated clone)
No real payment. Use deterministic fixtures and mock provider responses. Tests must assert database state before and after every scenario.

### Authorization / RPC
- unauthenticated invocation; customer A invoking customer B's order; changing customer UUID; direct invocation of legacy release RPC; seller attempting customer payment/order mutation; service role path versus authenticated path.
- effective EXECUTE privileges including PUBLIC inheritance; all SECURITY DEFINER owners, search paths, grants, and nested calls.
- SQL injection-like strings in coupon/reason/address; ensure treated as data and bounded.

### Stock / concurrency
- two buyers race for last parent-only unit; two buyers race for last variant unit; different variants race against shared parent total; duplicate same product/variant cart lines; two variants of same product in one cart; invalid variant belongs to another product; inactive/unapproved product or variant; zero/negative/huge quantity; NULL/negative stock; stale cart price.
- force failure after the first decrement, after order insert, after payment insert, and during coin ledger insert; assert full transaction rollback.
- cancel/retry cancellation concurrently; cancel while webhook arrives; failed payment followed by late capture; restoration exactly once; reservation metadata mismatch; historical order with missing variant ID.
- stock reconciliation equation: initial stock - successful reservations + exactly-once valid restorations = expected stock at every checkpoint. Parent and variant stock each independently asserted.

### Idempotency / money / coins
- same key + same payload sequentially and concurrently creates one order/payment attempt/redemption/reservation only;
- same key + different payload rejects without mutation;
- different keys with identical payload behave according to documented business rule, not accidental duplicate retries;
- two concurrent checkouts competing for last coins; cap boundaries, integer/decimal edge cases, insufficient balance; duplicate redemption/release ledger insert; wallet/ledger balance invariant.
- coin release races paid transition; provider captures after user cancellation; webhook duplicates/out-of-order delivery; provider timeout after successful capture; unknown status; page limit reached; one of multiple attempts captured; amount/currency/order ID/payment ID mismatch.
- never auto-release coins when evidence is incomplete or provider state remains ambiguous.

### Existing behavior / regressions
- COD, Razorpay, UPI/card/netbanking paths as supported; standard/fast/express/scheduled delivery charges; existing coupon behavior; address ownership; multi-seller cart and seller attribution; commissions/earnings; order notifications; seller guards; award-on-delivery trigger; returns/refunds; mobile checkout and order history.
- Test all existing DB triggers in place. Verify no accidental double ShubhCoins award on repeated status updates and no duplicate notifications or refund rows.
- Browser UI must not display “paid”, “coins released”, or “stock reserved” until server/database state confirms it.

## 7. Required implementation sequence (branch only)
1. Complete static caller map: every browser, Edge Function, webhook, trigger and RPC calling checkout/cancel/mark-paid/release/coin-award; include grants and service role context.
2. Confirm PostgreSQL version, full relevant schema, all indexes/constraints, policies, triggers and function owners. Capture a versioned schema snapshot without customer data/secrets.
3. Implement isolated test fixtures and SQL integration tests. If the current Free plan cannot provide an isolated database matching production, stop and do not use production as a test environment.
4. Replace the single-function stock candidate with one coherent draft migration and rollback plan. Do not apply it to live Supabase.
5. Add idempotency table/constraints only after schema and compatibility review; test transaction-level concurrency.
6. Rewrite transition/release/cancel/payment functions together; migrate callers; then test effective ACLs and all race scenarios.
7. Run repository tests, static security checks, secret scan, and Cloudflare preview. Verify the exact tested commit; a docs-only commit or a prior passing commit is not proof that the current code passes.
8. Review the diff against the locked roadmap and all current app behavior. Keep PR #62 Draft until tests and isolated database validation pass. No merge, production migration, deployment, real payment, or production grant change without explicit approval.

## 8. Current release decision
**BLOCKED / NOT READY FOR PRODUCTION.** This is a design gate, not proof that ShubhMart is secure. No system can be guaranteed impossible to hack; the goal is to reduce attack surface, make money/stock transitions atomic and auditable, and fail closed under uncertainty. The next coding change must be backed by exact caller/schema evidence and runnable isolated tests—not by assumptions or a large unverified SQL patch.
