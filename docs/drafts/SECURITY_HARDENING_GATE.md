# ShubhMart Security Hardening Gate — Draft Only

Updated: 2026-10-13

Status: defensive implementation plan and release gate. This document does not claim the listed controls are already enabled. No production settings, SQL, secrets, deployment, or payment flow were changed by adding this plan.

## Security objective

Reduce attack surface, prevent one customer's/seller's access from crossing into another account, limit abuse, protect checkout integrity, detect suspicious activity, and make recovery possible. Absolute immunity from hacking cannot be promised; controls must be verified continuously.

## P0 — Must pass before enabling customer checkout or merging checkout changes

### Identity and authorization
- Authenticate every protected Edge Function request server-side; reject missing, malformed, expired, or invalid JWTs.
- Derive customer/seller/admin identity from verified server auth context only. Never trust a browser-supplied user ID, seller ID, role, price, discount, stock, payment status, or coin balance.
- Keep admin/service-role credentials server-only. Never bundle them into HTML, JavaScript, mobile/PWA assets, logs, or source maps.
- Audit RLS on every exposed table. Default to deny; add only minimal policies. Test cross-customer and cross-seller read/write attempts explicitly.
- For SECURITY DEFINER functions: pin a safe search_path, schema-qualify objects, revoke broad EXECUTE grants, grant only required roles, and validate ownership inside the function.
- Make authorization checks cover object ownership and action permission, not merely whether the caller is logged in.

### Checkout, inventory, coins and payments
- Make order creation, inventory reservation, order items, payment intent and coin ledger changes one database transaction.
- Use database-enforced idempotency scoped to authenticated customer + checkout attempt; compare a canonical request fingerprint and reject key reuse with changed input.
- Lock actual inventory rows in deterministic order; use guarded decrements; prove concurrent buyers cannot oversell.
- Verify variant ownership/status and reserve exactly the selected SKU. Do not mix parent and variant inventory without an explicit catalog rule.
- Validate payment amount, currency, provider order ID, provider payment ID and captured/settled status server-side before a paid transition.
- Make payment callbacks, cancellations, refunds, unpaid cleanup and coin restoration safe under retries and concurrency.
- Do not call an external payment provider until the local payment-intent/attachment path and grants are known to work; add reconciliation for timeouts.
- Resolve multi-seller cart semantics before launch; sellers must never see or mutate another seller's items, delivery data, commissions or payouts.

### Secrets and data
- Keep Supabase service-role keys, Razorpay secrets, signing keys and privileged tokens in server-side secret storage only.
- Rotate any credential that was ever committed, pasted into chat/logs, or exposed in a client bundle; deleting the visible text alone is not sufficient.
- Never log passwords, OTPs, access tokens, full payment secrets or unnecessary personal data. Redact authorization headers and provider payload secrets.
- Minimize customer data in analytics, test fixtures, exports and backups. Use synthetic data in tests.

## P1 — Abuse resistance and browser hardening

- Apply rate limits and request-size limits to login/OTP, search, cart mutation, checkout, coupon, review, seller onboarding and admin endpoints. Use stricter limits for costly or sensitive actions.
- Add replay protection and short-lived challenges where appropriate; do not rely on client-side timers or hidden buttons as security controls.
- Validate input schemas and types server-side; enforce numeric bounds, positive quantities, allowed enum values, string length limits and canonical identifiers.
- Use restrictive CORS allowlists for known app origins. CORS is not authentication and must not be treated as an authorization control.
- Review CSP, HSTS, frame-ancestors/X-Frame-Options, X-Content-Type-Options, Referrer-Policy and Permissions-Policy. Roll out CSP in report-only mode first if the current site has inline scripts that could break.
- Render user-generated text as text, sanitize allowed rich text, and avoid unsafe HTML insertion. Check product descriptions, reviews, seller listings, profile fields and support messages for stored/reflected XSS.
- Prevent CSRF for cookie-authenticated mutations; ensure secure, HttpOnly, SameSite cookie settings if cookies are used.
- Ensure errors are useful to legitimate users but do not expose SQL, stack traces, secret values, internal paths or authorization details.

## P2 — Supply chain, monitoring and recovery

