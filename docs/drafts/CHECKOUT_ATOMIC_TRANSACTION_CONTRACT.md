# Checkout Atomic Transaction Contract — Draft Only

Date: 2026-10-10
Status: design proposal; not implemented, not tested against a database, and not approved for production.

## Non-negotiable invariants

1. A verified customer can create at most one checkout result for the same idempotency key and canonical request.
2. Reusing the same key with a different request fingerprint returns a conflict; it never silently changes the original checkout.
3. A retry after timeout returns the stored result or a stable terminal outcome. It must never recreate an order that was cancelled/deleted by cleanup.
4. Cart validation, stock reservation, order/items creation, ShubhCoins debit/ledger writes, idempotency result storage, and payment-intent metadata must commit or roll back together.
5. Inventory and coin credits/debits are applied at most once, including cancellation, unpaid cleanup, webhook retries, and concurrent requests.
6. Customer identity is derived from verified auth/JWT at the database boundary; never trust a client-supplied customer ID.
7. Do not claim marketplace readiness until seller attribution, parent/child order semantics, seller RLS, refunds, settlement and gateway reconciliation are defined.

## Proposed RPC boundary (signature to finalize after schema review)

A single authenticated RPC should accept:
- a stable client-generated idempotency key (UUID or suitably validated opaque key);
- address ID;
- payment method;
- delivery method;
- normalized coupon code;
- requested ShubhCoins amount.

The RPC must derive customer identity from `auth.uid()`. The Edge Function should validate request shape and authentication, then call the RPC with the customer's JWT. The customer ID supplied by the browser or Edge Function must not be an authority for ownership.

## Canonical request fingerprint

Compute the fingerprint on the server, from normalized values and the database cart snapshot, not from client JSON alone. Include:
- authenticated customer ID;
- address ID;
- normalized payment and delivery methods;
- normalized coupon code;
- requested ShubhCoins;
- sorted cart rows with product ID, variant ID (including explicit null), quantity, and server-observed price/version inputs used for pricing.

Use a stable serialization and a cryptographic hash available in PostgreSQL. A cart mutation after the first attempt must not mutate the saved result. A retry with the same key but a changed fingerprint returns a conflict and requires a new key.

## Transaction and concurrency sequence

Within one database transaction:
1. Validate key format and derive `auth.uid()`; reject unauthenticated calls.
2. Claim the unique (customer_id, idempotency_key) record. Use a unique constraint plus row locking/insert-conflict handling so simultaneous identical requests serialize.
3. If a completed record exists, compare fingerprints and return its stored outcome. If the fingerprint differs, return a conflict. If a record is still processing, wait/serialize or return a documented retryable response; never start a second order.
4. Lock relevant cart/product/variant/wallet rows in a deterministic order to reduce deadlocks.
5. Validate address ownership, active product/variant status, quantities, stock, price, coupon eligibility, coin balance, payment and delivery methods.
6. Reserve/decrement the exact product or variant inventory once. Write order and order items using the same price/variant snapshot. Mark reservation state only when reservation actually occurred.
7. Debit ShubhCoins and write its ledger reference once, if requested. Validate that the existing schema's wallet/ledger uniqueness rules support this; add no assumptions about current constraints.
8. Persist payment intent/order metadata and the complete stable response, then mark the idempotency record completed.
9. Commit. Any exception rolls back the entire transaction.

A unique idempotency key alone is not enough: the order, inventory, coins, payment metadata and replay result must share the same transaction boundary.

## Durable replay outcome and cleanup

The idempotency outcome must survive deletion of an unpaid order. Do not rely solely on an `order_id ON DELETE SET NULL` reference. Store a durable terminal state and safe response fields (for example, outcome = completed/cancelled/expired, original order UUID as a non-FK audit value where policy permits, amount/currency, and timestamps). Define retention and privacy policy before implementation.

