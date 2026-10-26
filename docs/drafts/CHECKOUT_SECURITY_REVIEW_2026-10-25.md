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

### H-03 — Payment-attempt identity: paid transition improved, attachment remains unresolved
**Status: PARTIAL / release blocker**

The latest draft now resolves `mark_razorpay_paid_secure` using the exact `order_id + customer_id + gateway_order_id` tuple and locks that row. The source regression test for this change passes. This corrects the earlier “latest row” selection in the paid transition.

However, `attach_razorpay_order` still selects the latest eligible row where `gateway_order_id` is null or already equals the supplied ID. The flow does not yet carry a durable attempt ID from attempt creation through provider order creation and attachment. Concurrent create-order requests or retries therefore still need a deterministic, idempotent attempt-creation contract.

**Required:** create/claim one durable attempt before making the external provider request; bind the provider order to that exact attempt; enforce uniqueness/locking and stable retry behavior. Add isolated tests for two attempts, concurrent creation, out-of-order callbacks and duplicate callbacks. Do not apply the draft until tested.

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

### H-09 — Stock-reservation candidate conflicts with the locked inventory contract
**Status: FAIL / release blocker**

The isolated-test runbook's current locked contract says variant orders decrement both `products.stock` and the selected `product_variants.stock` atomically, with rollback if either decrement fails. The current `CHECKOUT_VARIANT_STOCK_RESERVATION_CANDIDATE.sql` explicitly says variant inventory is owned by the variant and does not also decrement parent product stock. These two artifacts conflict. We must not pick one based on assumptions: the real meaning of both stock counters and all other stock mutation paths must be verified first.

**Required:** inspect the real schema and every seller/admin/import/return/restock/cancel mutation path in an isolated fixture; agree and document one invariant; then update the candidate and tests together. Until this conflict is resolved, the stock candidate is not eligible for application.

### H-10 — Latest CI evidence is source-level only
**Status: PASS for configured checks; BLOCKED for runtime proof**

For commit `fba59838f829c8f1d96eb7df434b192a9f3182fe`, GitHub Actions reports the configured JavaScript syntax and checkout regression tests passed (42 tests, 0 failures), and the configured secret scan passed. The Razorpay exact-attempt regression test is included. These tests read source text and use pattern assertions; they do not execute PL/pgSQL or prove concurrent runtime behavior.

**Required:** preserve these source checks, then run the isolated PostgreSQL and provider-mock acceptance suite in `CHECKOUT_ISOLATED_TEST_RUNBOOK.md`. The latest successful run is not evidence that production database/functions were changed or validated.

## Mandatory release gates

- [ ] Complete schema and privilege inventory; no guessed columns or grants.
- [ ] Implement database-level idempotency in the same transaction as all checkout side effects.
- [ ] Bind payment confirmation and provider-order attachment to one durable, exact payment-attempt row.
- [ ] Resolve the parent/variant stock-counter contract conflict and align candidate SQL, cancellation and tests.
- [ ] Prove cancellation, unpaid cleanup, payment failure, and coin release are idempotent and atomic.
- [ ] Add isolated PostgreSQL concurrency and rollback tests.
- [ ] Add Edge Function behavior tests for invalid, delayed, duplicate, and captured provider payments.
- [ ] Re-run security advisor and inspect all relevant findings; distinguish warnings from verified exploitable issues.
- [ ] Review multi-seller ownership, seller RLS, refunds, settlement, and order attribution before marketplace launch.
- [ ] Separate review/approval for migration, Edge Function deployment, and production release.

## Current release verdict

**BLOCKED — do not treat checkout/payment as production-ready.** The source draft improves payment verification, but the database transition, idempotency, stock/coin lifecycle, schema/grants, and runtime integration remain unproven. This report makes no production changes.
