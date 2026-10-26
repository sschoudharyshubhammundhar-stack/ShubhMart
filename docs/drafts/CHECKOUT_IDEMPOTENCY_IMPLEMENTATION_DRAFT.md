# Checkout Idempotency — Implementation Draft

Status: design artifact only. Not a migration and not enabled in any environment.

## Goal

A retried checkout request must not create a second order, reserve stock twice, or redeem ShubhCoins twice. The database—not browser storage or Edge Function memory—is the source of truth.

## Recommended contract

1. The authenticated client creates a UUID idempotency_key once when the customer deliberately starts checkout. Network retries for that same attempt reuse the same key. A new intentional checkout gets a new key.
2. The Edge Function derives the customer ID from the verified access token. It must ignore/reject a customer ID supplied by the browser.
3. The database RPC accepts the key and canonical checkout inputs. It calculates a request fingerprint from server-validated values: customer, address, payment method, delivery method, normalized coupon, requested ShubhCoins, and a deterministic snapshot of cart product/variant IDs and quantities. Never trust a client-supplied fingerprint.
4. The idempotency record, stock reservation, order and items, payment-intent metadata, coin ledger and result must commit in the same database transaction.
5. Same customer + same key + same fingerprint: return the original order/result without repeating side effects.
6. Same customer + same key + different fingerprint: reject with a stable conflict error; do not mutate cart, stock, order, or coins.
7. Concurrent calls using the same key must serialize via a unique constraint and row lock. A prior SELECT alone is not safe.
8. If the first transaction rolls back, its idempotency record and all checkout side effects roll back together so the same attempt can be retried safely.
9. Never store card PAN/CVV or payment secrets in the idempotency table. Store only safe references and the minimal result needed to replay the response.

## Schema shape to review (not executable yet)

Prefer an unexposed schema such as private if available, or explicitly revoke Data API access and keep RLS/privileges tight.

- customer_id uuid NOT NULL
- idempotency_key uuid NOT NULL
- request_fingerprint text NOT NULL
- order_id uuid NULL (FK target must match actual order table and delete behavior)
- state text NOT NULL with a constrained lifecycle, e.g. processing, completed
- response_version smallint NOT NULL
- created_at timestamptz NOT NULL DEFAULT now()
- completed_at timestamptz NULL
- Unique constraint on (customer_id, idempotency_key)

Do not implement this table as a public browser-readable log. Restrict INSERT/UPDATE/SELECT to the database owner/RPC path; revoke broad PUBLIC, anon and authenticated privileges as appropriate. Any SECURITY DEFINER function must use a fixed safe search_path, validate the authenticated customer, and have reviewed EXECUTE grants.

## Important transaction boundary

An Edge Function that calls an order-creation RPC and then writes an idempotency row in a separate request is not atomic. A crash between those calls can still duplicate orders. Implement the key and replay behavior inside the single database transaction that creates the order, or use a single database RPC that owns the entire transaction.

## Payment gateway notes

- Idempotency of order creation is distinct from gateway idempotency. Use a stable gateway idempotency/reference key where the provider supports it.
- Do not mark payment successful based only on a browser redirect. Verify provider callbacks server-side and make callbacks idempotent too.
- Keep COD and Razorpay states distinct; replaying checkout must not accidentally capture/authorize a payment again.
- Define what happens when order creation succeeds but the gateway call fails. The order/payment state machine must support a safe retry without reserving inventory or redeeming coins twice.

## Required integration sequence

1. Verify current Edge Function request contract and all checkout callers.
2. Inspect order/payment/coin schema, triggers, grants, cancellation, unpaid cleanup, refund and gateway callback functions.
3. Add schema + RPC contract in a reviewable migration draft.
4. Update Edge Function to pass a stable key and return the database's original result on retries.
5. Update frontend so a key is created per intentional attempt and retained across network retries; clear it only after a definitive completion or when the user starts a new attempt.
6. Run isolated PostgreSQL concurrency/failure tests and Edge Function tests.
7. Review grants, RLS, SECURITY DEFINER search paths and Supabase security advisors.
8. Only then propose a separate release decision. No production migration or deployment is implied by this document.

## Acceptance test matrix

- Same key + same request sequential retry: same order ID; one order; one stock decrement; one coin redemption.
- Same key + same request concurrent retry: same order ID returned to both callers; no duplicate side effects.
- Same key + different address, payment method, coupon, coin amount or cart snapshot: conflict; no second order.
- Different keys from same customer: two distinct intentional checkouts may create two orders, subject to current cart semantics.
- Transaction failure after stock decrement but before order completion: all changes roll back.
- Transaction failure after coin validation/redemption but before commit: coin and order effects roll back together.
- Existing key belongs to another customer: cannot reveal or return that customer's order.
- Key replay after cancellation: return original checkout outcome, never silently recreate the order; a new deliberate purchase requires a new key.
- Duplicate gateway callback: no duplicate capture, stock release, refund or coin restoration.
- Legacy orders with no reservation flag: cancellation must not inflate stock.
- Same key with a cart changed by another tab: reject fingerprint mismatch rather than silently checking out a different cart.

## Current release status

This is a proposal only. It has not been run against PostgreSQL, added to a live schema, or deployed. Current checkout release blockers remain: isolated database tests, inventory/cancellation/payment lifecycle verification, and the multi-seller order model.
