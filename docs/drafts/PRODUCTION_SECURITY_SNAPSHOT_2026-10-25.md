# Production Security Snapshot — 2026-10-25

Status: **READ-ONLY VERIFICATION / RELEASE BLOCKED**
Repository branch reviewed: `fix/secure-checkout-edge-function`
Supabase project: `yauveaexbpokhytqijae`

## Safety boundary

This snapshot records read-only inspection only. No production SQL writes, migrations, Edge Function deployments, live payments, PR merges, or Cloudflare production changes were performed. Findings are not a claim that the system is “hacker-proof”.

## Current platform evidence

- Supabase project API reports status `ACTIVE_HEALTHY`, Postgres 17.6.1.166, region `ap-south-1`.
- Live Edge Function inventory reports three ACTIVE functions with JWT verification enabled:
  - `razorpay-payment`, version 4, SHA-256 `235d8db85a67589882f8f0d8add5e3389f61249f540983b293991997d56f2c80`.
  - `create-customer-order`, version 4, SHA-256 `4a8436d31744b3454b37380d521ead06c9f1cb595398ea7f24061dea085f0c8e`.
  - `shubhmart-ai`, version 1, SHA-256 `c048e55987b617368c105a5dd2e6f0c2fe50fd291a743f2c7b3dbe8037391791`.
- Live deployed payment function source was retrieved and compared with the checked-in candidate. They are different. The candidate is **not deployed**.
- Read-only public schema table inspection failed with a database connection timeout.
- Security Advisor request failed because the connected project/organization endpoint reported a hibernated project. Advisor findings are **BLOCKED / UNVERIFIED**, not zero findings.
- The commit-status endpoint for the reviewed source commit returned a successful Netlify deploy-preview status only; it did not return the expected Actions checks in that response. Do not use that response as proof of database/runtime safety.

## Findings and status

| Area | Evidence | Status |
|---|---|---|
| Razorpay provider verification | Active v4 checks customer JWT, order ownership, amount supplied by client against stored order, and HMAC signature; it does **not** fetch `/payments/{paymentId}` to independently validate provider order ID, captured status, currency and amount before calling `mark_razorpay_paid_secure`. | **FAIL — release blocker** |
| Razorpay RPC error handling | Active v4 returns `re.message` to the browser for attachment/paid-state RPC failures. | **FAIL — information disclosure / unsafe diagnostics** |
| Razorpay HTTP method handling | Active v4 handles OPTIONS, but does not explicitly reject methods other than POST before parsing the request. | **FAIL — hardening gap** |
| CORS | Active v4 and order function use `Access-Control-Allow-Origin: *`. JWT checks still exist; wildcard CORS alone is not proof of auth bypass. Actual web/app origin inventory and preflight behavior remain unverified. | **HARDENING REQUIRED** |
| Order creation identity context | Active v4 verifies the bearer token, then calls `create_order_from_cart_with_coins` with a service-role client. Earlier read-only catalog evidence says the installed RPC requires `auth.uid() = p_customer_id`; service-role context may not satisfy that guard. The current catalog could not be refreshed in this pass. | **BLOCKED — reconfirm exact live definition/grants** |
| Order creation idempotency | Active v4 has no idempotency key or request fingerprint. | **FAIL — duplicate-order/retry risk** |
| ShubhCoins input | Active v4 uses `Math.max(0, Math.floor(Number(b.shubhcoins || 0)))`; malformed non-empty input can become `NaN` and is not rejected at the Edge Function boundary. Database validation is not currently verified. | **FAIL — input validation gap** |
| Address ownership | Edge Function checks that address ID is a string; ownership validation must be enforced in the effective RPC. Live RPC definition could not be refreshed. | **UNVERIFIED** |
| Inventory reservation and release | Existing source audit records that the live coin-aware checkout does not reserve/decrement stock or set `stock_reserved`; the variant candidate conflicts with the locked parent-plus-variant contract. Exact live catalog could not be refreshed here. | **FAIL / BLOCKED** |
| Payment attempt persistence | Earlier read-only grant evidence found customer-scoped `attach_razorpay_order` call and installed EXECUTE grants may not align. Must reconfirm exact live grants before any external order is created. | **BLOCKED** |
| AI Edge Function | Live v1 is JWT-gated by platform configuration and its inspected code is a local fallback (no external LLM call in the retrieved source). It accepts product data from the request for local matching; it must not be treated as authoritative inventory or pricing. | **LIMITED FEATURE / server-side data authority unverified** |
| Live schema, RLS, triggers, SECURITY DEFINER/search_path | Table/catalog call timed out; Security Advisor call was blocked. | **UNVERIFIED — do not claim clean** |

## Candidate-vs-live mismatch

The checked-in candidate `supabase/functions/razorpay-payment/index.ts` contains server-to-server Razorpay payment lookup and checks provider payment ID, order ID, amount, INR currency and captured state before the paid-state RPC. The active deployed v4 source does not contain these checks. The candidate also uses safer generic error responses and explicit POST-only handling. **Do not assume these candidate protections are present in production.**

The checked-in candidate `create-customer-order/index.ts` rejects non-finite/negative ShubhCoins values and maps unknown database errors to a generic message. The active deployed v4 source returns raw RPC error messages and does not reject `NaN` at the function boundary. The candidate itself is still not release-ready: it lacks idempotency and depends on a draft SQL/RPC contract that has not been applied or tested.

## Required next steps, in order

1. Retry read-only database catalog retrieval when the connection is available. Capture effective definitions, owners, grants, RLS policies, indexes and triggers for the checkout, payment, cancellation, coin release, seller stock and return/restock paths. Record timestamp and schema evidence.
2. Reconcile checkout RPC identity context without removing ownership checks or broadening client privileges.
3. Design durable checkout idempotency (key + request fingerprint + stable stored result) and payment-attempt identity. A retry must not create a second order, stock reservation, coin debit or provider order.
4. Reconcile the inventory contract across checkout, seller stock edits, variants, cancellations, unpaid cleanup, returns/restock and admin transitions. Preserve exact reservation evidence and restore each counter at most once.
5. Test the SQL/functions in a disposable local PostgreSQL/Supabase fixture with synthetic data. Include concurrent checkout, rollback at each mutation, repeated cancellation, late capture, duplicate callbacks, role/JWT/RLS/grant tests, and coin release after cleanup.
6. Run Deno checks against pinned dependencies and test provider calls with mocks/Razorpay test mode only.
7. Re-run CI on the exact final candidate commit and separately verify branch protection/deployment approvals. Keep production SQL, deployment, merge and live payments blocked until evidence-backed review and explicit approval.

## Verdict

**BLOCKED — no production checkout/payment release approval.** The most important live payment-provider validation is missing from deployed v4, and current live database catalog/Advisor verification could not complete in this pass. Static tests and a preview deployment cannot substitute for effective-schema and isolated transaction tests.
