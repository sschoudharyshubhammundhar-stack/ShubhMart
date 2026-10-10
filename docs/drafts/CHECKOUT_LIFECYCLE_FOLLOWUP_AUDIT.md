# Checkout Lifecycle Follow-up Audit — Read-only

Date: 2026-10-10
Status: review evidence only. No runtime changes, SQL writes, migrations, merge, or deployment.

## Newly re-verified database behavior

The current live function definitions were inspected read-only for:
- `public.cancel_customer_order(uuid, text)`
- `public.cancel_unpaid_order(uuid)`
- `public.create_order_from_cart_with_coins(uuid, uuid, text, text, text, bigint)`
- `public.create_order_from_cart(...)`

### Findings

1. **Unpaid cleanup deletes the order and its items.** `cancel_unpaid_order` restores stock only when `stock_reserved` is true, then deletes payment rows, order items, and the order. Any idempotency design must decide how to replay a prior checkout attempt after cleanup without recreating the purchase. The current draft table's `order_id ON DELETE SET NULL` is not sufficient by itself to preserve a durable replay outcome.

2. **Customer cancellation and unpaid cleanup have different terminal behavior.** `cancel_customer_order` changes the order status to Cancelled, releases reserved inventory once by flipping `stock_reserved=false`, and invokes coin-release logic for unpaid orders. `cancel_unpaid_order` restores reserved inventory but then deletes the order and does not call the coin-release routine in the inspected definition. Before release, verify whether the unpaid-cleanup caller separately restores coins; do not assume the database function does so.

3. **Legacy and current order RPCs differ materially.** The inspected `create_order_from_cart_with_coins` checks product-level stock but does not decrement inventory, does not reserve variants, and does not set `stock_reserved=true`. A separate legacy `create_order_from_cart` has variant-aware checks and stock decrement but still lacks database idempotency. Do not switch callers between these functions casually; the return contracts and coin behavior differ.

4. **Variant-aware candidate is not release-ready.** It needs isolated tests against the exact schema and function definitions, including variant status values, cancellation/unpaid cleanup, coin release, coupon semantics, and grants. Static tests do not prove transaction behavior.

5. **Multi-seller semantics remain unresolved.** The current order creation contract is one order per cart and does not establish seller ownership for each order item. Marketplace release needs a deliberate parent/child order model and matching RLS/payment/refund/settlement rules.

## Required decisions before an integrated idempotent RPC can be approved

- Choose whether a cleaned-up checkout attempt keeps a durable terminal tombstone/result or whether replay returns a stable expired/cancelled outcome; it must not recreate the order.
- Ensure unpaid cleanup releases ShubhCoins exactly once, including after order deletion. Prefer an auditable, order-independent idempotency/ledger reference rather than assuming the deleted order remains available.
- Integrate the key claim, fingerprint, inventory reservation, order/items, payment metadata, coin debit and stored response in one transaction.
- Update both browser callers and Edge Function together only after the final RPC signature is agreed.
- Test concurrent retries, rollback, cancellation, cleanup and duplicate gateway callbacks in an isolated PostgreSQL environment with synthetic data.

## Safety record

No live SQL write was run. No development branch was created (none was listed during the check), and no paid branch, production migration, Edge Function deployment, merge, or real payment test was performed.

## Additional confirmation — ShubhCoins release dependency

A further read-only scan of current `public`/`private` function definitions found `release_shubhcoins_for_order(uuid)` referenced by `cancel_customer_order`, but not by the inspected `cancel_unpaid_order` function. The release function itself looks up the order row by order ID and authenticated customer before it can find the redeem ledger entry. Therefore, calling it only after `cancel_unpaid_order` deletes the order would fail its ownership/order lookup. This confirms an integration gap in the inspected function definitions; it does not prove every application-level caller path has been audited.

Before changing this behavior, trace every Edge Function/browser/cron caller and check existing ledger rows in read-only mode. The eventual fix should make order cleanup and coin release atomic and idempotent, or store a durable checkout/ledger reference that remains valid after order cleanup. Do not patch production by simply adding a call after deletion.
