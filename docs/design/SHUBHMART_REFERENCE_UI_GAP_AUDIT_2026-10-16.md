# ShubhMart Reference UI — Existing-App Gap Audit

Status: READ-ONLY SOURCE AUDIT, branch `fix/secure-checkout-edge-function`; no app code or production data changed by this audit.
Canonical design: `docs/design/SHUBHMART_VISUAL_DESIGN_LOCK.md` and the user-provided reference image.

## Important finding

The existing repository already has a substantial marketplace application. Do not replace `index.html` with the standalone prototype. The prototype is not integrated with Supabase and uses remote sample images, demo prices/ratings, emoji stand-ins, and an in-memory cart counter. The actual app entry point is the existing `index.html` plus `assets/shubhmart-library-home.css`, `assets/shubhmart-responsive.css`, and customer modules.

## Confirmed existing frontend assets and modules

- `index.html` (~128 KB on audited branch): existing app entry point, Supabase JS and Razorpay Checkout scripts, and references to the two marketplace completion/pro-layer modules.
- `assets/shubhmart-logo.png`: existing logo asset (~781 KB); use/review this official asset rather than drawing a substitute logo in production.
- `assets/shubhmart-library-home.css` (~68 KB) and `assets/shubhmart-responsive.css` (~12 KB): extensive existing styling already targets the premium navy/pink/gold direction and responsive behavior.
- Existing modules include `customer/customer-app.js`, `customer/marketplace-completion.js`, `customer/marketplace-pro-layer.js`, `customer/order-enhancements.js`, seller and admin panels, and Supabase Edge Functions.
- Existing database migrations cover checkout validation, variants, multi-seller cart, order cancellation/returns/refunds, ShubhCoins, seller security and other marketplace functions. Their existence alone does not prove live deployment or correctness.

## Confirmed checkout integration gaps

1. There are two independent checkout entry points: `customer/customer-app.js` uses `sb.functions.invoke("create-customer-order", ...)`; `index.html` posts directly to `/functions/v1/create-customer-order`.
2. The `index.html` checkout payload does not include ShubhCoins or an idempotency key; the caller inventory reports the customer-app caller also lacks an idempotency key.
3. COD checkout deletes cart rows in a separate request after order creation. Online checkout creates a provider order after the database order; failure paths call cancellation/cleanup. These multi-request boundaries require lifecycle hardening, not cosmetic UI work.
4. Existing checkout source tests are source-pattern checks; they do not establish successful isolated PostgreSQL transaction, concurrency, stock, trigger, provider or browser testing.
5. Checkout remains a release blocker until parent+variant inventory accounting, durable reservation/restoration, idempotency, payment-attempt serialization, coin ledger safety, cancellation/late-capture handling and multi-seller attribution are solved together.

## Visual/functionality gap register — requires screenshot and interaction verification

The reference requires all of the following to be present and working in the actual app, not merely drawn:
- official logo and correct brand/tagline treatment;
- layered desktop header, live search, account, wishlist and cart counts;
- four trust benefits and horizontally usable category navigation;
- high-impact hero, shopping-character artwork, trust cards and clear CTA;
- category artwork and labels;
- three campaign tiles (fashion, beauty, electronics);
- product cards with truthful product data, badges, rating only when sourced, current/old price and discount only when verified, and functioning cart action;
- referral/app/payment/deals strip and multi-column footer;
- true mobile reflow, touch-friendly controls, and complete bottom navigation on narrow screens;
- no clipped content, hidden/white-on-white navigation, debug/error text, dead controls, broken images or blank sections.

Source inspection alone cannot certify these visual points. They need browser screenshots and interaction checks at recorded desktop and mobile viewport sizes against the canonical image. Do not mark them passed without evidence.

## Safe next implementation sequence

1. Capture/inspect the existing `index.html` and CSS/module dependencies and compare against the canonical reference; do not introduce the prototype as a replacement.
2. Produce a component-to-reference map and exact visual gap list with screenshot evidence.
3. Identify existing working handlers and preserve them. Repair missing/incorrect behavior in the smallest isolated change; no broad CSS rewrite.
4. Test search, category links, product details, cart/wishlist/account, checkout validation, order history and mobile navigation without real payment or production writes.
5. Keep the checkout security gate separate; use isolated synthetic-data tests before any live migration or payment change.
6. Do not deploy, merge, change production database/grants, activate real payments, or add paid services without separate explicit approval.

## Evidence boundary

This audit confirms repository file presence and source-level patterns on the branch. It does not claim a browser visual test, full end-to-end test, production deployment, or security certification. External images, demo values and UI-only cart state from the standalone prototype are not production data.
