# Checkout Isolated Test Runbook — Draft Only

Date: 2026-10-15

Status: test plan only. No database branch was created, no SQL was applied, and no live checkout/payment was run.

## Why this gate exists

The current branch has passed JavaScript syntax/source-regression checks on earlier code commits. Those checks do not execute PL/pgSQL or prove transaction locking, Supabase JWT role context, RLS/grants, Deno runtime behavior, or Razorpay integration. Do not promote a preview build as proof of checkout readiness.

## Locked inventory contract — supersedes older contradictory test wording

The current ShubhMart roadmap requires both parent and variant stock accounting for variant orders:
- A non-variant line reserves quantity Q from `products.stock`.
- A variant line reserves quantity Q from both `products.stock` and the selected `product_variants.stock`, atomically. Both guarded decrements must succeed or the entire transaction rolls back.
- Validate that the selected variant belongs to the selected product and is active/sellable.
- Persist the exact product, variant, quantity and counters reserved in durable reservation evidence.
- Cancellation/payment-failure restoration must restore each counter actually decremented exactly once, from that evidence.
- All seller/admin/import/return/restock paths must follow the same invariant.

An older version of this runbook said that parent stock stays unchanged for a variant line. That wording conflicts with the locked roadmap and is superseded by this section. Do not implement either model until the real meaning of the two stock columns and every stock mutation path has been audited. If existing business semantics contradict this roadmap, stop and reconcile the design before writing SQL; do not silently choose a model.

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
| Product without variant | Parent stock decreases by exactly quantity; order records a reservation only after the complete transaction commits. |
| Product with variant | Parent product stock and selected variant stock each decrease by exactly quantity, in the same transaction; both remain unchanged if either decrement fails. |
| Two variants compete for the last parent capacity | Only the transaction that can reserve both parent capacity and its variant stock succeeds. |
| Insufficient parent or variant stock | Transaction fails; no order, payment, coin debit, partial stock decrement or completed idempotency result remains. |
| Inactive product/variant or wrong product-variant pairing | Rejected; no side effects. |
| Same idempotency key + same request, sequential retry | Same stable order/result; one order, one payment intent, one stock reservation and one coin debit. |
| Same key + same request, two concurrent calls | Both callers get the same result; no duplicate side effects. |
| Same key + changed address/cart/variant/quantity/coupon/payment method/coin amount | Stable conflict; original result unchanged; no new side effects. |
| New key for a deliberate checkout | Separate result, constrained by current stock and wallet balances. |
| Failure injected after parent decrement, variant decrement, order insert, payment insert, or coin debit | Whole transaction rolls back; no partial state. |
| Cancellation repeated or racing with cleanup | Every recorded stock counter restored at most once; ShubhCoins released at most once; payment/refund state remains consistent. |
| Unpaid cleanup followed by same-key retry | Stable expired/cancelled result; no recreated order and no double coin credit. |
| Wrong customer, missing/expired JWT, or spoofed customer ID | Request rejected and cannot read/create another customer's order. |
| Historical order with missing variant/reservation evidence | No guessed restoration; moved to explicit reconciliation/manual-review path. |

## Required Edge Function / gateway tests

- Run Deno type/runtime checks and the Edge Function tests using the project's pinned dependencies.
- Verify the actual role/JWT context at the RPC boundary. In particular, the live order RPC's `auth.uid() = p_customer_id` check conflicts with a service-role RPC call unless the SQL contract is deliberately reconciled and tested. Never solve this by weakening ownership checks.
- Verify `attach_razorpay_order` EXECUTE permissions before making any external provider order. Do not create a provider order if the database attachment path cannot succeed safely.
- Use a Razorpay sandbox/mock only. Test wrong payment ID, wrong provider order ID, amount mismatch, currency mismatch, authorized-but-not-captured payment, captured payment, duplicate callback, and replay with a different payment ID.
- A successful HMAC check alone is not a pass; provider payment facts and database state transition must also be checked.
- Simulate timeout after provider order creation and after database commit. The retry/reconciliation path must not create duplicate provider orders or mark an unpaid order paid.
- Test provider capture racing cancellation, duplicate/out-of-order webhooks, and a payment that becomes captured after the UI reported failure.

## Acceptance criteria

All assertions above pass on an isolated database; no duplicate orders or side effects appear under concurrency; parent and variant stock both reconcile exactly; no stock/coin drift occurs after rollback or repeated cancellation; Deno/runtime checks pass; provider interactions are sandboxed; and a reviewer approves schema/grants/RLS/search_path/error handling.

## Current known blockers (do not skip)

1. Idempotency is not yet implemented in the live RPC. The idempotency schema file is only a proposal.
2. Both checkout callers currently omit an idempotency key; their request payloads differ because only one sends ShubhCoins.
3. The live order RPC does not reserve/decrement stock or set `stock_reserved=true`.
4. Candidate Edge Function uses the service-role client after token verification, but the live SQL ownership guard expects `auth.uid()` to match the customer. The proposed SQL allowance is draft-only.
5. The payment attachment RPC's live grant inventory and customer-scoped caller do not currently align.
6. Unpaid cleanup / ShubhCoins release, payment retries and multi-seller attribution require an agreed lifecycle contract.
7. Stock reservation candidate and the earlier variant-stock test wording disagree with the locked parent-plus-variant requirement. The candidate must be redesigned rather than applied as-is.

Until these are resolved and tested, keep the PR draft and do not deploy the candidate checkout path.
