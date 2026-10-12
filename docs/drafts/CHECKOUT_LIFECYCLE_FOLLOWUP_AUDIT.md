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


### Payment-function source availability check

The PR branch repository tree contains `supabase/functions/create-customer-order` and `supabase/functions/shubhmart-ai`, but no `supabase/functions/razorpay-payment` source directory. Since `index.html` calls the deployed `razorpay-payment` endpoint, its implementation cannot be audited from the current checked-in source. Treat signature verification, gateway-order creation, payment capture/verification, webhook deduplication, and order-state updates as unverified until the actual deployed function source and provider webhook configuration are located. Do not infer that payment verification is secure merely because the customer-order function is protected.


## Live Supabase Edge Function and payment RPC audit — read-only, 2026-10-12

The Supabase project function inventory shows `razorpay-payment` is ACTIVE (version 4, `verify_jwt=true`). Its deployed source was retrieved read-only through the Supabase function API; it is not currently checked into this PR branch.

### Confirmed payment flow behavior

- The function authenticates the bearer token with `sb.auth.getUser()` and scopes the order lookup to the authenticated customer.
- `create_order` compares the client-supplied amount to the stored order total before creating a Razorpay order.
- `verify_payment` computes an HMAC-SHA256 signature over the client-provided `razorpay_order_id|razorpay_payment_id`.
- The function then calls `mark_razorpay_paid_secure` using a service-role client. The database function checks customer ownership and requires the supplied Razorpay order ID to equal the ID stored in `payments`.
- The deployed function does not fetch the payment entity from Razorpay to independently confirm the payment's actual amount, currency, order ID and captured/authorized status before marking the order Paid. This needs a server-to-server provider verification step and idempotent state transition.
- The CORS policy currently allows `Access-Control-Allow-Origin: *`. Because the function still requires an authenticated JWT, this alone is not proof of an authentication bypass, but production origin restrictions should be reviewed and tested before changing them.

### High-priority integration mismatch found

- During `create_order`, the deployed function calls `sb.rpc("attach_razorpay_order", ...)` on a client carrying the customer's Authorization header.
- A read-only query of `information_schema.routine_privileges` showed `attach_razorpay_order` EXECUTE granted to `postgres` and `service_role`, but not `authenticated` or `anon`.
- The same privilege inventory showed `mark_razorpay_paid_secure` EXECUTE granted to `postgres` and `service_role`; the deployed function correctly calls this latter RPC with a service-role client after verifying the user and order.
- Therefore, the current `attach_razorpay_order` call appears unable to execute under the customer-scoped client. The function may create a Razorpay order externally and then fail to persist its gateway-order ID, leaving an orphaned gateway order and a checkout that cannot complete. Confirm with sanitized function logs and a sandbox test; do not test by charging a real customer.
- Candidate correction: after customer authentication and the ownership/amount checks already present, call `attach_razorpay_order` through a server-side service-role client, while keeping strict ownership validation in the Edge Function and database RPC. Do not grant broad EXECUTE to authenticated users as a quick fix. Also add cleanup/reconciliation for a gateway order created when the DB attach step fails.

### Required payment tests before rollout

1. Razorpay sandbox order creation persists exactly one matching `payments.gateway_order_id`.
2. RPC permission failure is handled without falsely reporting checkout success; orphan gateway orders are logged/reconciled.
3. Invalid signature, mismatched order ID, mismatched amount/currency, failed/authorized-but-not-captured payment, and duplicate verification requests do not mark an order Paid incorrectly.
4. Valid captured payment is confirmed server-to-server with Razorpay and transitions order/payment atomically and idempotently.
5. Duplicate/late callbacks, client retries, network timeout after provider success, and cancellation racing with verification yield one consistent terminal state.
6. The source of the deployed function is checked into the repo and reviewed so the PR and production code cannot silently diverge.

This section records a source/privilege mismatch found by read-only inspection. No live checkout was attempted, no payment was created, no SQL write/migration was performed, and no deployed function was changed.


### Candidate remediation now checked into the PR branch (not deployed)

- `supabase/functions/razorpay-payment/index.ts` now contains the reviewed function source under version control. Relative to the read-only live snapshot, the candidate confirms the Razorpay payment entity server-to-server and checks provider order ID, payment ID, INR currency, exact expected amount and `captured=true/status=captured` before invoking the privileged paid-state RPC. It also uses a narrow customer-scoped RPC call for attaching the gateway order and returns generic payment errors.
- `docs/drafts/20261012_secure_razorpay_payment_transition_candidate.sql` is a draft-only database migration candidate. It grants authenticated EXECUTE only to the ownership-checking `attach_razorpay_order` RPC, checks that the payment row was actually updated, and makes the privileged paid-state RPC retry-safe for the same payment while rejecting a different payment for an already-paid order.
- `tests/razorpay-payment-source.test.js` adds static source guardrails for authentication, provider-side amount/currency/capture checks, narrow RPC grants and idempotent paid-state behavior. These tests do not execute PostgreSQL or call Razorpay.
- The function and SQL candidate have not been deployed or applied. Before rollout, run Deno/Edge Function checks and the SQL candidate against an isolated Supabase/Postgres environment; verify the actual `payments` row cardinality, status transitions, triggers, concurrent duplicate callbacks, and behavior if the provider order succeeds but attachment fails.
- The draft function intentionally retains the existing wildcard CORS policy for now to avoid an untested origin change; restrict origins only after the actual web/app origin inventory and preflight behavior are confirmed.


