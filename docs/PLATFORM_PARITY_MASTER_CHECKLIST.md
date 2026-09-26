# ShubhMart Platform Parity Master Checklist

Updated: 2026-09-26

This checklist captures the small and large marketplace capabilities commonly exposed by major Indian marketplaces, without copying proprietary UI or code.

## Customer
- [ ] Search suggestions/autocomplete
- [ ] Recent searches
- [ ] Search filters and sort
- [ ] Product variants
- [ ] Product image gallery/zoom
- [ ] Ratings and reviews
- [ ] Verified-purchase review marker
- [ ] Wishlist/favorites
- [ ] Save for later
- [ ] Recently viewed
- [ ] Compare products
- [ ] Coupons
- [ ] Deals/flash deals
- [ ] Buy-X-Get-Y offers
- [ ] Gift cards
- [ ] Wallet/credits (only after compliant financial design)
- [ ] Notifications
- [ ] Order tracking timeline
- [ ] Cancel/return/refund workflow
- [ ] Replacement workflow
- [ ] Help/support tickets
- [ ] Buyer-seller messaging with privacy controls
- [ ] Address book/default address
- [ ] Invoice download
- [ ] Reorder/buy again
- [ ] Referral/rewards
- [ ] Accessibility and multilingual UX

## Seller
- [ ] GST/PAN/bank verification workflow
- [ ] Pickup address verification
- [ ] Category/brand approval
- [ ] Product attributes/variants
- [ ] Barcode/identifier support
- [ ] Bulk listing import/export
- [ ] Listing quality score
- [ ] Inventory alerts
- [ ] Pricing tools
- [ ] Coupons/deals/promotions
- [ ] Seller storefront
- [ ] Order processing/manifest/invoice
- [ ] Shipping label generation integration
- [ ] Return/replacement management
- [ ] Settlement ledger
- [ ] Fee/commission breakdown
- [ ] Seller performance/account health
- [ ] Customer feedback/review insights
- [ ] Seller support/tickets
- [ ] Reports/analytics
- [ ] Advertising/sponsored listings architecture
- [ ] Brand protection/IP complaint workflow

## Admin / Trust
- [ ] Seller approval and KYC review
- [ ] Product moderation
- [ ] Restricted-category controls
- [ ] Counterfeit/IP complaint workflow
- [ ] Fraud/risk flags
- [ ] Dispute management
- [ ] Refund approval controls
- [ ] Audit logs
- [ ] Role-based permissions
- [ ] Platform fee configuration
- [ ] Coupon/promotion governance
- [ ] Notification templates
- [ ] CMS/banner/category management
- [ ] Support dashboard
- [ ] Data export and operational reports

## Logistics
- [ ] Delivery partner abstraction
- [ ] Shipment creation
- [ ] Label/AWB support
- [ ] Pickup scan/status
- [ ] Tracking events
- [ ] NDR workflow
- [ ] Delivery ETA
- [ ] Return pickup
- [ ] Shipping fee rules
- [ ] Pincode/serviceability
- [ ] Local delivery option

## Payments / Finance
- [ ] Secure server-side order creation
- [ ] Payment gateway integration
- [ ] Webhook verification
- [ ] Payment reconciliation
- [ ] COD controls
- [ ] Refund reconciliation
- [ ] Seller settlement ledger
- [ ] Commission/tax calculation
- [ ] Invoice/credit-note support
- [ ] Failed-payment recovery

## Growth / Intelligence
- [ ] Personalised recommendations
- [ ] Trending products
- [ ] Product discovery signals
- [ ] AI-assisted listing creation
- [ ] AI search/chat assistant
- [ ] Demand insights
- [ ] Restock suggestions
- [ ] Seller growth dashboard
- [ ] Campaign analytics

## Legal / Compliance
- [ ] Privacy Policy
- [ ] Terms of Use
- [ ] Seller Terms
- [ ] Return/Refund/Cancellation Policy
- [ ] Shipping Policy
- [ ] Grievance/contact details
- [ ] Cookie/consent controls where applicable
- [ ] Marketplace disclosures
- [ ] Product/category restrictions
- [ ] GST/tax invoice configuration
- [ ] Data retention/deletion workflow

## Production QA
- [ ] Desktop QA
- [ ] Android/mobile QA
- [ ] Browser compatibility
- [ ] Broken-link scan
- [ ] Security/RLS review
- [ ] Performance/Lighthouse review
- [ ] Backup/rollback verification
- [ ] Production smoke test

### Reference basis
Amazon publicly documents seller catalogue, inventory, pricing, orders/returns, advertising/promotions, reports, performance and B2B tools; its seller app also supports listings, inventory, fulfilment, returns, analytics and buyer messaging. citeturn0search1turn0search2

Flipkart publicly describes seller pricing recommendations, promotions, rewards, fulfilment/speed support and guidance, plus marketplace governance and seller onboarding controls. citeturn0search4turn0search12

Meesho publicly describes returns/refunds, ratings/feedback, seller quality insights and AI/ML-driven discovery/personalisation. citeturn0search36turn0search37

This checklist is a product-planning baseline, not a claim that every item is legally required or offered identically by every platform.
