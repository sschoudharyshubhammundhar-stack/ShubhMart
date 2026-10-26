# ShubhMart Visual Design Lock

Status: LOCKED — visual changes require explicit user approval.

Reference authority:
- The user-provided “ShubhMart Neon Marketplace Showcase” image is the canonical visual reference.
- Preserve the same desktop marketplace composition and the right-side iPhone-style mobile showcase. Do not redesign, simplify, substitute a generic storefront, or change the visual direction.
- The standalone generated HTML file is a prototype artifact, not proof that the existing ShubhMart application already matches the reference. Integrate into the existing app only after auditing its actual entry points and components.

## Immutable design contract

1. Palette: luxury indigo/navy (#0A0E1A to #0D162D), neon orange (#FF6B00), gold (#FFC700), magenta/pink CTA (#FF1768).
2. Typography: Poppins or Montserrat; bold display headings, semibold product titles, medium tags.
3. Brand: glossy shopping-bag mark with metallic 3D “S”, golden/orange orbital details, “ShubhMart” wordmark, and centered “Har Zaroorat, Ek Jagah” tagline.
4. Header: layered brand/search/account/wishlist/cart area, notification counts, four trust-benefit items, and horizontal category navigation.
5. Hero: premium promotional composition, illustrated shopping character, layered lighting/shadows, trust cards, and clear Shop Now CTA.
6. Categories: circular/rounded category art and labels, matching the reference's density and alignment.
7. Promotions: three distinct fashion, beauty, and electronics promotional tiles.
8. Product grid: badge, product image, title/category, rating, current price, struck-through old price, discount, and rounded magenta Add to Cart control.
9. Utility strip and footer: referral/app/payment/deals tiles and a multi-column dark footer.
10. Mobile presentation: the reference-style phone frame, mobile header/search, promotional banner, trust strip, categories, deals, bottom navigation. The actual site must also responsively reflow for real mobile screens; do not force the desktop page into a phone viewport.
11. Finish quality: preserve spacing, corner radii, gradient depth, shadows, typography hierarchy, visual density, and responsive behavior. No visible debug/error text, blank sections, hidden navigation labels, or placeholder content in the shipped UI.

## Change control

- This lock freezes the visual direction and layout hierarchy, not the implementation code or functional requirements.
- Missing functionality must be added without changing the approved appearance unless the user explicitly approves a visual revision.
- Before changing UI, inspect the current repository and reuse working components. Avoid a rebuild from scratch.
- Treat the user-provided image as the comparison target. Verify desktop and mobile screenshots at defined viewport sizes before calling the design complete.
- External image URLs, emoji, demo products, fake ratings/prices, and simulated cart state are prototype-only. Production must use approved brand assets and real application data; never present demo values as verified catalog data.
- No production deployment, database mutation, payment activation, merge, or paid-service change is authorized by this document.
- Never claim 100% pixel-perfect or security-certified without reproducible visual comparison and relevant tests.

## Acceptance gate before proceeding

- [ ] Existing app entry point and shared components identified; no parallel replacement storefront.
- [ ] Reference layout mapped to actual components and data sources.
- [ ] Desktop and narrow-mobile layouts inspected for clipping, missing navigation, overflow, and broken sections.
- [ ] Real product/catalog state replaces demo-only content where connected.
- [ ] Search, cart, account, wishlist, category navigation, and CTAs have truthful behavior; no dead controls.
- [ ] Screenshot comparison completed against the canonical reference at recorded viewport sizes.
- [ ] No production deployment or database/payment changes without separate explicit approval.

Next work must follow the existing locked roadmap and audit the missing functionality while keeping this design contract unchanged.
