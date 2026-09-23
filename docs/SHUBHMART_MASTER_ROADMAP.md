# ShubhMart Master A-to-Z Roadmap — Locked Marketplace Parity + Plus

This is the **locked product roadmap and feature contract** for ShubhMart. The goal is not to copy any one marketplace; it is to cover the major capabilities users expect from large marketplaces such as Amazon, Flipkart, Meesho and Myntra, while adding ShubhMart-specific capabilities. New work must fit this roadmap and must not remove working features.

## Product vision

ShubhMart is a multi-vendor marketplace combining B2C retail, fashion, multi-seller selling, B2B wholesale, bulk buying, multi-speed delivery, AI-assisted listing and shopping, rewards, services and a future compliant credit/finance layer.

## Benchmark scope

The benchmark checklist covers common marketplace capabilities documented by major platforms: seller listing/catalog management, inventory, order and shipment management, fulfilment choices, returns/refunds, payments and settlements, reviews, analytics, customer support, promotions, advertising, AI assistance, and seller/business insights. For example, Flipkart documents seller fulfilment, shipping, returns and settlements; Amazon documents Seller Central tools, AI assistance, review insights, returns and shopping assistance; Meesho documents supplier listing/order/inventory/payment/analytics/support workflows. These are reference capabilities, not copied branding or code.

## Locked delivery sequence

### 1. Foundation + secure checkout
- Modular architecture
- Customer marketplace shell
- Cart, address and checkout
- Payment integration boundary
- Order creation and idempotency
- Security/RLS baseline

### 2. Security + QA + customer runtime
- Auth/session hardening
- RLS audit
- Error handling
- Mobile-first QA
- Checkout/order runtime tests
- Regression protection

### 3. Seller Center / Multi-Seller
- Seller registration/KYC workflow
- Seller profile/shop
- Product creation/edit/resubmit
- Listing approval and rejection reasons
- Variants/SKU
- Images/video
- Inventory and low-stock alerts
- Bulk inventory/price upload
- Seller order management
- Seller fulfilment/self-ship options
- Seller performance/health
- Seller analytics
- Payout/settlement ledger
- Fees/commission visibility
- Coupons/offers
- Customer review insights
- Seller support/tickets
- AI Listing Assistant

### 4. Wholesale / Bulk Buyer
- Wholesale catalog
- MOQ and tier pricing
- Bulk inquiry/quote
- Buyer/seller negotiation workflow
- Bulk cart
- Multi-seller consolidated checkout
- B2B invoices
- RFQ/RFP workflow
- Repeat bulk orders
- Business profile and tax details

### 5. Admin Center
- Admin authentication and role protection
- Seller/KYC approval/suspension
- Product/category/catalog moderation
- Order operations
- Returns/refunds/disputes
- Wholesale approval
- Commission/fee rules
- Coupon/promotion controls
- Payout controls
- User/customer support
- Delivery operations
- Content/banner/homepage controls
- Fraud/risk flags
- Audit logs
- Analytics/GMV/order/return dashboards
- Feature flags and configuration

### 6. Delivery & Shipping
- Delivery partner onboarding
- Delivery assignment
- Pickup/packing/dispatch
- Shipment/tracking lifecycle
- OTP/POD
- RTO and reverse pickup
- Delivery partner dashboard
- Customer live status
- Seller shipment status
- Admin dispatch console
- SLA/late-delivery flags
- Multiple fulfilment modes

### 7. AI Listing + AI Shopping
- AI title/description generation
- Attribute extraction
- Category suggestion
- Image quality/background guidance
- SEO/search keyword suggestions
- Listing quality score
- AI price/competition suggestions
- AI inventory/reorder suggestions
- AI review/return-reason summarisation
- Customer AI shopping assistant
- Product comparison assistant
- Natural-language product search
- Personalised recommendations
- AI fraud/anomaly signals
- AI support assistant with human escalation