- Add dependency vulnerability checks and secret scanning to CI; pin or review dependency updates and third-party GitHub Actions.
- Keep CI permissions minimal (contents: read unless a job truly needs more); never expose deployment secrets to untrusted pull-request code.
- Separate validation from deployment. Pull-request checks must not deploy production or run migrations.
- Add automated tests for authorization boundaries, RLS, idempotency, concurrency, rate limiting, payment transitions and rollback behavior.
- Record security-relevant events (repeated auth failures, privilege changes, checkout conflicts, payment verification failures, seller/admin changes) with request/correlation IDs, while excluding secrets.
- Alert on unusual admin actions, spikes in failures, repeated coupon abuse, payment mismatch, inventory drift and abnormal data exports.
- Document a credential-rotation procedure, incident response contact path, and tested restore/recovery procedure. A backup is not proven until restore is tested.

## Required adversarial test checklist

- [ ] Customer A cannot read, edit, cancel or pay for Customer B's order.
- [ ] Seller A cannot access Seller B's order items, buyer address, settlement, shipment or payout.
- [ ] A normal user cannot invoke admin-only RPCs or set an admin/seller role.
- [ ] Tampered price, total, coupon, coin amount, stock, seller ID or payment status from the browser is ignored/rejected.
- [ ] Missing/expired/forged JWT and malformed JSON are rejected with no side effects.
- [ ] Replayed checkout request and concurrent duplicate callbacks create no duplicate order, stock decrement, payment or coin ledger entry.
- [ ] Two buyers competing for the last unit cannot oversell product or variant stock.
- [ ] Payment amount/order/currency/status mismatch never marks an order paid.
- [ ] XSS payloads in user-controlled catalog/review fields render inert.
- [ ] Rate limits apply without locking out normal shoppers; logs contain no credentials or full tokens.
- [ ] Restore from backup and rotate test credentials successfully.

## Evidence required for each release gate

For every checked item, attach a test result, configuration evidence, or reviewer-approved reason why it does not apply. A green syntax check or successful preview build is not evidence for database authorization, race conditions, payment correctness, or production security.

## Current checkout-specific release blockers

- Database-backed idempotency is not implemented in the live RPC.
- Live order RPC stock reservation and variant handling are incomplete.
- Caller/RPC auth context and payment-attachment grants need one consistent, isolated-tested design.
- Unpaid cleanup, ShubhCoins restoration, cancellation/refund races, and multi-seller attribution need an atomic lifecycle design.
- Isolated PostgreSQL concurrency/transaction tests, Deno runtime checks and payment-provider sandbox tests remain required.

## Change-control rule

Do not apply candidate SQL to production, deploy Edge Functions, merge this draft PR, enable real payments, create a paid test branch, or change production security settings without the user's explicit approval and a reviewed rollback plan.
## Initial code/config observations (2026-10-13)

- The Cloudflare config (`wrangler.toml`) serves static assets from the repository root and does not define a Worker entry point. A root `_headers` file was not present at the inspected branch ref; do not assume Pages-style `_headers` rules apply to this Workers static-assets deployment. Confirm the supported response-header mechanism before rollout.
- `index.html` loads Supabase JS from jsDelivr and Razorpay Checkout from Razorpay's hosted script, and includes inline JavaScript. A strict CSP cannot be pasted in blindly: first inventory all required script/connect/image/frame origins, introduce report-only monitoring where feasible, and avoid breaking login or payment checkout.
- `customer/customer-app.js` escapes several displayed fields, which is a useful baseline, but product search constructs a PostgREST `.or(...)` filter by concatenating user-entered search text. Treat this as an input-grammar robustness issue: canonicalize/limit search text or move to a safer server-side search path; test quotes, commas, parentheses, percent and underscore wildcard behavior.
- The client renders product/category data through `innerHTML` templates. Escaping is used in the inspected product listing path, but every rendering sink and URL context needs a full audit; HTML escaping alone is not a universal URL/JavaScript-context sanitizer.
- Added `.github/workflows/security-secret-scan.yml` on this branch. It runs Gitleaks on full Git history for pull requests and this feature branch, with read-only repository permissions and no deploy step. A clean scan is not yet confirmed; if a real secret is detected, rotate/revoke it.

These are initial observations, not a complete penetration test or confirmation that production response headers are already hardened.
