# ShubhMart Red-Team Security Review — 2026-10-13

## Scope and safety boundary

This is a read-only review of the current Supabase project `yauveaexbpokhytqijae` plus source review on the draft PR branch. No SQL, RLS policy, Auth setting, Edge Function, production asset, payment, or deployment was changed by this review. This document is a risk register, not a claim that the marketplace is secure or penetration-tested.

Threat-model perspectives used:
- **Black-hat attacker:** unauthenticated probing, IDOR/BOLA, role escalation, replay/race conditions, forged client prices/statuses, stock oversell, payment spoofing, secret discovery, and abuse of exposed RPCs.
- **Red-team tester:** reproduce each suspected issue with two customer accounts, two sellers, a non-admin account, a real admin account, and gateway sandbox; collect evidence without accessing unrelated user data.
- **Defender:** least privilege, server-side authorization, transactional invariants, immutable audit trail, monitoring, and rollback-safe release gates.

## Verified observations

1. **RLS is enabled on the sampled public tables.** The read-only catalog query found RLS enabled on all returned public tables. This is a useful baseline, not proof that every policy is correct. RLS is not forced for table owners, and privileged functions can bypass RLS.
2. **Supabase Security Advisor currently reports 58 SECURITY DEFINER function exposure warnings** for functions executable by the `authenticated` role, plus **one warning that leaked-password protection is disabled**. These are triage items, not 58 confirmed exploitable vulnerabilities. Some sampled admin RPCs explicitly check `private.is_admin()`; each function still needs body-level review and negative tests. Advisor remediation reference: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
3. **Sensitive RPCs must be tested against cross-account access.** Sampled customer/seller RPCs such as `set_cart_quantity`, `cancel_customer_order`, `seller_add_product_variant`, and `update_seller_product_stock` include owner/authentication checks in the inspected definitions. This does not substitute for execution tests, and the remaining RPCs are not yet exhaustively reviewed.
4. **The product/variant and seller model needs end-to-end authorization tests.** Policies for `products`, `product_variants`, `Sellers`, `Orders`, and `Order_items` exist, but business rules span multiple tables. In particular, verify seller ownership cannot be reassigned, seller-only data is not exposed through joins/views/RPCs, and an unapproved seller cannot activate a listing or alter protected fields.
5. **Checkout/payment remains a release blocker until the lifecycle is made atomic and idempotent.** Existing review notes identify missing DB-backed idempotency, stock reservation/restore gaps, ShubhCoins release gaps on some failure/cancellation paths, and a possible service-role/customer-`auth.uid()` mismatch around `attach_razorpay_order`. Payment success must be driven only by verified gateway facts, never a client claim.
6. **RLS policies are not enough for admin authorization.** Every privileged `SECURITY DEFINER` function needs: a fixed safe search path (or fully-qualified object names), explicit caller/role checks, strict input validation, least-privilege EXECUTE grants, and negative tests for non-admin callers. Never assume a function is safe merely because its name begins with `admin_`.
7. **Leaked-password protection is disabled according to the current Advisor result.** This should be enabled in Auth settings after confirming the expected user experience and testing; it has not been changed by this PR.
8. **Latest draft-branch CI at the reviewed test commit:** Secret Scan and PR Syntax Checks completed successfully. These are repository/source checks only; they are not database integration tests, adversarial RLS tests, concurrency tests, or Razorpay sandbox tests.

## High-priority red-team test matrix

| Priority | Attack scenario | Required safe result |
|---|---|---|
| P0 | Customer A reads/updates Customer B's cart, addresses, orders, payment, wallet, ledger, tickets, or saved items by changing UUIDs | Denied; no row returned/changed |
| P0 | Seller A changes Seller B's product, variant, stock, offer, payout, order, or KYC by changing IDs | Denied; no protected field changes |
| P0 | Non-admin invokes every admin RPC directly through REST, bypassing the admin UI | Denied with no side effects |
| P0 | Client forges order amount, discount, coin balance, customer ID, gateway order/payment ID, signature, or paid status | Server ignores/rejects forged values; order remains unpaid |
| P0 | Two concurrent checkouts buy the last product/variant unit | At most one succeeds; stock never goes negative |
| P0 | Repeat the same checkout request or replay gateway callback | One logical order/payment/coin debit; callback is idempotent |
| P0 | Payment fails, times out, is cancelled, or callback arrives twice/out of order | Stock reservation and coins are released exactly once; order/payment state stays consistent |
| P1 | Anonymous/unauthenticated RPC calls and malformed/oversized input | Least-privilege denial, bounded work, no stack/secret leakage |
| P1 | User-controlled metadata attempts to grant admin/seller privileges | Role derived from trusted server-side state only; user metadata never grants privileges |
| P1 | Product names, reviews, seller names, support tickets, image URLs, and search terms contain HTML/JS or hostile URLs | Correct context escaping and URL allow-listing; no script execution |
| P1 | Public schema views/functions accidentally reveal private columns or bypass RLS | Private data not exposed; views use security-invoker or are not exposed |
| P1 | Secret scan, dependency compromise, or leaked credentials | No secrets in repo/history/client bundle; rotate any confirmed exposed credentials |
| P2 | Repeated login, password reset, search, coupon, support, and checkout requests | Rate-limited or abuse-monitored; errors do not disclose account existence |

## Release gates — do not bypass

- [ ] Inventory all exposed tables, views, RPCs, triggers, grants, and SECURITY DEFINER functions; classify by customer/seller/admin/service role.
- [ ] Review all 58 Advisor findings individually; distinguish guarded admin RPCs from genuinely over-granted or unguarded functions.
- [ ] Run Supabase Security Advisor again after any approved changes.
- [ ] Add two-account authorization tests and non-admin direct-RPC tests.
- [ ] Add isolated PostgreSQL tests for checkout transactions, idempotency, stock contention, cancellation/failure, and coin-ledger consistency.
- [ ] Run Razorpay sandbox tests for amount/currency/order/payment matching and replay behavior.
- [ ] Test response headers/CSP in report-only mode first; the current page uses inline JavaScript and hosted payment scripts, so a careless CSP can break checkout.
- [ ] Enable leaked-password protection only after an approved setting change and UX validation.
- [ ] Review secret-scan results and rotate credentials only if exposure is confirmed.
- [ ] Obtain explicit approval before production SQL/migrations, Auth-setting changes, Edge Function deploy, production deploy, or PR merge.

## Important limitation

This review did not perform destructive testing, credential attacks, live payment attempts, or unauthorized access to other users' records. No system can be guaranteed unhackable. The goal is to make compromise harder, reduce blast radius, and detect/contain failures.
