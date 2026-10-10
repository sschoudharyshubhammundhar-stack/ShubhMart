# ShubhMart Security + QA Audit (Roadmap Phase 2)

Updated: 2026-10-09

Scope: read-only inspection of the connected Supabase project's current policies, security/performance advisor output, active Edge Function source, and the feature branch. No production deploy, SQL write, migration execution, or payment transaction was performed.

## Verified improvements in this branch

- `supabase/functions/create-customer-order/index.ts` now verifies the bearer token using the server auth client and forwards that same customer JWT to `create_order_from_cart_with_coins`, so the database function's `auth.uid() = p_customer_id` guard can evaluate in the customer's context.
- `tests/create-customer-order-source.test.js` adds regression assertions for token verification, customer-JWT propagation, error sanitization, and request/auth guards. The latest commit's combined status reports a successful Netlify Deploy Preview, but that is not evidence that the Node regression tests or Cloudflare Worker preview passed.
- GitHub Actions PR syntax and checkout regression checks passed for commit `158d3b017ee9bfb6bb0cb7455a761c6e5b5cc985`.
- These source changes are not proof that the live Supabase Edge Function was updated. Live function changes require a separate approved deployment.

## Findings requiring follow-up

### High priority: checkout inventory and duplicate-order behavior
- Read-only inspection of the live function definition confirmed it checks `products.stock` but does not decrement stock or set `Orders.stock_reserved`. Its cart loop uses `FOR UPDATE OF c` (locking cart rows, not the matching product rows), so concurrent buyers can both pass the stock check. No idempotency key is accepted, so retries/double taps can create duplicate orders and redeem ShubhCoins more than once.
- The same function inserts a single `Orders` row for the whole cart without setting `Orders.seller_id`; `Order_items` has no seller identifier column. Multi-seller cart attribution/seller isolation is therefore not implemented in this RPC's current body. This must be designed against the actual seller-order panel and existing constraints before changing the schema.
- Do not use real payments or enable live checkout until the above is resolved and end-to-end tests pass.

### High priority: seller onboarding authorization
- The seller panel client upserts `profiles.role = 'seller'` during onboarding.
- Current RLS policy inspection showed self-insert/update policies permit roles `customer` and `seller`, but not `admin`. This does not by itself demonstrate admin privilege escalation; however, role assignment should be owned by a trusted backend or explicitly documented and tested against the seller approval lifecycle.
- The product insert RLS policy requires an Approved seller, while the UI attempts to insert Pending products. Test the intended onboarding/approval flow end-to-end; a mismatch may prevent pending sellers from submitting listings.

### Security advisor review
- Supabase advisor reported 58 authenticated-executable SECURITY DEFINER functions. This is a warning requiring per-function authorization review, not proof that all 58 are vulnerable.
- Advisor also reported leaked-password protection disabled. Enable only after reviewing auth impact and testing login/password reset.
- Multiple permissive RLS policy warnings exist on several tables; consolidate only after comparing the effective OR semantics so no customer, seller, or admin capability is accidentally removed.

### Payment verification
- The live Razorpay function checks customer ownership, amount equality, and Razorpay HMAC signature before calling `mark_razorpay_paid_secure`. Real gateway flow, failed payments, dismissed checkout, retries, and duplicate callbacks still need controlled end-to-end tests.
- Never claim payment success based on client-only state. Keep real payment flags disabled until test completion.

## Phase 2 exit gates

- [ ] Implement inventory safety with product-row locks/atomic stock decrement or reservation, clear release rules on cancellation/failure, and concurrency regression tests.
- [ ] Add server-validated idempotency keys with a database uniqueness/transaction strategy; repeated checkout requests must return the original order and must not redeem coins twice.
- [ ] Decide and implement parent-order vs per-seller child-order representation; align seller panel queries, order items, payment/refund accounting, and RLS before enabling multi-seller checkout.
- [ ] Verify seller onboarding, pending listing submission, admin approval, and rejection paths against actual RLS.
- [ ] Review SECURITY DEFINER grants and authorization checks, prioritizing admin, finance, refund, payout, and payment RPCs.
- [ ] Test COD, payment failure, modal dismissal, payment success, order history, and duplicate submission in a non-production test environment.
- [ ] Verify mobile layout and existing customer/seller/admin feature regression.
- [ ] Confirm Cloudflare preview for the latest commit and inspect GitHub Actions test results; do not treat a Netlify preview status alone as checkout/runtime verification.
- [ ] Obtain explicit approval before deploying any Supabase function, running migrations, enabling payments, or merging to production.

## Safety boundary

This audit is a working checklist, not a security certification. Production and database were not modified by this audit.


## Additional read-only schema verification (2026-10-09)

The follow-up SQL inspection checked the live function definition, table columns, constraints, and triggers. It did not insert, update, or delete any data.

