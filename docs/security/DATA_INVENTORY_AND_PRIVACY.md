# ShubhMart Data Inventory and Privacy Controls

Status: inventory template and minimum-control specification. Complete from the actual schema, storage, logs, analytics, and provider integrations; do not guess at data fields or retention periods.

## Inventory template
For every data store and processing path record: data category, exact fields, purpose, source, subjects, reader/writer roles, storage location, encryption/access controls, retention/deletion rule, backup presence, processors/recipients, logs/analytics copies, and evidence owner.

## Categories to inventory
- Identity and account: user IDs, authentication identifiers, role/seller relationships.
- Contact and delivery: names, phone/email, addresses, delivery instructions.
- Commerce: cart, products viewed if tracked, orders, returns, support requests.
- Money and payment: order totals, provider order/payment IDs, signatures or verification metadata, refunds, reconciliation records. Never store card data or secrets unless a specifically approved compliant provider flow requires it.
- Loyalty: ShubhCoins balance, ledger entries, expiry/adjustments.
- Seller/business: shop profile, listings, stock, price, settlement/tax information if collected.
- Security/operations: IP/user-agent where collected, request IDs, auth events, audit logs, error traces, deployment logs.
- AI/support: prompts, client-supplied product lists, generated output, any stored conversation or support text.

## Required controls
- Collect only data needed for a stated feature; avoid collecting sensitive data by default.
- Apply least-privilege access to production, support, analytics, logs, backups, and third-party providers.
- Keep service-role keys and provider secrets server-side; redact authorization headers, cookies, tokens, signatures, addresses, and phone numbers from logs.
- Define and implement retention/deletion rules for each category, including backups and third-party copies where applicable.
- Verify export, account deletion, correction, and support processes against actual product behavior and applicable law; do not claim compliance without review.
- Use synthetic or irreversibly anonymized data in tests, screenshots, issue reports, and previews.
- Review storage bucket policies and public URLs; public product images must not accidentally expose private uploads.
- Document processors, data locations, incident contacts, and breach-assessment workflow.

## Required evidence before PASS
Schema/storage inventory, log field review, access-policy tests, retention owner and implementation, backup treatment, provider/data-flow inventory, and sanitized evidence. Unknown retention or unknown data flow is MISSING/UNVERIFIED, not PASS.