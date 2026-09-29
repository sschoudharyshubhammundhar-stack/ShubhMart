# ShubhMart Final Internal Feature Integration Status

Updated: 2026-09-29

## Integrated customer features
- Secure server-side order creation through the protected `create-customer-order` Edge Function.
- Legacy browser-accessible `create_order_from_cart` execution revoked from `authenticated`/`anon`; service-role only.
- Data-driven active coupon validation.
- COD / Razorpay payment flow handoff.
- Delivery method selection.
- Wishlist, save for later, recently viewed, recent searches and product compare (max 4).
- Product variants, offers, ratings/reviews with delivered-product verification and Q&A.
- Order invoice, Buy Again / reorder and order tracking timeline.
- Customer cancellation, return, exchange/replacement and Buyer Protection workflows.
- Notifications, support tickets and address book / checkout address.
- ShubhCoins wallet visibility, accessibility quick control and recommendations.
- Public seller storefront filtering.

## Integrated seller features
- Seller onboarding/KYC, product listing/editing and product variants.
- Wholesale pricing and seller offers.
- Returns, seller finance/payout views, analytics, support and notifications.
- Wholesale workflow.
- CSV bulk listing import (up to 50 rows per batch) and product CSV export.
- Listing quality score, seller performance snapshot and public seller storefront shortcut.

## Integrated admin / operations
- Seller approval/KYC and product moderation.
- Order processing and wholesale pricing/order controls.
- Delivery partner approval, shipment creation/assignment.
- Returns/refunds, Buyer Protection and seller payouts.
- Risk flags, feature flags and audit logs.
- Notifications, support tickets and user/operational reporting.

## Intentionally external / credential-dependent
- Real SMS/OTP provider.
- Real transactional email provider.
- WhatsApp provider.
- Live payment-gateway production credentials/KYC.
- Courier/carrier APIs and live AWB labels.
- External AI model/API.
- External KYC/GST verification.

These remain connector-ready and are not faked. They require the respective production accounts, credentials, verification and/or paid external services.

## Production security status
- Customer order creation is routed through the protected Edge Function with JWT verification.
- Browser-side direct INSERT access to Orders, Order_items and payments remains blocked by RLS.
- Legacy `create_order_from_cart` RPC is no longer executable by `authenticated` or `anon`.
- Admin order/product functions remain protected by their server-side admin checks.
- Final remaining project-level security advisories and browser smoke tests must be reviewed before claiming production certification.

## Release gate
GitHub Actions syntax validation + Cloudflare deployment must succeed before calling a code deployment complete. Browser smoke testing on Android/desktop remains the final human-runtime gate. External credential-dependent integrations are not represented as live until real credentials and provider verification are supplied.
