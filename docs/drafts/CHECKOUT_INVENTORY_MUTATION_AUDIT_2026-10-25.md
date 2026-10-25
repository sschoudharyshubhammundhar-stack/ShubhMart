# Checkout Inventory Mutation Audit — 2026-10-25

Status: **READ-ONLY SOURCE AUDIT / INCOMPLETE — NOT A RELEASE APPROVAL**

Branch reviewed: `fix/secure-checkout-edge-function`

Safety boundary:
- This document records source-level findings only. No SQL was executed against production.
- No production database, Edge Function, payment setting, deployment, or PR state was changed.
- Source files and migrations are not proof of the currently installed database function definitions or effective table grants. Where live catalog evidence is missing, the status is UNVERIFIED.
- Never describe ShubhMart as “hacker-proof”; this audit reduces uncertainty and lists gates that still need proof.

## Locked inventory invariant

The current `CHECKOUT_ISOLATED_TEST_RUNBOOK.md` explicitly locks this model:
1. Non-variant cart line of quantity Q: reserve Q from `products.stock`.
2. Variant cart line of quantity Q: reserve Q from both the parent `products.stock` and the selected `product_variants.stock`, in one transaction. If either guarded decrement fails, the whole checkout must roll back.
3. Persist product, variant, quantity, and the exact counters reserved.
4. Every cancellation, failed/unpaid cleanup, and other restoration path must restore each recorded counter exactly once.
5. All seller, admin, import, return, and restock paths must preserve the same invariant.

This is the locked product requirement, but it is not yet verified against the live schema/business meaning of the counters. If parent stock is not a true aggregate capacity, stop and reconcile the design rather than silently changing the contract.

## Mutation-path inventory

| Path | Source evidence | What it does in reviewed source | Status / risk |
| --- | --- | --- | --- |
| Coin-aware checkout | `supabase/migrations/20260924_add_shubhcoins_checkout_redemption.sql`; read-only live snapshot recorded in `LIVE_CHECKOUT_COIN_STOCK_DEEP_AUDIT_2026-10-15.md` | The recorded live definition checks parent stock but does not decrement parent or variant stock, does not read cart variant IDs, omits `variant_id` in order items, and leaves `stock_reserved` at its default. | **FAIL / release blocker** in the recorded snapshot. Re-fetch current live definition read-only before any future migration. |
| Variant-aware candidate checkout | `docs/drafts/CHECKOUT_VARIANT_STOCK_RESERVATION_CANDIDATE.sql` | Decrements only selected variant stock for variant lines; explicitly does not decrement parent stock. | **FAIL** against locked parent+variant contract. Draft only; do not apply. |
| Legacy stock patch draft | `docs/drafts/CHECKOUT_STOCK_RESERVATION_PATCH_DRAFT.sql` | Comments describe a parent-only decrement and explicitly say variant inventory needs separate schema-aware handling. | **INCOMPLETE**; not sufficient for variants or cancellation symmetry. |
| Seller product stock RPC | `supabase/migrations/20260924_seller_production_core.sql`, function `update_seller_product_stock` | Sets `products.stock = p_stock` after checking authenticated seller ownership and non-negative input. It does not update variant stock or reservation evidence. | **PARTIAL**. Need a documented meaning for parent stock and safeguards against setting aggregate stock below already reserved variant quantities. |
| Seller product edit UI | `seller/seller-panel.js`, `saveSellerProductEdit` | Updates the `products` row directly, including `stock`, only for products in Pending/Under Review/Rejected states, then resets review fields. | **UNVERIFIED** effective table grants/RLS and whether this can diverge from variants. Test policy and privilege together. |
| Seller variant creation / variant table policy | `supabase/migrations/20260924_phase2_product_variants_store_offers.sql`; `supabase/migrations/20260924_seller_variant_secure_rpc.sql`; `seller/seller-panel.js` | Variant creation stores its own stock. The migration's seller policy is `FOR ALL` on own variants, which includes UPDATE at the policy level. Effective table grants were not revalidated in this pass. | **UNVERIFIED / high priority**. If UPDATE is granted, a seller may change variant stock independently of parent stock. Check effective grants and all write callers; do not infer exploitability from policy text alone. |
| Customer cancellation | `docs/drafts/LIVE_CHECKOUT_COIN_STOCK_DEEP_AUDIT_2026-10-15.md` records the inspected live function | Recorded live function restores inventory when `stock_reserved` is true and invokes coin release for unpaid orders. | **BLOCKED**. Exact parent/variant restoration behavior and idempotency are not proven for the locked contract. |
| Unpaid cleanup | Same deep-audit document | Recorded live function restores based on `stock_reserved`, then deletes payment rows, order items, and order. | **FAIL / release blocker** for durable reconciliation: deletes payment-attempt evidence and can conflict with coin release / late capture. |
| Admin order status migration baseline | `supabase/migrations/20260924_admin_orders_finance_security.sql` | This migration version only changes `Orders.order_status` and writes an audit log; it contains no stock restoration. | **UNVERIFIED current state**: later migrations/live catalog may replace it. Reconcile the effective installed function before claiming admin cancellation restores stock. |
| Seller order status migration baseline | `supabase/migrations/20260924_seller_production_core.sql`, function `update_seller_order_status` | Allows selected order-status transitions and updates the order row; this source version does not restore stock, release coins, or create refunds on cancellation. | **UNVERIFIED current state / lifecycle gap**. Verify installed definition and all caller paths. |
| Return/refund/restock paths | Relevant migration sources exist, but a complete effective-function and table-grant inventory was not available in this pass. | No complete proof that return/exchange restocking updates parent and variant counters according to the locked contract. | **MISSING / BLOCKED**. Inventory each effective function, trigger, direct table write, import, admin and seller route. |

