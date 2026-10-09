# ShubhMart Power Roadmap

**Project:** ShubhMart  
**Hosting policy:** Cloudflare Workers only. Do not use Netlify.  
**Budget policy:** Free-tier-first; do not enable paid services or upgrade plans without explicit approval.  
**Release policy:** Never deploy to production or merge a risky change without explicit approval. Keep changes in a branch until validated.

## Goal
Restore and finish the existing ShubhMart marketplace without deleting working features or replacing the locked premium desktop/mobile design with a simplified recreation.

## Phase 0 — Protect the project
- [ ] Keep `main` and the current live Worker unchanged until a fix is tested.
- [ ] Record the current main commit and create a code checkpoint before each risky edit.
- [ ] Confirm deployment path is Cloudflare Workers and prevent accidental production deployment from pull-request branches.
- [ ] Keep secrets out of source files, logs, screenshots and commits.
- [ ] Treat database backup separately from GitHub source backup.

**Exit gate:** A known-good rollback point exists and deployment triggers are understood.

## Phase 1 — Build and release pipeline
- [ ] Inspect the Cloudflare failed build log for PR #62 and fix the actual error, not guess.
- [ ] Check Wrangler config, asset exclusions, workflow triggers, required Cloudflare secrets and branch rules.
- [ ] Run JavaScript syntax checks for standalone scripts and extract/check inline scripts from `index.html`.
- [ ] Verify PRs do not deploy to the production Worker.
- [ ] Confirm the intended Cloudflare preview flow; do not use Netlify previews.

**Exit gate:** Branch validation succeeds and production remains unchanged.

## Phase 2 — Checkout, orders and payment security
- [ ] Review the frontend checkout flow and active Supabase Edge Functions together.
- [ ] Verify authenticated user ownership of delivery address and cart items on the server.
- [ ] Verify product price, stock, delivery fees, coupon and any ShubhCoins discount are calculated server-side.
- [ ] Confirm COD creates one order and clears cart only after successful order creation.
- [ ] Confirm Razorpay amount is taken from the server-created order, never trusted from the browser.
- [ ] Confirm payment signature verification, cancellation/failure handling and duplicate-click protection.
- [ ] Check order history, invoices, cancel, return and replacement paths.
- [ ] Test errors and expired sessions without leaving duplicate or unpaid orphan orders.

**Exit gate:** No payment or order changes reach production until all available tests pass.

## Phase 3 — Database, access control and product visibility
- [ ] Audit RLS policies and grants for customer, seller and admin tables.
- [ ] Review SECURITY DEFINER functions and ensure admin-only actions verify server-side authorization.
- [ ] Confirm product visibility rules and why products may be hidden (e.g. `is_live`, approval, compliance status).
- [ ] Do not publish pending/demo products or alter customer/order data without approval.
- [ ] Verify seller ownership boundaries for products, orders and profile data.

**Exit gate:** Access is least-privilege and product publication rules are clear.

## Phase 4 — Locked premium design and responsive UI
- [ ] Use the user's approved “ShubhMart Neon Marketplace Showcase” as the visual master.
- [ ] Restore premium dark-blue header, logo and tagline, search, account/wishlist/cart and navigation.
- [ ] Build the premium hero artwork and trust cards; avoid malformed AI imagery and extra limbs.
- [ ] Restore circular category icons, three promotional tiles, six-product row, service strip and premium footer.
- [ ] Make mobile layout intentionally responsive; no squeezed desktop header or horizontal overflow.
- [ ] Preserve all current functional IDs, event handlers, sections and accessible controls while styling.
- [ ] Compare desktop and phone screenshots against the reference before approval.

**Exit gate:** Visual comparison passes on both phone and desktop; features remain functional.

## Phase 5 — Customer features
- [ ] Login/session recovery and profile.
- [ ] Search, categories, product detail, filters/sorting and product variants.
- [ ] Cart, wishlist, address book and checkout.
- [ ] Coupons, ShubhCoins and order totals.
- [ ] Order history, invoice, buy again, cancellation, returns/replacements and notifications.
- [ ] WhatsApp order path, with clear order summary and no exposure of private data.

**Exit gate:** Each customer journey is checked end-to-end.

## Phase 6 — Seller and admin marketplace
- [ ] Seller onboarding and approval/KYC/GST status.
- [ ] Seller product submission, price/stock/wholesale settings and compliance review.
- [ ] Admin product approval/live toggle and moderation.
- [ ] Order management, seller-specific access, customer support and audit trail.
- [ ] Ensure only authorized admins can approve sellers/products or change sensitive statuses.

**Exit gate:** Seller and admin actions are role-protected and tested with non-admin accounts.

## Phase 7 — Legal, reliability and launch checklist
- [ ] Confirm Terms, Privacy, Shipping/Delivery, Cancellation, Return/Refund, Contact and seller policies are accessible.
- [ ] Confirm contact details and business representations are accurate; do not invent legal claims.
- [ ] Test current Android Chrome, a desktop browser, small and large phone widths.
- [ ] Test slow/offline network, empty states, invalid forms and server errors.
- [ ] Check accessibility basics, image sizes, loading states and console errors.
- [ ] Verify free-tier limits and avoid paid upgrades without permission.

## Phase 8 — Controlled production release
- [ ] Summarize code changes and test results.
- [ ] Ask for approval before merging or deploying production.
- [ ] Deploy only to Cloudflare Worker after approval.
- [ ] Smoke-test the live URL and keep rollback instructions ready.

## Working rules
1. One phase at a time; fix root causes instead of layering patches.
2. Do not remove features to make a test pass.
3. Do not mark seed/demo products live without permission.
4. Do not commit secrets or change production database records without permission.
5. If evidence/logs are unavailable, state the limitation and request the exact log or screenshot instead of guessing.
