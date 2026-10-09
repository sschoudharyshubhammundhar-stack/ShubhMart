# ShubhMart Security + QA Audit (Roadmap Phase 2)

Updated: 2026-10-09

Scope: read-only inspection of the connected Supabase project's current policies, security/performance advisor output, active Edge Function source, and the feature branch. No production deploy, SQL write, migration execution, or payment transaction was performed.

## Verified improvements in this branch

- `supabase/functions/create-customer-order/index.ts` now verifies the bearer token using the server auth client and forwards that same customer JWT to `create_order_from_cart_with_coins`, so the database function's `auth.uid() = p_customer_id` guard can evaluate in the customer's context.
- `tests/create-customer-order-source.test.js` adds regression assertions for token verification and customer-JWT propagation.
- GitHub Actions PR syntax and checkout regression checks passed for commit `158d3b017ee9bfb6bb0cb7455a761c6e5b5cc985`.
- These source changes are not proof that the live Supabase Edge Function was updated. Live function changes require a separate approved deployment.

## Findings requiring follow-up

### High priority: checkout inventory and duplicate-order behavior
- The live `create_order_from_cart_with_coins` function checks current stock but the inspected function body does not decrement/reserve inventory and does not accept an idempotency key. Concurrent checkouts or repeated submissions need runtime/concurrency tests and a reviewed database-side fix.
- The inspected order creation body creates one `Orders` row and inserts cart rows into `Order_items`; seller-specific order splitting/assignment was not evident in that function. Verify this against the intended multi-seller contract before enabling real marketplace orders.
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

- [ ] Resolve inventory reservation and idempotency design with safe migration + regression tests.
- [ ] Verify multi-seller order representation and seller order isolation.
- [ ] Verify seller onboarding, pending listing submission, admin approval, and rejection paths against actual RLS.
- [ ] Review SECURITY DEFINER grants and authorization checks, prioritizing admin, finance, refund, payout, and payment RPCs.
- [ ] Test COD, payment failure, modal dismissal, payment success, order history, and duplicate submission in a non-production test environment.
- [ ] Verify mobile layout and existing customer/seller/admin feature regression.
- [ ] Obtain explicit approval before deploying any Supabase function, running migrations, enabling payments, or merging to production.

## Safety boundary

This audit is a working checklist, not a security certification. Production and database were not modified by this audit.
