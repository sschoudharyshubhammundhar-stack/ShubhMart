# Checkout Lifecycle Failure Matrix — Draft Only

Status: planning/test artifact. This file does not change database behavior and is not evidence that any test has passed.

## Scope

Exercise checkout, inventory reservation, payment callbacks, cancellation, unpaid cleanup, and ShubhCoins in an isolated PostgreSQL/Supabase test environment before any production release. Use synthetic customers, products, variants, orders, and coin balances. Do not use real payments or production customer data.

## Current implementation risks already identified

- The existing `create_order_from_cart_with_coins` RPC checks product stock but does not decrement inventory or set `orders.stock_reserved`.
- The current RPC does not persist cart `variant_id` into order items or calculate the selected variant's price.
- Cancellation/unpaid cleanup restores stock only when `orders.stock_reserved = true`; therefore the reservation flag and stock decrement must be committed atomically.
- The proposed variant-aware stock-reservation SQL and idempotency design remain drafts. Neither is enabled.
- Order creation currently makes one order for the cart; multi-seller splitting and seller attribution remain unresolved.

These are review findings to verify against the exact schema/function version in the isolated test environment before implementing a migration.

## Required test matrix

| Area | Scenario | Required invariant |
|---|---|---|
| Checkout | Valid COD cart | One order and correct order items/totals; inventory and reservation flag agree |
| Checkout | Valid Razorpay initiation | Order is pending payment; no client-side signal alone marks it paid |
| Inventory | Two customers buy the final unit concurrently | At most one checkout reserves the unit; no negative stock |
| Variants | Cart contains a variant | Variant belongs to product, is active/available, its price and ID are persisted |
| Inventory | Variant stock insufficient | Entire transaction fails; no partial order, coin debit, or reservation |
| Atomicity | Failure after inventory decrement | Transaction rollback restores inventory and removes partial checkout effects |
| Atomicity | Failure during coin redemption | Order, inventory, and coin ledger changes roll back together |
| Idempotency | Same customer/key/request repeated sequentially | Same original order result; no duplicate stock or coin effects |
| Idempotency | Same customer/key/request sent concurrently | One committed order and one set of side effects |
| Idempotency | Same key but changed address/cart/variant/quantity/coupon/payment/coin amount | Stable conflict; no side effects |
| Isolation | Another customer reuses a key | No access to or disclosure of the first customer's order |
| Cancellation | Reserved order cancelled once | Reservation released once; stock and coins restored according to policy |
| Cancellation | Same cancellation repeated | No second stock/coin restoration |
| Cancellation | Legacy order with `stock_reserved=false` | No inventory inflation |
| Unpaid cleanup | Pending payment expires | Reservation released once; order state terminal/consistent |
| Payment | Duplicate valid gateway callback | No duplicate paid transition, capture, coin effect, or fulfillment |
| Payment | Invalid signature or mismatched amount/order | Rejected; order remains unpaid |
| Payment | Gateway failure after order creation | Safe retry path; no duplicate order/reservation/coin debit |
| Cart | Cart changes after first request but before retry | Fingerprint mismatch conflict; no silent purchase of a changed cart |
| Permissions | Anonymous/customer calls privileged RPC directly | Denied unless explicitly and safely authorized |
| Multi-seller | Cart has products from two sellers | Expected grouping, seller ownership, payment/refund and RLS behavior documented before enabling marketplace checkout |

## Evidence to capture per test

- Starting and ending product/variant stock.
- Order count, order status, order items, `variant_id`, `stock_reserved`, and payment reference.
- Coin balance and ledger rows before/after.
- Cart contents before/after.
- Authenticated user and RPC/function identity.
- SQLSTATE/error category for rejected cases.
- Two-session/concurrency traces for race cases.

## Release gates

1. Run tests against an isolated database with a reviewed schema snapshot.
2. Verify all inventory, coin, order, and idempotency effects share a transaction.
3. Verify cancellation, unpaid cleanup, refunds, and duplicate callbacks are idempotent.
4. Review RLS, grants, SECURITY DEFINER functions, and fixed `search_path`.
5. Complete browser COD and Razorpay sandbox smoke tests on desktop and mobile.
6. Review multi-seller order semantics and seller panel access.
7. Obtain explicit release approval before any production migration, merge, deployment, or live payment test.

## Not done

No SQL has been applied by this document. No isolated PostgreSQL tests or browser smoke tests are claimed as passed. No production database writes, payment tests, PR merge, or deployment were performed.
