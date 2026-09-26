# ShubhMart Seller Master Blueprint — LOCKED

Version: 1.0
Date: 2026-09-26

## Core decision
Seller Panel and Wholesale Panel remain separate experiences. A seller can still enable product-level wholesale pricing from Seller Panel. AI can recommend wholesale opportunity, but the seller approves MOQ/price before activation.

## Seller OS
Dashboard; Catalogue; One-Photo AI Listing Studio; Inventory; Pricing; Variants; SKU/Barcode; Orders; Returns; Shipping/Fulfilment; Finance; Payouts; Invoices/Tax; Marketing/Ads; Analytics/Reports; Reviews/Q&A; Account Health; KYC/Business/GST/PAN/Udyam; Documents; Support/Grievance; Notifications; Team/Permissions; Settings.

## Professional listing
Title; category; sub-category; product type; seller SKU; brand; GTIN/barcode where applicable; HSN where applicable; MRP; selling price; discount; tax; stock; cost price; manufacturer/packer/importer where applicable; country of origin; package contents; product/package dimensions; weight; warranty; return eligibility; licence/certificate/compliance fields; highlights; description; specifications; dynamic category attributes; search keywords; SEO title/description; variants; images; video; 360 media.

## AI listing
Seller provides one genuine product photo plus basic factual information. AI prepares listing content and a media-generation workflow. It must not invent brand, certification, licence, quantity, colour, dimensions, warranty, compliance or other factual claims. Seller review, compliance review and admin approval are required before LIVE.

## Wholesale
Dedicated Wholesale Hub with business profile, MOQ, minimum order value, quantity tiers, bulk pricing, buyer verification, enquiries/quotes, wholesale orders, bulk shipping terms, return/payment terms and tax invoice handling. Seller Panel also exposes product-level wholesale price/MOQ.

## Lifecycle
Draft → AI Processing → Seller Review → Compliance Review → Admin Approval → LIVE → Orders → Returns → Commission → Payout → Invoice → Grievance.

## Security
Master seller identity is tied to the authenticated user and verified seller record. Product LIVE state remains approval-controlled. Wholesale changes use protected RPCs. AI assets have seller-approval/publication state. RLS stays enabled. No service/secret key is exposed in the browser.

## Implementation status
Database foundation and new professional fields are established; AI draft/assets and category-template tables exist; dedicated Seller Panel and Wholesale Hub pages are added; product-level wholesale workflow is protected by RPC. Actual AI image/video/360 generation requires an enabled production AI provider/gateway and is not falsely marked as already generated.

## Lock rule
Future work extends this blueprint. Do not remove modules, create a competing seller identity/verification path, or merge the dedicated Wholesale Hub back into the normal Seller Panel.
