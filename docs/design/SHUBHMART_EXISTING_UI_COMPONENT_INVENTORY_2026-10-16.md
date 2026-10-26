# ShubhMart Existing UI Component Inventory — 2026-10-16

Branch: `fix/secure-checkout-edge-function`
Purpose: preserve the approved visual design while repairing missing behavior in the existing app.
No production actions were performed.

## Confirmed files inspected

- `index.html` — 128,218 characters; existing live marketplace entry point. It includes the marketplace shell, header/search, category navigation, hero, product grid, benefits, footer, responsive CSS references, Supabase/Razorpay integration, and customer module references.
- `assets/shubhmart-library-home.css` — 68,413 characters; extensive existing design styles including header/brand/search, nav, sidebar, hero, chips, category icons, product cards, pricing, stock, wishlist, wholesale marketplace, benefits, footer, product modal and error states. Breakpoints include 1100px, 1050px, 820px, 700px, 600px, 430px, and other targeted sizes.
- `assets/shubhmart-responsive.css` — 12,423 characters; responsive rules for the same core elements and reduced-motion preference.
- `customer/customer-app.js` — 57,922 characters; existing functions include product search/loading, cart, account/profile/address, checkout calculations, coupon, ShubhCoins, order review/placement/history, wishlist, recently viewed, compare, reviews/questions, seller store, variants/offers, notifications and support.
- `customer/marketplace-completion.js` — 15,647 characters; existing save/compare hub, marketplace coupon, product extras, reviews/Q&A, buy again, cancel, invoice, return, SEO, accessibility, network status and safety/customer checks.
- `customer/marketplace-pro-layer.js` — 17,325 characters; existing search, product variant/seller enhancement, safe reviews/returns, cancel/reorder/order timeline, recommendations and accessibility/coin UI.
- `assets/shubhmart-logo.png` exists in the repository and should be treated as the candidate official asset pending direct visual comparison.

## What this establishes — and what it does not

The repository is not a blank storefront. Many of the requested capabilities already have code paths; the remaining task is to verify their runtime behavior and visual match, then fix only evidenced defects. The standalone Tailwind HTML prototype is not a replacement for this app and must not be copied over the live entry point.

A source-level function inventory does not prove that all controls work, that the correct functions are wired to visible elements, that Supabase data loads, or that the current deployed site matches this branch. No browser screenshots or live click-through tests were available in this audit, so visual defects must not be marked as verified.

## Minimal-change audit order

1. Compare current app screenshots with the locked reference at desktop (1440×1000) and mobile (390×844), recording exact viewport and commit.
2. Verify header/search suggestions/clear/search submit; category navigation; hero CTA; product open, wishlist and cart actions; account/address; order history; mobile overflow and touch targets.
3. For each failed check, trace the actual HTML ID/class to the existing handler before changing code. Keep the CSS patch scoped to the broken selector/component.
4. Run syntax/security tests and available repository CI. Separate source-pattern tests from browser/E2E and isolated database concurrency tests.
5. Checkout remains separately gated: no production migration/deployment/payment activation until inventory reservation, idempotency, payment/cancel races and coin-ledger invariants pass isolated tests.

## Visual lock invariants

The user-approved palette, brand/logo, typography, header hierarchy, hero, category density, three campaign tiles, product card contents, benefits/footer, and responsive mobile composition are immutable without explicit user approval. Functionality can be repaired within those visual constraints.
