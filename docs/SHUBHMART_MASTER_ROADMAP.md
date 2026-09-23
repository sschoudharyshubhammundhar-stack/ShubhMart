# ShubhMart Master A-to-Z Roadmap

This is the fixed product roadmap. New features must fit this roadmap instead of changing direction.

## Product vision
ShubhMart is a multi-vendor marketplace combining B2C retail, fashion, multi-seller selling, B2B wholesale, bulk buying, multi-speed delivery, AI-assisted listing, rewards, and a future compliant credit/finance integration.

## Phases
1. Foundation and modular architecture
2. Brand and UI system
3. Customer marketplace
4. Authentication and account
5. Product and catalog system
6. Search, categories, filters and wishlist
7. Cart and checkout
8. Orders, returns and refunds
9. Seller Center
10. Admin Center
11. B2B and Wholesale Center
12. Bulk cart and consolidated checkout
13. Delivery and shipping layer
14. Reviews, ratings, coupons and offers
15. AI listing and shopping assistance
16. ShubhCoins and rewards
17. Payment integrations
18. Real email, OTP and Google login
19. Future ShubhCredit through compliant lending or finance partners
20. Security, QA, analytics and production launch

## Fixed rules
- Customer, seller, wholesale and admin modules stay separate.
- Prefer small reusable JS and CSS modules over one giant file.
- Keep public configuration separate from feature code.
- Never put secret or service-role keys in browser code.
- Version database changes with migrations.
- Give every feature a separate Git commit.
- Test before merging to main.
- Do not remove working features while adding a new feature.
- Real-money services stay disabled until the demo flow is tested.
- Uploaded ShubhMart screenshots are the visual master reference.

## Current priority
Build and test the free/demo architecture first. Real OTP, SMTP, production payment and credit services come later.
