# ShubhMart Stage 2 — Checkout and Payment Audit

**Roadmap:** Frozen Power Roadmap v1.0  
**Branch:** `stage2/secure-checkout-audit`  
**Status:** IN PROGRESS — source changes and CI checks pass; database migration is not applied or integration-tested.  
**Release policy:** No production merge/deploy before Stage 7. Cloudflare Workers only. No Netlify deployment or preview workflow is used by this work.

## Stage 1 evidence carried forward
- Standalone JavaScript files and all extracted inline JavaScript blocks pass Node syntax checks.
- Wrangler `deploy --dry-run` passes without credentials or a production deployment.
- Cloudflare production workflow now runs only when `github.ref == refs/heads/main`; manual dispatch on a non-main branch is skipped.
- Cloudflare deploy workflow includes inline-script syntax validation.
- `.assetsignore` excludes `supabase/` source/migrations from public static assets.
- Fixed the wholesale product-price HTML concatenation syntax error and removed fragile quote escaping from the inquiry button.
- GitHub Actions: https://github.com/sschoudharyshubhammundhar-stack/ShubhMart/actions/runs/37913780699

**Caveat:** An older PR #62 Cloudflare preview was reported failed and its account-gated build logs were unavailable to this audit. The corrected branch passes Wrangler dry-run, but that older external preview status is not claimed as fixed.

## Findings from live checkout audit
1. The deployed `create-customer-order` Edge Function used a service-role RPC client for a function that checks `auth.uid()`; that auth context is not the caller's user JWT. The source implementation now uses a user-scoped client and a dedicated owner-checked RPC.
2. The deployed `razorpay-payment` function called `attach_razorpay_order`, but the live database reports EXECUTE unavailable to `authenticated`. The source implementation now uses a dedicated server-only attach RPC.
3. The existing order-creation RPC checked stock but did not reserve/decrement it and did not preserve cart variants in order items. The proposed migration adds row locking, variant-aware prices/stock, and stock restoration on cancellation.
4. Failed/cancelled unpaid orders did not release ShubhCoins before deleting the order. The proposed migration restores coin redemption before deletion.
5. Payment verification previously relied on HMAC signature without fetching the gateway payment to confirm its order id, amount, currency, and captured state. The source implementation now checks those values and only marks the order paid after verification/capture.
6. Checkout lacked a server-side idempotency key and double-click guard. The branch adds both, plus cart mutation invalidation.
7. The security advisor reports 58 SECURITY DEFINER functions callable by authenticated users and leaked-password protection disabled. Those findings are recorded for the broader Stage 3 security audit; they are not silently marked fixed by this checkout patch.

## Source changes on this branch
- Checkout now calls `create-customer-order` and `razorpay-payment` instead of directly invoking the legacy order RPC.
- ShubhCoins redemption input is sent to the server; the database remains authoritative for balance and the 20% item-subtotal cap.
- Payment failures that cannot be verified are left pending for support reconciliation rather than automatically deleting an order that might have a captured payment.
- Added source for `create-customer-order` and `razorpay-payment` Edge Functions.
- Added `20261009_secure_checkout_order_payment_flow.sql` for review, covering idempotent order creation, stock/variant reservation, coupon/coin validation, unique gateway identifiers, server-only Razorpay attachment/paid mutation, and coin release on cancellation.
- Schema cross-check found the live `products` table has no `updated_at` column while its update trigger referenced that field; the migration corrects that trigger so stock reservation/restoration can update products.
- No live Edge Function was deployed and no production database schema/data was changed.

## Validation evidence
- Latest branch CI run: https://github.com/sschoudharyshubhammundhar-stack/ShubhMart/actions/runs/37915129213
- Passed: Deno type-check for both Edge Functions, standalone JS syntax, inline JS syntax, Wrangler dry-run packaging, validation-only workflow. A top-level PostgreSQL SQL parser check is also being added to CI.
- Not yet passed/available: execution of the SQL migration against a disposable database; PL/pgSQL body/integration validation against a database; end-to-end COD/Razorpay browser tests; real Razorpay test-mode transaction and reconciliation tests; confirmation that live Supabase functions match this branch.

## Free-tier constraint / blocker
A Supabase development branch was not created because the available estimate was **US$0.01344 per hour**. This project is being kept free-tier-first. Do not apply the migration to production as a substitute for a test database. Stage 2 remains open until SQL/integration tests can be performed safely and all fixes are reviewed.
