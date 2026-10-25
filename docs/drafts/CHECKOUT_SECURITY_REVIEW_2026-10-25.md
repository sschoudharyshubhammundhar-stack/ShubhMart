# Checkout Security Review — Follow-up Findings

Date: 2026-10-25
Branch: `fix/secure-checkout-edge-function`
Scope: read-only source review of the checkout Edge Functions, Razorpay transition candidate SQL, stock-reservation candidate SQL, and source-level regression tests.

## Status and safety boundary

- This is a source review, not a penetration-test certification.
- The reviewed SQL files are drafts. They have not been applied to production or proven against an isolated PostgreSQL database.
- No production settings, database rows, Edge Function deployments, or PR merge actions were changed by this review.
- Existing source-pattern tests are useful guardrails, but do not establish SQL correctness, runtime behavior, concurrency safety, RLS/grant correctness, or provider integration.

## Findings

### H-01 — Checkout idempotency is still absent from the stock-reservation candidate
**Status: FAIL / release blocker**

The candidate function `create_order_from_cart_with_coins` can create an order and perform stock/coin side effects on every successful invocation. The draft explicitly says it does not implement database-backed idempotency. Two requests with the same user intent can therefore produce two orders and potentially reserve/debit twice.

**Required:** one transaction owns the idempotency key, canonical request fingerprint, order/items, stock reservation, ShubhCoins ledger mutation, payment intent, and durable replay response. Enforce a unique key per customer and serialize concurrent retries. Same key/different request must return conflict without side effects.

### H-02 — Cancellation and unpaid cleanup are not yet proven symmetric with reservation and coin debit
**Status: BLOCKED / release blocker**

The candidate marks `stock_reserved=true` and decrements inventory inside the transaction, but the complete cancellation, failed-payment, and unpaid-cleanup paths have not been tested together with this candidate. Earlier source inspection found a cleanup path that deletes the order before a coin-release function can find it. Applying only the reservation candidate could make this mismatch more consequential.

**Required:** in an isolated database, test cancel-before-payment, repeated cancellation, cleanup retry, failed payment, paid-order refund path, and coin release. Every reservation/debit must have exactly one corresponding restoration/release, and repeated cleanup must be a no-op. Do not call an order-dependent coin-release function after deleting its order row.

### H-03 — Payment-attempt selection is based on latest `updated_at`, not an explicit attempt identity
**Status: FAIL / requires design correction before release**

Both `attach_razorpay_order` and `mark_razorpay_paid_secure` select a payment row by `updated_at DESC, id DESC`. The verification request carries the gateway order ID, but the secure transition first selects the latest row and then compares that row's gateway order ID. With multiple attempts or out-of-order callbacks, the latest row may not be the attempt associated with the verified provider payment.

**Required:** resolve the payment row by the exact `order_id + customer_id + gateway_order_id` tuple and lock that row; require exactly one match. Make retries for the same payment idempotent even if a later attempt exists. Add tests for two attempts, callbacks arriving out of order, and duplicate callbacks.

### H-04 — The unique payment-ID index draft needs broader duplicate preflight and retry tests
**Status: BLOCKED**

The draft proposes a unique partial index on `gateway_payment_id`, but its transition pre-check only looks for the same payment ID on a different order. A duplicate mapping to a different attempt row for the same order is also a consistency case that must be handled intentionally. The unique index may reject the update, but relying on an uncaught constraint error is not a complete, stable retry contract.

**Required:** preflight duplicates across all rows, reconcile manually, then test duplicate payment ID across different orders and different attempts of the same order. Return stable, non-sensitive outcomes and preserve transaction atomicity.

### H-05 — Payment state update and gateway verification still need isolated integration tests
**Status: PARTIAL / BLOCKED**

The Edge Function draft now verifies Razorpay's payment entity server-to-server (payment ID, provider order ID, amount, INR currency, captured status) before invoking the privileged paid-state RPC. That is an important source-level improvement, but the draft migration has not been applied/tested and the deployed function is still a different version.

**Required:** test valid captured payment, failed/authorized-but-not-captured payment, wrong amount/currency/order ID, invalid HMAC, repeated valid callback, payment ID already used, RPC failure after provider capture, and reconciliation after a timeout. Confirm no browser-controlled field can directly mark an order paid.

### H-06 — CORS remains wildcard in the draft Edge Functions
**Status: HARDENING REQUIRED; not by itself proof of auth bypass**

Both reviewed Edge Function drafts use `Access-Control-Allow-Origin: *`. Bearer authentication is present, so wildcard CORS alone does not prove unauthorized access; however, the production web origins and mobile/PWA request behavior must be mapped before narrowing CORS. Ensure OPTIONS behavior, allowed headers, and error responses are consistent.

**Required:** inventory legitimate origins, restrict browser origins where feasible, and test preflight plus authenticated/unauthenticated requests. Do not break mobile clients blindly.

### H-07 — Source-regex tests do not execute SQL or prove security properties
**Status: PARTIAL**

Current tests assert that expected code fragments exist. They do not execute PostgreSQL functions, simulate two concurrent sessions, validate trigger/RLS/grants, mock Razorpay responses, or verify actual rollback behavior.

**Required:** retain source tests, add Edge Function behavior tests with mocked provider responses, and add isolated PostgreSQL integration tests for permissions, transaction rollback, concurrency, stock/coin invariants, and retry semantics.

### H-08 — Order creation must be verified against real schema, triggers, and grants before any migration
**Status: UNVERIFIED / BLOCKED**

The stock candidate assumes exact columns, status values, triggers, and wallet/ledger semantics (including `products`, `product_variants`, `Orders`, `Order_items`, `payments`, `shubhcoins_wallets`, and `shubhcoins_ledger`). The latest read-only schema/grant inspection was not complete, so these assumptions are not release-verified.

**Required:** export/read the schema and function definitions from an isolated clone or non-production test database; verify every referenced column, constraint, trigger, RLS policy, function owner, search path, and EXECUTE grant. Do not use production checkout as a test.

## Mandatory release gates

- [ ] Complete schema and privilege inventory; no guessed columns or grants.
- [ ] Implement database-level idempotency in the same transaction as all checkout side effects.
- [ ] Bind payment confirmation to the exact payment-attempt row.
- [ ] Prove cancellation, unpaid cleanup, payment failure, and coin release are idempotent and atomic.
- [ ] Add isolated PostgreSQL concurrency and rollback tests.
- [ ] Add Edge Function behavior tests for invalid, delayed, duplicate, and captured provider payments.
- [ ] Re-run security advisor and inspect all relevant findings; distinguish warnings from verified exploitable issues.
- [ ] Review multi-seller ownership, seller RLS, refunds, settlement, and order attribution before marketplace launch.
- [ ] Separate review/approval for migration, Edge Function deployment, and production release.

## Current release verdict

**BLOCKED — do not treat checkout/payment as production-ready.** The source draft improves payment verification, but the database transition, idempotency, stock/coin lifecycle, schema/grants, and runtime integration remain unproven. This report makes no production changes.
