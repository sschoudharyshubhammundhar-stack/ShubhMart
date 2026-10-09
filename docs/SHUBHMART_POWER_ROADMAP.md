# ShubhMart Power Roadmap — FROZEN v1.0

**Status:** FROZEN — follow this plan in order.  
**Frozen on:** 2026-10-09  
**Project:** ShubhMart  
**Hosting:** Cloudflare Workers only. Do not use Netlify.  
**Budget:** Free-tier-first. No paid upgrades or paid services without explicit approval.  
**Release rule:** Production launch is Stage 7 only, after every prior gate passes. Do not deploy early.

## Change-control lock
1. This is the single source of truth for project sequencing. Do not reorder, replace, or casually rewrite stages.
2. Keep this version unchanged during implementation. Record progress in PR descriptions/checklists or a separate progress log.
3. A roadmap change is allowed only if (a) a critical security/legal blocker requires it, or (b) the user explicitly asks to change the plan. Explain the reason before changing it.
4. A stage is complete only when its exit gate has evidence. Never mark a test as passed if it was not run.
5. Preserve existing features and the approved “ShubhMart Neon Marketplace Showcase” visual master. Do not simplify the site to pass a test.
6. Never publish demo/pending products, modify real customer/order data, expose secrets, or perform destructive database actions without authorization.
7. Keep work on branches until Stage 7. No production merge/deploy before then. Stage 7 launch requires all gates passed and a final release review.
8. Hosting is Cloudflare Workers only. Existing third-party repository integrations must not be used as a hosting/release path; do not use Netlify tools, previews, deploys, or links.

## Stage 1 — Protect the project and make builds reliable
- [ ] Record the current production/main checkpoint and rollback path.
- [ ] Confirm Cloudflare Worker and GitHub workflow triggers; ensure pull-request branches cannot deploy to production.
- [ ] Inspect the actual failed build log and fix the evidenced root cause.
- [ ] Check Wrangler config, asset exclusions, required secrets (never print values), and branch/release settings.
- [ ] Run JavaScript syntax checks for standalone scripts and inline scripts in `index.html`.
- [ ] Use only Cloudflare for hosting/release validation; identify any repository integration that conflicts with the no-Netlify rule.
**Exit gate:** Reproducible branch build/syntax validation passes, deployment triggers are understood, and production is unchanged.

## Stage 2 — Checkout, orders and payment security
- [ ] Review frontend checkout and active Supabase Edge Functions together.
- [ ] Verify server-side authentication and ownership for cart, delivery address, order and seller data.
- [ ] Verify price, stock, delivery fees, coupon and ShubhCoins discount are computed/validated server-side.
- [ ] Verify COD order creation is idempotent and cart clears only after success.
- [ ] Verify Razorpay amount comes from the server-created order, signatures are checked server-side, and failures/cancellations are handled safely.
- [ ] Check duplicate clicks, expired sessions, duplicate orders, unpaid orders, order history, invoice, cancellation, return and replacement paths.
- [ ] Run tests or document exactly which tests remain blocked; never claim unrun tests passed.
**Exit gate:** Order/payment flows pass available automated and manual tests; no client-trusted totals or authorization gaps remain.

## Stage 3 — Database, access control and product visibility
- [ ] Audit RLS, grants and policies for customer, seller, order and admin tables.
- [ ] Review SECURITY DEFINER functions and verify privileged actions enforce server-side role checks.
- [ ] Confirm seller ownership boundaries and protect customer personal data.
- [ ] Explain product visibility conditions (live flag, approval, compliance); do not publish pending/demo products without approval.
- [ ] Confirm schema and deployed Edge Functions are consistent with the repository.
- [ ] Check backups and rollback options before any schema/data change; never expose service-role keys.
**Exit gate:** Least-privilege access is verified and data changes are safely reversible.

## Stage 4 — Locked premium design and responsive UI
- [ ] Use the user's approved “ShubhMart Neon Marketplace Showcase” as the locked visual master.
- [ ] Restore premium dark-blue header, logo/tagline “ShubhMart — Har Zaroorat, Ek Jagah”, search, account/wishlist/cart and navigation.
- [ ] Restore premium hero artwork, attractive campaign visual and trust cards without malformed anatomy.
- [ ] Restore circular category icons, three promo tiles, six-product row, service strip and premium dark footer.
- [ ] Make phone layouts intentionally responsive; check small/large mobile widths and desktop; no squeezed desktop layout or horizontal overflow.
- [ ] Preserve existing feature IDs, event handlers, routes and data integrations while styling.
- [ ] Compare screenshots against the reference on desktop and mobile.
**Exit gate:** Visual review passes on phone and desktop and existing features still work.

## Stage 5 — Customer features end-to-end
- [ ] Login/session recovery, profile and address book.
- [ ] Search, categories, product details, filters/sorting and variants.
- [ ] Cart and wishlist.
- [ ] Coupons, ShubhCoins, totals and checkout.
- [ ] Orders, invoices, buy again, cancellation, returns/replacements and notifications.
- [ ] WhatsApp order flow with a clear summary and no private-data leakage.
- [ ] Empty, loading, invalid-input, slow-network and error states.
**Exit gate:** Each customer journey is tested end-to-end without feature regressions.

## Stage 6 — Seller/admin, policies and launch readiness
- [ ] Seller onboarding, approval/KYC/GST status, product submission, price/stock and compliance review.
- [ ] Admin approval/moderation, order management, seller-specific access and audit trail.
- [ ] Verify admin-only actions against non-admin accounts.
- [ ] Ensure Terms, Privacy, Shipping/Delivery, Cancellation, Return/Refund, Contact and seller policies are accessible and accurate.
- [ ] Test Android Chrome and desktop browser, responsive widths, accessibility basics, image loading, console/network errors and offline/slow conditions.
- [ ] Verify free-tier limits and production rollback steps; no paid upgrade without approval.
- [ ] Complete a security review and record unresolved risks honestly.
**Exit gate:** All critical/high issues fixed; no launch-blocking legal, security, checkout, or data-integrity defects remain.

## Stage 7 — Controlled production launch
- [ ] Produce final change summary, test evidence, known limitations and rollback plan.
- [ ] Confirm Stages 1–6 exit gates with evidence.
- [ ] Review the final production diff and confirm no secrets, debug settings or demo data were exposed.
- [ ] Launch only on the Cloudflare Worker after the final release gate; never deploy from an unvalidated PR.
- [ ] Smoke-test the live URL: home/mobile, login, product visibility, cart, COD/order path, payment verification if configured, order history and seller/admin access.
- [ ] Monitor errors and roll back immediately if a critical defect appears.
**Exit gate:** Live Cloudflare site passes smoke tests, rollback is available, and the launch is documented.

## Fixed working rules
- One stage at a time; root-cause fixes only.
- No unapproved scope changes and no roadmap rewrites.
- No feature removals as shortcuts.
- No production data edits, secret exposure, paid upgrades, merge, or production deploy outside the stated release gate.
- If evidence or logs are unavailable, record the blocker and do not guess.
