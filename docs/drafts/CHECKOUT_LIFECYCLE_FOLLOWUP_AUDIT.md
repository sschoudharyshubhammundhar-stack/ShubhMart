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


## Additional application-level call-site trace — 2026-10-10

A source scan of the current PR branch's frontend files adds these concrete caller findings. This is still not a complete audit of remote Supabase triggers or provider-side systems.

### `index.html` checkout

- Defines a `cancelUnpaidOrder(orderId)` helper that calls `cancel_unpaid_order`.
- Calls `cancel_unpaid_order` directly when Razorpay payment setup fails and when payment verification returns an error. The broader file contains five textual occurrences, including the helper and call sites.
- Calls `create-customer-order` through `fetch`; the request body includes address, payment method, delivery method and coupon code, but omits ShubhCoins and an idempotency key.
- Calls `cancel_customer_order` when the payment session is missing and from the customer order-cancellation flow.
- Uses a separate `razorpay-payment` Edge Function endpoint. Its implementation and all provider webhook/callback state transitions still require audit.

### `customer/customer-app.js` checkout

- Calls `create-customer-order` via `sb.functions.invoke`, sending address, payment method, delivery method, coupon code and ShubhCoins, but no idempotency key.
- Calls `release_shubhcoins_for_order` from the browser through `releaseShubhCoinsForOrder(orderId)` when payment verification throws, Razorpay modal is dismissed, payment fails, and in non-COD checkout error handling.
- The frontend reports that coins were released after the modal-dismiss handler resolves, but the helper catches RPC errors internally; therefore a resolved helper promise does not prove the database release succeeded. User-facing wording should not claim a successful release unless the RPC result confirms it.
- This path does not directly call `cancel_unpaid_order` in the inspected file.

### Important implication

There are two different failure-cleanup patterns: `index.html` invokes unpaid-order cleanup, while `customer/customer-app.js` invokes ShubhCoins release and may leave order/inventory cleanup to another path. They must be reconciled as one documented state machine before runtime changes. Avoid blindly adding both calls: order deletion, stock restoration and coin release must be serialized and idempotent, and gateway failure does not necessarily mean the payment is definitively unpaid.

### Remaining trace work

- Inspect the `razorpay-payment` function implementation and any external gateway webhook configuration/callbacks.
- Search the complete Supabase schema for triggers, scheduled jobs, and functions that call either cleanup/release routine.
- Review current coin ledger rows read-only to determine whether duplicate release entries or unresolved redemption states exist.
- Confirm the exact `release_shubhcoins_for_order` return value contract and make the frontend show success only when the RPC result confirms it.
- No live writes, migrations, deployment or merge were performed for this trace.
