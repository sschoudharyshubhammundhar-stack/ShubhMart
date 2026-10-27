# ShubhMart Security Audit Snapshot — 2026-10-27

## Scope and safety boundary
- Repository branch reviewed: `security/h01-safe-image-url`; current PR #66 is open, draft, and not merged.
- Supabase project: `yauveaexbpokhytqijae`; project API reports `ACTIVE_HEALTHY`, region `ap-south-1`.
- Production database writes, SQL, migrations, Edge Function deployments, payment activation, and production deployment were not performed.
- This is a source-level snapshot, not a penetration-test certification. Do not describe the system as “hacker-proof.”

## Verified PASS
1. Cloudflare preview build for commit `8f4fa7c` reported build and deployment success. It was a preview deployment, not production.
2. The new GitHub Actions workflow ran for commit `76ae2ca`: `node --test tests/safe-image-url-source.test.js`; 2 tests passed, 0 failed. This checks source patterns and known image sinks, not browser behavior or all XSS cases.
3. `safeImageUrl()` is used at the known customer product-image locations covered by the regression test. It accepts HTTPS only and rejects URL embedded credentials.
4. Both `razorpay-payment` and `create-customer-order` report ACTIVE version 4 with `verify_jwt=true`. This does not by itself prove business authorization or payment correctness.
5. PR #66 remains open, draft, and unmerged.

## Findings requiring remediation / verification

### H-02 — Payment verification relies on signature but does not independently retrieve payment entity
**Status: FAIL (source-level control gap; exploitability not tested).**
The active `razorpay-payment` function computes HMAC for `razorpay_order_id|razorpay_payment_id` and then calls `mark_razorpay_paid_secure`. In the retrieved active source, the verify path does not first fetch the payment entity from Razorpay and independently compare the provider-reported payment ID, linked order ID, amount, INR currency, and captured status. A valid signature is an important control, but these server-side invariants should also be checked before Paid is committed.
**Required safe fix:** implement a candidate on a non-production branch; validate the provider entity and order/customer/amount/currency/captured status; enforce idempotent state transition in the database transaction; test invalid, mismatched, failed, authorized-but-not-captured, replayed, and duplicate requests in isolated test infrastructure. Do not deploy until database RPC behavior/grants and rollback path are verified.

### H-03 — Client-supplied ShubhCoins coercion is permissive
**Status: FAIL (input-validation weakness in active source).**
The active `create-customer-order` function uses `Math.max(0, Math.floor(Number(b?.shubhcoins||0)) )`. This coercively accepts values that should be rejected (for example fractional, boolean, or numeric-string inputs) rather than requiring a canonical safe non-negative integer. The database RPC must still enforce balances and totals, but the edge function should reject malformed input instead of silently normalizing it.
**Required safe fix:** strict input schema validation and database-side enforcement of coin balance, discount cap, order total, and atomic debit; unit tests for negative, fractional, boolean, array/object, whitespace, exponent, unsafe integer, and replay cases.

### H-04 — Database state and grants could not be verified in this audit
**Status: BLOCKED / UNVERIFIED.**
Supabase table/migration listing timed out; Security Advisor reports project hibernated. Therefore RLS policies, grants, triggers, RPC bodies, idempotency, stock reservation/restoration, and payment state transition cannot be certified from this run.
**Required safe fix:** repeat read-only table/migration/advisor/RPC/grant inspection when the database connection is responsive. Do not apply candidate SQL based on this report alone.

### H-05 — Wildcard CORS on authenticated edge endpoints
**Status: REVIEW (not by itself proof of unauthorized access).**
The active `razorpay-payment` and `create-customer-order` sources return `Access-Control-Allow-Origin: *`. Bearer authentication and JWT verification are present, but CORS should be constrained to known production/preview origins where feasible, with OPTIONS/POST behavior tested. CORS is not an authorization control and must not replace server-side authorization.
**Required safe fix:** document required origins first, then change only in a branch and test customer, seller, admin, and preview flows.

### H-06 — Provider/database errors may be returned to clients
**Status: REVIEW.**
The payment function returns some provider and RPC error messages directly. Normalize client-facing errors and retain detailed diagnostic context only in safe server-side logs; never log keys, full authorization headers, signatures, or sensitive customer data.

### H-07 — AI helper trusts client-supplied product list for its fallback response
**Status: REVIEW / LOW confidence impact.**
The active `shubhmart-ai` function accepts a client-provided `products` array and computes fallback matches from that array rather than verifying product IDs and live/visibility status server-side. It appears to be a fallback helper, not an authoritative catalog endpoint, but its output must not be used as proof of product availability, price, or permission.
**Required safe fix:** treat output as suggestions only; fetch/validate product IDs and live visibility on the server before any action, and never let this helper set prices, stock, order state, or seller permissions.

## Not yet tested
- Browser/mobile behavior and actual hostile image URL cases.
- Full HTML/DOM XSS audit (including inline event handlers and unsafe HTML construction).
- Authentication/IDOR across customer, seller, admin, order, address, returns, and support APIs.
- RLS, table grants, function execute grants, trigger/RPC semantics.
- Checkout idempotency and duplicate order/coin/stock mutation.
- Variant + parent stock atomic reservation and restoration on cancel/payment failure.
- Razorpay webhook authenticity, replay protection, refund path, and reconciliation.
- Rate limiting/abuse controls, secret exposure, dependency pinning, CI supply-chain, Cloudflare permissions, branch protection and environment approvals.
- Full repository test suite, typecheck, build, and real device testing.

## Required order of work
1. Preserve this PR as draft; do not merge based on image tests alone.
2. Run full repository CI and inspect the complete DOM/XSS surface in a branch.
3. Build and test strict ShubhCoins input validation in a branch.
4. Build server-to-server Razorpay entity verification and idempotent payment transition in a branch; do not deploy.
5. Re-establish read-only database access and inspect RLS, grants, RPCs, triggers, stock, and coin flows.
6. Add isolated test cases for duplicate/replay/race/failure paths; verify stock/coins/orders are atomic.
7. Review CI permissions, pinned action SHAs, branch protection, Cloudflare preview/prod separation and secrets handling.
8. Only after evidence and explicit approval, plan production changes with rollback and post-deploy verification.

## Change log for this snapshot
- Current branch commit when this report was prepared: `76ae2cabb026a458e44ce0bea116f4a088c97097`.
- No production database, payment configuration, or production deployment was changed.