For unpaid cleanup, do not call `release_shubhcoins_for_order` after deleting the order: its current inspected implementation looks up the order row first. Instead, redesign cleanup and release in the same transaction with an order-independent ledger reference or release coins before deletion while the order is still present, under locks and with a unique release-ledger key. A repeated cleanup must see the release marker and must not credit twice. Preserve audit history even if operational order rows are deleted.

## Cancellation, stock, payment and webhook contract

- Cancellation and unpaid cleanup lock the order and its reservation/coin ledger references.
- Inventory is restored only if a real reservation exists and has not already been released; record the transition atomically.
- A paid order must not use the unpaid cleanup path. Refund creation and gateway refund status need their own idempotency reference.
- Gateway callbacks/webhooks are at-least-once: verify signatures, deduplicate by provider event/payment ID, and enforce legal state transitions.
- Payment gateway order creation is external to the database transaction. Use a durable payment-intent/outbox state machine and reconciliation; do not hold a DB transaction open over a network request. Specify behavior if DB commit succeeds but gateway creation fails, and if gateway creation succeeds but the response is lost.

## Existing integration gaps confirmed during read-only audit

- Both `customer/customer-app.js` and `index.html` call the `create-customer-order` Edge Function but currently send no idempotency key.
- Their payloads differ: the customer app sends `shubhcoins`; the `index.html` checkout path omits it.
- The current Edge Function forwards the request to `create_order_from_cart_with_coins` without an idempotency key.
- The inspected `create_order_from_cart_with_coins` function checks product-level stock but does not reserve/decrement stock or set `stock_reserved=true`.
- The inspected `cancel_unpaid_order` restores stock if `stock_reserved=true`, then deletes payment/order-item/order rows, but does not call the ShubhCoins release function in its body.
- The inspected `release_shubhcoins_for_order` first looks up the order; therefore it cannot be safely called only after that order has been deleted.
- The current model creates one order for the whole cart and does not establish item-level seller attribution. Multi-seller behavior is unresolved.

These are findings from source and read-only function-definition inspection, not proof that every frontend, Edge Function, scheduled job, gateway callback, or trigger has been traced.

## Required tests before any runtime rollout

Use an isolated PostgreSQL environment with synthetic data; production SQL is not a test environment.

1. Same key + same request, sequential retry -> same stable result; one order and one inventory/coin effect.
2. Same key + same request, concurrent requests -> one result, no duplicate order/reservation/debit.
3. Same key + changed cart/address/coupon/coins/payment -> conflict; no second side effect.
4. Different keys -> independent legitimate checkouts subject to stock/wallet locks.
5. Exception at every transaction step -> full rollback; no orphan debit/reservation/idempotency claim.
6. Timeout after commit -> retry returns committed result.
7. Cleanup racing with retry/cancellation/webhook -> one terminal state, one stock restoration, one coin release.
8. Cleanup after order deletion -> durable replay outcome still returned; no order recreation.
9. Duplicate/late payment webhooks and gateway-order creation failures -> deterministic reconciled state.
10. Product-only and variant cart rows, inactive variant, insufficient stock, coupon rejection, zero coins, max coins, COD and online payment.
11. RLS, table grants, SECURITY DEFINER search_path, EXECUTE permissions, error redaction, and authorization ownership checks.
12. Explicit tests for multi-seller cart behavior before enabling marketplace checkout.

## Release gates

- Finish call-site inventory across frontend, Edge Functions, triggers, cron/scheduled tasks, and gateway webhooks.
- Review exact schema, indexes, grants, triggers and all relevant RPC definitions.
- Agree parent/child order and seller-attribution model.
- Implement RPC, Edge Function and both callers in one coordinated change.
- Pass static tests plus real isolated transaction/concurrency tests.
- Run COD and payment-provider sandbox tests; reconcile failure/timeout cases.
- Review security and migration rollback plan.
- Obtain explicit approval before production migration, deploy, merge, or live payment enablement.

## Safety

No production DDL/DML, migration, paid branch, deployment, merge, or live payment was performed as part of this draft.