- The live `Orders` table already has a non-null `stock_reserved` boolean column, but the inspected checkout RPC's INSERT does not supply it. The existing customer cancellation routines restore stock only when `stock_reserved` is true. Since this checkout RPC neither decrements stock nor marks it reserved, the reservation/cancellation lifecycle is not connected in this code path. Check column default and every reservation-related function before drafting a migration.
- `Orders.seller_id` exists, but the checkout RPC does not populate it. `Order_items` has `product_id`, `quantity`, `unit_price`, and `total_price`, but no seller ID field.
- The RPC locks cart rows with `FOR UPDATE OF c`; it does not explicitly lock product rows in that loop. A product stock check without a matching atomic decrement/row lock is not safe against concurrent checkouts.
- The read-only function inventory also found customer cancellation routines that lock an order and conditionally add quantities back to `products.stock` or `product_variants.stock` when `stock_reserved` is true. This makes setting the reservation flag without a matching stock decrement equally unsafe (it could inflate inventory on cancellation). Implement reservation as one atomic transaction and test both reserve and release together.
- This is a confirmed checkout code-path finding, not a claim that every other database trigger or RPC lacks stock logic. Before writing the migration, inspect all stock/reservation triggers, cancellation/refund RPCs, and seller order-status functions as one transaction lifecycle.

### Next implementation slice

1. Map existing stock/reservation/cancel/refund functions and defaults, including `Orders.stock_reserved`, before touching production schema.
2. Draft a branch-only migration and rollback plan that fits the actual schema and preserves COD/payment-failure/cancellation behavior.
3. Add database-level tests for simultaneous checkout, retry/idempotency, insufficient stock, and coin balance conservation.
4. Keep live migration/function deployment and real payment tests blocked pending explicit approval.


## Latest branch status (2026-10-10)

- Latest audited branch change: checkout error sanitization and source-level regression assertions.
- The latest commit has a successful Netlify Deploy Preview status. Cloudflare preview status and GitHub Actions test results for this exact commit are not yet confirmed.
- No database migration has been authored or applied in production. The next code change must wait until the stock/variant/cancellation lifecycle and idempotency strategy are fully mapped, because a partial reservation fix could return inventory twice or oversell.


## Roadmap continuation (2026-10-10)

A branch-only implementation design note has been added: [Checkout Inventory and Idempotency Design](CHECKOUT_INVENTORY_IDEMPOTENCY_DESIGN.md). It defines the invariants and test matrix for inventory reservation, retry protection, cancellation release, and multi-seller order attribution.

This is intentionally a design/test-plan slice rather than a live schema patch: the current cancellation code can add inventory back whenever `stock_reserved` is true, so setting that flag without an atomic matching decrement risks stock inflation. The next safe implementation requires an isolated test database and review of all related functions/triggers. Production migration/deployment remains blocked pending explicit approval.


### Stock reservation patch draft (2026-10-10)

Added [CHECKOUT_STOCK_RESERVATION_PATCH_DRAFT.sql](drafts/CHECKOUT_STOCK_RESERVATION_PATCH_DRAFT.sql). It records the transaction-safe approach for stable cart/product row locks, guarded stock decrement, positive-quantity validation, and setting `stock_reserved` only in the same transaction as the decrement. It is explicitly a draft, not a complete replacement function or executable migration.

The patch is not ready to apply: the isolated database test environment is not confirmed, variant stock and idempotency remain unresolved, and the full cancellation/payment lifecycle still needs test coverage. No SQL was run from this draft.


### Follow-up implementation slice (2026-10-10)

- Added `Address is required` to the checkout error allowlist so the Edge Function can return its own safe validation message rather than replacing it with the generic database-error response.
- Added a regression assertion for that validation message.
- Added `tests/checkout-stock-draft.test.js` to check that the stock patch remains explicitly marked as a draft and records the guarded-decrement/quantity/reservation invariants. These are source/documentation checks; they are **not** database concurrency or integration tests.
- Cloudflare's latest reported preview for commit `5eb01cc` was still in progress at the time of inspection. An earlier preview for `b3141d6` succeeded, but that does not validate the newest commit.
- The GitHub workflow/status connector returned no status records for the newest commit, so CI success is not confirmed. Do not merge based on the preview build alone.


### Follow-up inventory review (2026-10-10)

- Read the full live checkout RPC definition and the customer cancellation/unpaid-order cleanup routines using read-only queries.
- Confirmed the RPC currently checks product-level stock but does not decrement it or set `Orders.stock_reserved`.
- Confirmed a second gap: `cart.variant_id` and `Order_items.variant_id` exist, but the checkout RPC ignores the selected variant and does not persist it to order items. A product-only patch would not be a complete fix.
- Added the variant-aware inventory requirements to `docs/CHECKOUT_INVENTORY_IDEMPOTENCY_DESIGN.md`.
- Corrected the draft-source test's matcher to match the commented, multiline SQL example. Focused checks of the relevant source strings pass. The full Node test runner and latest CI are still not confirmed by the GitHub status connector; do not treat these focused checks as full CI.
- No SQL writes, migration, production deployment, merge, or live payment test was performed.
