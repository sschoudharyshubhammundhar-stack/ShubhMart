# ShubhMart Threat Model

Status: working model; validate against current code and database before treating any control as present.
Last reviewed: 2026-10-27.

## Security objectives
- Customers can access only their own profile, addresses, cart, orders, and payment status.
- Sellers can manage only their authorized shop, inventory, and permitted order data.
- Admin actions require server/database role authorization, not merely hidden UI controls.
- Payment becomes Paid only after independent server-side provider verification and an atomic, idempotent state transition.
- Inventory and ShubhCoins are reserved, debited, and restored at most once under retries, concurrency, cancellation, and failure.
- User-supplied content cannot execute script or inject markup.
- Secrets and sensitive customer/payment data are not exposed in client bundles, logs, errors, or repository history.
- Releases are reviewable, traceable, reversible, and do not silently affect production.

## Assets
Customer identities, sessions, addresses, contact details, order history; seller accounts, listings, inventory and prices; orders, payment IDs, signatures, refunds and payment state; ShubhCoins balances and ledger; Supabase secret keys, Razorpay credentials, Cloudflare credentials and GitHub tokens; schema, RLS, grants, RPCs, triggers, Edge Functions and deployment configuration.

## Trust boundaries
Browser/mobile to public app and Supabase; untrusted payload to Edge Functions; Edge Functions to database using user-scoped or service-role credentials; Edge Functions to Razorpay; GitHub PR/CI to Cloudflare preview and production; customer/seller/admin identities to database authorization; imported content and errors to rendered UI.

## Threat scenarios
- Unauthenticated visitors probe endpoints and IDs.
- Customer manipulates another customer's IDs, totals, coins, address, or order state.
- Seller attempts cross-seller access.
- Malicious listing content attempts XSS or unsafe resource URLs.
- Replay/concurrent checkout or payment requests duplicate orders, coin debits, stock changes, or payment transitions.
- Weak rate limits, broad CORS, compromised dependencies, leaked secrets, or unreviewed deployment credentials enable abuse.
- Operator mistakes break checkout, delete data, or deploy untested code.

## Required controls (must be verified)
- Server-side identity and object-level authorization for every sensitive operation.
- Least-privilege RLS, grants, RPC EXECUTE permissions, SECURITY DEFINER controls and safe search_path.
- Strict schema validation and server-calculated prices, discounts, tax and shipping.
- Razorpay server-to-server payment lookup; exact order/payment/amount-in-paise/currency/captured-status checks before Paid.
- Durable idempotency keys and uniqueness for order creation, payment verification, coin ledger, stock reservation/release.
- Atomic transactions for order/payment/inventory/coin changes and invariant-preserving rollback.
- Context-appropriate output encoding; avoid unsafe HTML sinks; validate image URLs.
- Appropriate CORS, method allowlists, body limits, rate limits, generic client errors and protected logs.
- Secret scanning, dependency review, least-privilege CI and production deployment approvals.
- Recovery plan and monitored incident response.

## Known audit limits
Supabase table/migration inspection timed out on 2026-10-27; Security Advisor was unavailable. RLS, grants, RPC definitions, triggers, and inventory invariants remain UNVERIFIED. Browser/device runtime and end-to-end payment testing are not evidenced by source tests. Do not claim exploitability solely from source-level weaknesses; validate only in an isolated authorized environment.
