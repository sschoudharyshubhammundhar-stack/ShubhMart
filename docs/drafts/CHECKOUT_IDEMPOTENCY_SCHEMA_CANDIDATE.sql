-- DRAFT ONLY — DO NOT RUN AGAINST PRODUCTION.
-- This is a schema-shape proposal, not a complete idempotency implementation.
-- Before any migration: confirm the target schema, FK/delete behavior, function owner,
-- role grants, and actual checkout RPC signature in an isolated PostgreSQL database.
-- This table alone does NOT prevent duplicate orders until the checkout RPC is changed
-- to claim/replay the key atomically with order, inventory, payment and coin effects.

BEGIN;

-- Prefer a non-exposed schema for internal idempotency records.
-- Review whether "private" already exists and who owns it before applying.
CREATE SCHEMA IF NOT EXISTS private;

CREATE TABLE IF NOT EXISTS private.checkout_idempotency (
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  idempotency_key uuid NOT NULL,
  request_fingerprint text NOT NULL,
  order_id uuid NULL REFERENCES public."Orders"(id) ON DELETE SET NULL,
  state text NOT NULL DEFAULT 'processing'
    CHECK (state IN ('processing', 'completed')),
  response_version smallint NOT NULL DEFAULT 1
    CHECK (response_version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz NULL,
  CONSTRAINT checkout_idempotency_customer_key_unique
    UNIQUE (customer_id, idempotency_key),
  CONSTRAINT checkout_idempotency_completion_consistent
    CHECK (
      (state = 'processing' AND completed_at IS NULL)
      OR
      (state = 'completed' AND completed_at IS NOT NULL)
    )
);

-- Do not expose idempotency rows through the browser/Data API.
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE private.checkout_idempotency FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE private.checkout_idempotency FROM service_role;

COMMIT;

-- IMPLEMENTATION REQUIRED BEFORE THIS TABLE CAN BE USED:
-- 1. Update the single order-creation RPC to accept a client-generated UUID key.
-- 2. Derive customer identity from auth.uid()/verified context; do not trust a browser customer_id.
-- 3. Canonicalize and hash server-validated address/payment/delivery/coupon/coin/cart+variant inputs.
-- 4. Atomically insert/lock the (customer_id, key) row; same fingerprint replays original result,
--    different fingerprint returns conflict. A unique constraint must arbitrate concurrent calls.
-- 5. Commit idempotency result, order/items, inventory reservation, payment intent metadata,
--    and coin ledger effects in the same transaction.
-- 6. Review order deletion semantics before keeping ON DELETE SET NULL: replay behavior after
--    cancellation/deletion must not recreate a purchase.
-- 7. Add authenticated Edge Function and frontend key propagation; do not write the key in a
--    separate network request from order creation.
-- 8. Test concurrency, rollback, cancellation, unpaid cleanup, duplicate gateway callbacks,
--    RLS/EXECUTE grants and multi-seller behavior in isolated PostgreSQL first.
--
-- No SQL in this file has been executed.