## Important conclusions

1. **The checkout candidate and runbook disagree.** Candidate SQL must not be applied as-is.
2. **A checkout-only fix would be unsafe.** Even a correct double decrement can create stock inflation or drift if cancellation restores only one counter, restores twice, or uses incomplete legacy order evidence.
3. **Stock columns can be changed through more than checkout.** Seller product stock RPC, seller product edit, and variant creation/table policies must be assessed as one system.
4. **The current source branch is not the same as the installed database.** Migration history and source tests do not establish the live function body, grants, triggers, or RLS behavior.
5. **No test environment is currently evidenced as available.** The runbook says to use a disposable local PostgreSQL/Supabase fixture or separately approved isolated project, and not to substitute production.

## Required next steps (in order)

1. Obtain a read-only, timestamped snapshot of the *effective* installed schema and definitions for `create_order_from_cart_with_coins`, `cancel_customer_order`, `cancel_unpaid_order`, `admin_update_order_status`, `update_seller_order_status`, all return/refund/restock functions, triggers, policies, and grants. If access is unavailable, keep the result UNVERIFIED.
2. Inventory every reference/write to `products.stock`, `product_variants.stock`, `Orders.stock_reserved`, and `Order_items.variant_id` across SQL functions, triggers, direct client writes, imports, seller/admin routes, and cleanup.
3. Define durable reservation evidence that records the exact counter(s) decremented, item/variant, quantity, and release state. A single boolean `stock_reserved` may not be sufficient to restore a mixed legacy/new order correctly.
4. Align checkout, cancellation, payment failure, unpaid cleanup, returns, and admin/seller status changes with one lock order and one idempotent reserve/release contract.
5. In an isolated database, test: parent-only line; variant line; shared parent capacity across two variants; insufficient parent stock; insufficient variant stock; rollback after each mutation; concurrent final-unit checkouts; repeated cancellation/cleanup; late capture; return/restock; seller stock edits racing checkout; and historical orders without reservation evidence.
6. Add tests for effective grants/RLS as well as runtime SQL. Source-regex tests alone are not acceptance evidence.
7. Only after all tests pass should a separate review decide whether to prepare a migration. Production SQL, deployment, PR merge, and live payment remain outside this audit.

## Verdict

**BLOCKED — do not apply the stock candidate or enable live checkout based on current evidence.** The inventory model is written down, but effective live mutation paths and end-to-end reservation/restoration symmetry remain unverified. This is an audit artifact, not a claim that the production system has been fixed.