### Additional payment trigger blocker found in read-only database inspection

- The current `guard_customer_payment_update()` trigger allows updates when `private.is_admin()` is true; that helper checks whether `auth.uid()` has an admin profile. A service-role Edge Function request normally has no customer `auth.uid()`, so the deployed `mark_razorpay_paid_secure` call may hit `Payment update denied` when its update reaches the `payments` trigger. This needs confirmation in isolated tests/logs; no live payment was attempted.
- The SQL candidate now proposes a narrow `auth.role() = 'service_role'` exception in the payment-update trigger, preserving the existing ownership/protected-field checks for customer requests. It also proposes idempotent paid-state transitions. This is draft-only and must be tested against the exact production schema, trigger order and JWT claim behavior before applying.
- This finding means payment verification can fail even after signature and provider data checks pass; do not assume the existing active payment function is working end-to-end.


## Extended database lifecycle and privilege scan — read-only, 2026-10-12

This pass inspected current live function definitions, non-internal triggers on Orders/payments, and EXECUTE grants. It did not change the database.

### Additional confirmed findings

1. **Order status has automatic side effects.** Orders has an AFTER UPDATE trigger that awards ShubhCoins when an order first transitions to Delivered, and another trigger that writes customer notifications for order/payment status changes. The reward routine checks for an existing order_reward ledger entry keyed by order ID before crediting, which is a useful idempotency guard. Any order state transition test must account for these triggers rather than testing only the RPC body.

2. **Admin cancellation also restores inventory and may queue a refund.** admin_update_order_status locks the order, restores product/variant inventory only if stock_reserved=true, flips that flag off, and inserts a pending refund for paid orders. The current customer order-creation RPC that checks stock without reserving it does not set that flag, so these cancellation safeguards cannot restore inventory that was never reserved. This reinforces that inventory reservation and its flag must be written atomically with order/items.

3. **Seller cancellation has a different path.** update_seller_order_status allows seller cancellation only for early states and updates order status, but the inspected definition does not itself restore stock, create a refund, or release ShubhCoins. Confirm whether seller cancellation is intentionally allowed to leave cleanup to another trusted workflow; do not assume it is equivalent to customer/admin cancellation.

4. **Two payment-marking RPCs exist.** Both mark_razorpay_paid and mark_razorpay_paid_secure are present. The older mark_razorpay_paid checks auth.uid() ownership and updates Orders/payments but does not itself validate the provider payment entity, amount, currency or capture status. The inspected EXECUTE grants list only postgres and service_role for these two functions, not authenticated; the deployed function uses the secure-named RPC. Before any removal/revocation, search all Edge Functions and server-side callers to prove the older RPC is unused.

5. **Payment row cardinality needs an explicit invariant.** The current attach function updates all payment rows matching the order/customer and returns no row-count result; the current secure mark-paid function selects one matching gateway order with LIMIT 1 and updates all matching order/customer payment rows. Candidate migration currently assumes the intended invariant is one payment row per order. Before applying it, inspect existing duplicate rows and confirm whether a unique constraint/index already enforces one payment intent per order; if not, add a safe deduplication/constraint plan only after data review.

6. **Trigger security requires role-aware testing.** The payments table has BEFORE INSERT and BEFORE UPDATE guard triggers. The update guard permits an admin or the customer owner and otherwise raises Payment update denied; the candidate service-role exception is therefore a security-sensitive change. Test signed service-role claims, ordinary authenticated customer JWTs, anonymous requests, and admin JWTs separately in an isolated database. Preserve protected-field checks for customer sessions.

### Required next checks

- Read-only: check uniqueness/indexes and current duplicate payment rows per order without exposing customer details.
- Read-only: search all deployed Edge Function source for calls to both payment-marking RPCs and all order-cancel/coin-release functions; inspect scheduled jobs/webhooks where supported.
- Isolated tests: verify Delivered reward is credited once under concurrent status updates; customer/admin/seller cancellation and payment verification races restore inventory at most once; paid cancellation queues one refund; coin release cannot be duplicated or lost after cleanup.
- Keep all database changes in the draft PR until exact-schema tests and review pass.

No payment was initiated, no live SQL write/migration was performed, no Edge Function was deployed, and no PR merge or production deployment was performed.


### Payment-row cardinality check — read-only, 2026-10-12

- Current public.payments indexes are a primary key on id plus non-unique indexes on customer_id and order_id; no unique index on order_id was found.
- A read-only aggregate found 0 orders currently having more than one payments row, and 0 duplicate non-null (order_id, customer_id, gateway_order_id) groups.
- This is a snapshot, not a concurrency guarantee. The candidate assumes one payment intent per order, but that invariant is not enforced by the inspected indexes. Before adding a unique constraint, verify whether the business allows retries/new payment attempts per order; the safer model may be a separate payment-attempt table with a unique active attempt or provider-order ID rather than a blanket unique order_id constraint.