### 8. ShubhCoins / Loyalty
- Earn/redeem rules
- Referral rewards
- Streaks/badges
- Cashback/coins ledger
- Tiered loyalty
- Seller-funded rewards
- Expiry rules
- Fraud controls

### 9. Services
- Product/service marketplace
- Service provider onboarding
- Booking/request flow
- Quote flow
- Service status
- Reviews
- Disputes
- Provider payouts

### 10. ShubhCredit
- Partner-based compliant finance only
- Eligibility/request flow
- Consent and disclosures
- Partner handoff
- Application status
- Repayment/status visibility
- No lending decision logic in the browser

## Cross-panel feature contract — nothing essential should be skipped

### Customer Panel
- Sign up/login/logout/password reset
- Mobile/Google login when production auth is enabled
- Profile and saved addresses
- Search, autocomplete, filters, sort and categories
- Wishlist
- Recently viewed
- Compare products
- Product variants
- Product videos/images
- Ratings/reviews/photos/videos
- Questions & answers
- Seller/store page
- Offers/coupons
- Cart and save-for-later
- Multi-seller cart
- Checkout/payment
- Order history/invoice
- Cancel/return/exchange/refund
- Delivery tracking and OTP/POD
- Buy Again
- Notifications
- Support/tickets
- Referral and ShubhCoins
- Personalised recommendations
- AI shopping assistant
- Wholesale/B2B mode
- Service bookings
- Account/privacy/security controls

### Seller Panel
- Registration/KYC/profile
- Shop and brand profile
- Product/listing CRUD
- Variants/SKU/catalog
- Media management
- AI listing
- Listing quality/QC
- Inventory
- Bulk inventory/price updates
- Low-stock/reorder alerts
- Orders/shipments
- Returns/RTO/refunds
- Shipping labels/POD
- Coupons/offers
- Promotions/ads
- Reviews/feedback
- Customer questions
- Analytics and performance
- Settlement/payout ledger
- Fee/commission calculator
- Business invoices/tax reports
- Wholesale pricing/RFQ
- Seller support
- Account health/compliance
- Fraud/risk alerts
- Notification center

### Wholesale Buyer Panel
- Business registration/profile
- GST/tax details
- Wholesale discovery
- MOQ/tier pricing
- RFQ
- Quote negotiation
- Bulk cart
- Multi-seller bulk checkout
- Purchase orders
- Business invoices
- Repeat orders
- Order/shipment tracking
- Returns/disputes
- Buyer analytics
- Saved suppliers/products
- Credit/partner-finance entry point
- Support

### Admin Panel
- Role-based access
- Dashboard/KPIs
- Users/customers
- Sellers/KYC
- Products/catalog/categories
- Orders
- Payments/refunds
- Returns/disputes
- Delivery partners/shipments
- Wholesale/RFQ
- Coupons/offers
- Ads/promotions
- Reviews/moderation
- Support tickets
- ShubhCoins/rewards
- Services
- Finance/credit partner controls
- Fraud/risk
- Reports/export
- Audit logs
- Notification templates
- Homepage/content/banner controls
- Feature flags
- System health/QA

### Delivery Panel
- Partner login/onboarding
- Availability/online status
- Assigned pickups
- Pickup OTP
- Package verification
- Route/status updates
- Delivery OTP
- Proof of delivery
- Failed delivery/RTO
- Reverse pickup
- Earnings/settlement view
- Support/escalation
- Performance/SLA

## ShubhMart Plus — extra capabilities beyond baseline parity

