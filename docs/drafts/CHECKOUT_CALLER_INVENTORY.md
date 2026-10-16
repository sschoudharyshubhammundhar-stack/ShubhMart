# Checkout Caller Inventory — Phase 1 Audit

Status: audit only. No runtime code changes. No production database writes or deployments.

## Confirmed checkout entry points on `fix/secure-checkout-edge-function`

### 1. `customer/customer-app.js`

- Customer-facing `placeOrder()` invokes `create-customer-order` through `sb.functions.invoke`.
- Sends `address_id`, `payment_method`, `delivery_method`, `coupon_code`, and `shubhcoins`.
- Does not currently send an idempotency key.
- On COD success it deletes the customer's cart in a separate request.
- For online payment it creates the gateway order after the database order is created; dismissal/failure paths call coin-release logic.

### 2. `index.html`

- Its separate `checkout()` implementation calls `/functions/v1/create-customer-order` with `fetch`.
- Sends `address_id`, `payment_method`, `delivery_method`, and `coupon_code`.
- Does not send `shubhcoins` or an idempotency key.
- On COD or successful online payment it deletes the cart in a separate request.
- Payment setup and failure/dismissal paths call cancellation RPCs.

## Why this matters

The two callers currently have different checkout payloads and separate post-order cleanup behavior. Adding an idempotency key to only one caller would leave the other path unprotected. Adding the key in the browser or Edge Function alone is insufficient: the current database RPC must atomically claim/replay the key with order, item, stock, payment metadata and coin effects.

The online gateway step occurs after order creation. Gateway order creation, payment verification callbacks, cancellation/unpaid cleanup and coin release therefore need a lifecycle review; idempotent order creation alone does not make the entire payment lifecycle idempotent.

## Phase 1 safe implementation order

1. Keep both current caller implementations unchanged until a database RPC contract is finalized.
2. Define one shared request contract: stable UUID per intentional checkout attempt, reused only for network retries; server-validated address, payment/delivery, coupon, coins, and deterministic cart/variant snapshot.
3. Implement the key claim, fingerprint comparison, order creation, inventory reservation, item snapshot, payment metadata and coin ledger effects in one database transaction.
4. Update and test both callers together, including their different coin and cancellation behavior.
5. Run synthetic-data PostgreSQL tests in an isolated database for sequential and concurrent retries, fingerprint conflicts, rollback, stock races, variants, cancellation, unpaid cleanup, duplicate gateway callbacks, and coin restoration.
6. Review grants, RLS, SECURITY DEFINER ownership/search_path, seller attribution, and multi-seller behavior.
7. Only after evidence is green, present a separate release decision. No merge, production migration, deployment, or real-payment test is implied.

## Release blockers still open

- No idempotency key is accepted by the current Edge Function/RPC path.
- Current RPC does not reserve inventory or persist variant-aware order items correctly.
- The two frontend checkout callers are not contract-aligned.
- Isolated PostgreSQL execution and lifecycle tests have not been completed.
- Multi-seller order attribution/splitting is not solved by the current single-order RPC.

## Safety record

This audit was based on source review of the PR branch. It did not alter checkout behavior, execute SQL, create a paid database branch, merge the PR, deploy functions, or touch production order data.
