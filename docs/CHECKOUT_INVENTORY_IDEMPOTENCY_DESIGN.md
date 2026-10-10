# Checkout Inventory and Idempotency Design

Status: design note only. Not a migration; not approved for production execution.

## Findings from read-only inspection

- `Orders.stock_reserved` is `NOT NULL DEFAULT false`.
- Cancellation routines restore product/variant quantities only when `stock_reserved` is true.
- The inspected checkout function checks stock but does not decrement stock or set `stock_reserved`; its `FOR UPDATE OF c` locks cart rows rather than inventory rows.
- The checkout function does not accept an idempotency key.
- It creates one order for the whole cart without assigning `Orders.seller_id`; the inspected `Order_items` schema has no seller identifier.

## Required invariants

1. Stock must never become negative.
2. One customer checkout attempt must produce at most one order and one coin redemption.
3. Inventory decrement, order/items, payment intent and coin ledger changes must commit or roll back together.
4. Reservation release on cancellation must happen once and only for stock actually reserved.
5. Each seller may access only order items, shipments and settlement values belonging to that seller.

## Design to implement after isolated testing

### Inventory

- Resolve each cart product and optional variant, then lock the actual inventory row(s) in deterministic ID order.
- Validate approved/active product, variant ownership, positive quantity, price and stock while holding the inventory lock.
- Decrement inventory with a guarded update that requires `stock >= requested_quantity`; verify that one row changed.
- Create order items and mark the order reserved in the same transaction. Any error must roll back stock, order, payment and coin changes.
- Review every cancellation, unpaid-order cleanup, payment failure and refund path. Do not set `stock_reserved=true` unless a matching decrement committed in that transaction.

### Variant-aware inventory (must be solved before enabling variant checkout)

- Include `cart.variant_id` in the locked cart snapshot and validate that the selected variant belongs to the product and is available/approved under the existing variant lifecycle.
- When a variant is selected, validate and decrement `product_variants.stock` under a row lock; do not also decrement parent `products.stock` unless the existing catalog contract explicitly defines shared inventory.
- Persist `variant_id` into `Order_items` so cancellation/fulfilment uses the exact SKU selected at checkout.
- For products without variants, reserve `products.stock` as the separate path. Test both paths and ensure a failed mixed cart rolls back every reservation.

### Idempotency

- Use a database-backed key unique per authenticated customer and intentional checkout attempt.
- Store a request fingerprint and resulting order ID in the same transaction as checkout side effects.
- A retry with the same key and same request returns the original order; reusing a key with a changed request is rejected.
- Do not rely on browser state or Edge Function memory for duplicate protection.

### Multi-seller model

- Choose parent checkout plus seller-specific child orders, or one seller order per seller linked by a checkout/group ID. Never assign a mixed cart to one arbitrary seller.
- Preserve a single customer-facing checkout while reconciling payment, refunds, commission, seller earnings, shipment and payouts.
- Update seller queries, RPC ownership checks and RLS policies together; never trust seller IDs supplied by the browser.

## Test matrix

- Two customers buy the last unit concurrently: one succeeds, one gets insufficient stock; stock never goes negative.
- Variant and non-variant inventory decrement correctly.
- Same idempotency key and request returns the original order with no extra stock/coin effect.
- Same key with changed cart/address/payment intent is rejected.
- Failure during multi-item checkout rolls back all side effects.
- Cancellation releases reserved stock exactly once; unreserved legacy orders do not add stock back.
- Payment failure, checkout dismissal and duplicate gateway callbacks are safe to retry.
- Mixed-seller cart attributes each item correctly; one seller cannot read/update another seller's order.
- Refund caps and ShubhCoins restoration remain consistent.

## Safety gates

- [x] Read-only review of the full checkout RPC and customer cancellation/unpaid-order cleanup functions.
- [ ] Inspect all constraints, triggers, payment failure/refund routines and seller-order functions in a test database; the read-only schema inventory is not yet a complete lifecycle audit.
- [ ] Run the migration and tests in an isolated test database using synthetic data.
- [ ] Review function grants, `search_path`, RLS and security advisors.
- [ ] Get explicit approval before any live migration, Edge Function deployment, production deployment, merge or real payment test.

No production SQL writes, migration, function deployment, payment, merge or production deployment was performed for this design note. This plan is not a claim that protections are already implemented.


## Follow-up finding — variant inventory (2026-10-10)

The live schema has `cart.variant_id` and `Order_items.variant_id`, but the inspected `create_order_from_cart_with_coins` RPC omits both from its cart validation/insert path. It reads only `products.stock`, then writes order items without the selected variant. This is a concrete correctness gap separate from the product-level stock reservation gap. Do not ship a product-only reservation patch as a complete checkout fix: it would leave variant carts incorrect. No database writes were performed.


## Candidate implementation artifact — variant-aware stock (2026-10-10)

A complete candidate replacement function is now staged for review at `docs/drafts/CHECKOUT_VARIANT_STOCK_RESERVATION_CANDIDATE.sql`. It preserves the existing RPC signature and adds deterministic cart locking, product/variant ownership and status validation, guarded stock decrements against the selected inventory row, variant_id persistence, and `stock_reserved=true` in the same database transaction as order/payment/coin writes. A source-level regression test is at `tests/checkout-variant-stock-candidate.test.js`.

This is deliberately still a draft: static source tests are not PostgreSQL execution tests. No migration was applied. Before this candidate can be approved, test it in an isolated database and inspect the actual variant lifecycle rules, stock-restoration functions, payment failure/refund paths, function grants and security settings. It still lacks database-backed idempotency and multi-seller order splitting; those remain release blockers. No live database writes or deployment were performed.
