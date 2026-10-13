# Checkout Isolated Test Runbook — Draft Only

Date: 2026-10-13

Status: test plan only. No database branch was created, no SQL was applied, and no live checkout/payment was run.

## Why this gate exists

The current branch has passed 30 JavaScript syntax/source-regression checks. Those checks do not execute PL/pgSQL or prove transaction locking, Supabase JWT role context, RLS/grants, Deno runtime behavior, or Razorpay integration. Do not promote a preview build as proof of checkout readiness.

## Safe environment rule

- Use a disposable local PostgreSQL/Supabase environment or a separately approved isolated test project populated only with synthetic records.
- Do not point tests at production project `yauveaexbpokhytqijae`.
- Do not create a hosted Supabase branch until its cost is checked and explicitly approved. Do not use live customer records, live addresses, or real Razorpay credentials.
- Keep production migrations, Edge Function deployment, PR merge, and live payment testing out of this runbook.

## Preflight — must all pass before running SQL

1. Record the exact candidate commit SHA and copy the database schema/function definitions into the isolated test fixture without customer data.
2. Verify fixture column names, constraints, extensions, trigger definitions, function owners, EXECUTE grants, RLS policies and Supabase auth helpers. Do not assume the production schema snapshot is unchanged.
3. Set test-only credentials and provider mocks. Confirm the target database URL is local/isolated and cannot point to production.
4. Load the fixture and candidate SQL only in the disposable environment. If a referenced field/constraint/trigger differs, stop and update the candidate instead of altering production.
5. Capture schema version, test data IDs and output logs; redact JWTs, API keys, customer information and payment secrets.

## Required database transaction tests

| Scenario | Required assertion |
| --- | --- |
| Product without variant | Stock decreases by exactly quantity; order records `stock_reserved=true`. |
| Product with variant | Variant stock decreases once; parent product stock is unchanged. |
| Insufficient product/variant stock | Transaction fails; no order, payment, coin debit, partial stock decrement or completed idempotency record remains. |
| Inactive product/variant or wrong product-variant pairing | Rejected; no side effects. |
| Same idempotency key + same request, sequential retry | Same stable order/result; one order, one payment intent, one stock reservation and one coin debit. |
| Same key + same request, two concurrent calls | Both callers get the same result; no duplicate side effects. |
| Same key + changed address/cart/variant/quantity/coupon/payment method/coin amount | Stable conflict; original result unchanged; no new side effects. |
| New key for a deliberate checkout | Separate result, constrained by current stock and wallet balances. |
| Failure injected after stock update, order insert, payment insert, or coin debit | Whole transaction rolls back; no partial state. |
| Cancellation repeated or racing with cleanup | Stock restored at most once; ShubhCoins released at most once; payment/refund state remains consistent. |
| Unpaid cleanup followed by same-key retry | Stable expired/cancelled result; no recreated order and no double coin credit. |
| Wrong customer, missing/expired JWT, or spoofed customer ID | Request rejected and cannot read/create another customer's order. |

## Required Edge Function / gateway tests

- Run Deno type/runtime checks and the Edge Function tests using the project's pinned dependencies.
- Verify the actual role/JWT context at the RPC boundary. In particular, the live order RPC's `auth.uid() = p_customer_id` check conflicts with a service-role RPC call unless the SQL contract is deliberately reconciled and tested. Never solve this by weakening ownership checks.
- Verify `attach_razorpay_order` EXECUTE permissions before making any external provider order. Do not create a provider order if the database attachment path cannot succeed safely.
- Use a Razorpay sandbox/mock only. Test wrong payment ID, wrong provider order ID, amount mismatch, currency mismatch, authorized-but-not-captured payment, captured payment, duplicate callback, and replay with a different payment ID.
- A successful HMAC check alone is not a pass; provider payment facts and database state transition must also be checked.
- Simulate timeout after provider order creation and after database commit. The retry/reconciliation path must not create duplicate provider orders or mark an unpaid order paid.

## Acceptance criteria

All assertions above pass on an isolated database; no duplicate orders or side effects appear under concurrency; no stock/coin drift occurs after rollback or repeated cancellation; Deno/runtime checks pass; provider interactions are sandboxed; and a reviewer approves schema/grants/RLS/search_path/error handling.

## Current known blockers (do not skip)

1. Idempotency is not yet implemented in the live RPC. The idempotency schema file is only a proposal.
2. Both checkout callers currently omit an idempotency key; their request payloads differ because only one sends ShubhCoins.
3. The live order RPC does not reserve/decrement stock or set `stock_reserved=true`.
4. Candidate Edge Function uses the service-role client after token verification, but the live SQL ownership guard expects `auth.uid()` to match the customer. The proposed SQL allowance is draft-only.
5. The payment attachment RPC's live grant inventory and customer-scoped caller do not currently align.
6. Unpaid cleanup / ShubhCoins release, payment retries and multi-seller attribution require an agreed lifecycle contract.

Until these are resolved and tested, keep the PR draft and do not deploy the candidate checkout path.