1. **AI Listing Studio** — one photo/text prompt can prepare a structured draft listing.
2. **AI Catalog Doctor** — detects missing attributes, weak titles, duplicate listings and image issues.
3. **AI Pricing Copilot** — suggests price bands using internal marketplace signals; seller remains in control.
4. **AI Return Detective** — groups return reasons and identifies recurring listing/quality problems.
5. **AI Seller Coach** — converts seller analytics into actionable tasks.
6. **AI Buyer Concierge** — natural-language shopping, comparison and shortlist building.
7. **Smart Bundle Builder** — creates compatible product bundles and cross-sell suggestions.
8. **ShubhDeal Engine** — rules-based deal/coupon engine with seller/admin controls.
9. **ShubhCoins Wallet** — unified rewards ledger across shopping, referrals and eligible services.
10. **Trust Score** — transparent seller/listing quality signals based on documented marketplace metrics.
11. **Multi-seller smart checkout** — one customer checkout while internally splitting seller/order/shipment records safely.
12. **Wholesale negotiation room** — RFQ, counter-offer, quote expiry and acceptance history.
13. **Returnless/partial-resolution framework** — configurable by policy and admin approval.
14. **Smart RTO prevention** — risk flags, address/phone checks and delivery reminders without exposing sensitive data unnecessarily.
15. **Seller health center** — SLA, cancellation, return, quality and customer feedback trends.
16. **Buyer protection center** — order issue, evidence upload, dispute timeline and resolution status.
17. **Explainable recommendations** — show why a product is recommended rather than using a black-box label only.
18. **Privacy center** — sessions, device visibility, data/export/delete requests and consent records.
19. **Marketplace experimentation** — feature flags and controlled UI experiments without changing core order logic.
20. **Unified notification center** — in-app, email/OTP/push-ready architecture with templates and preferences.
21. **Search intelligence** — typo tolerance, synonyms, Hindi/English query support and intent-aware filters.
22. **Catalog deduplication** — detect probable duplicate products/SKUs before publication.
23. **Seller import/export** — CSV-based catalog, price and inventory tools with validation and error reports.
24. **Operational command center** — admin view of stuck orders, SLA breaches, payment exceptions and delivery exceptions.
25. **Audit-first architecture** — important admin, seller, payout, refund and status changes are traceable.

## Non-negotiable engineering/security rules

- Never expose Supabase service-role/secret keys in browser code.
- Every sensitive table gets explicit RLS.
- Role changes cannot be self-assigned by normal users.
- Seller access is always scoped to the authenticated seller.
- Admin actions are role-gated and auditable.
- Money operations use server-side/Edge Function boundaries and idempotency.
- Order, payment, refund and payout state transitions are validated.
- PII is minimised in client responses.
- Use indexes for high-volume lookup paths.
- Prefer additive migrations; do not destroy working data/schema casually.
- Every feature gets a separate branch/commit/PR.
- Test before merging to main.
- Existing customer checkout must not be broken by seller/admin/delivery work.
- Demo mode and real-money production mode remain clearly separated.
- AI outputs are drafts/recommendations until an authorised user confirms them.

## Definition of done for every major module

A module is not complete merely because its screen exists. It must have:
1. UI
2. Database/schema
3. RLS/security
4. Valid state transitions
5. Error handling
6. Mobile usability
7. Empty/loading/error states
8. Auditability where needed
9. Regression test coverage appropriate to the module
10. Integration with the other panels
11. Documentation
12. Safe Git PR and merge

## Release gates

Before production launch, verify:
- Customer purchase from product -> cart -> checkout -> payment -> order -> delivery -> return/refund.
- Seller listing -> approval -> order -> fulfilment -> settlement.
- Wholesale inquiry -> quote -> bulk order -> fulfilment.
- Admin moderation -> operations -> audit.
- Delivery assignment -> pickup -> tracking -> delivery/RTO -> reverse pickup.
- AI suggestions never bypass approval/security.
- RLS prevents cross-user/cross-seller data access.
- Refund/return/cancellation paths are consistent.
- Notifications and support escalation work.
- Analytics reconcile with transactional data.

## Current execution position

The repository already contains the customer, seller, wholesale and admin foundations. **Delivery & Shipping is the next execution stage.** After delivery, continue through AI Listing/Shopping, ShubhCoins, Services, ShubhCredit, then final security/QA/production gates.

This document is the master scope. Feature ideas can be added as sub-features, but the locked execution order should remain stable.
