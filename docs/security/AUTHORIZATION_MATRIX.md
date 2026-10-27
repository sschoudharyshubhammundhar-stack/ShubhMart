# ShubhMart Authorization Matrix

Status: required-control specification. This is not evidence that current policies enforce these rules. Validate against the live schema, RPCs, Edge Functions, and UI routes before marking any row PASS.

| Resource/action | Anonymous | Customer | Seller | Admin | Required enforcement point |
|---|---|---|---|---|---|
| Public live product read | Allow only published fields | Same | Same | Same | RLS/API filters; never expose private seller/customer fields |
| Draft/unlisted product read | Deny | Deny unless explicit owner workflow | Owning seller only | Authorized admin only | Server-side owner/role checks plus RLS |
| Product create/update/delete | Deny | Deny | Own shop and permitted fields only | Authorized admin only | RLS and validated server/RPC; immutable ownership fields |
| Own profile/address/cart | Deny or minimal public profile | Own records only | Own records only where applicable | Least privilege | RLS and object-level authorization |
| Order read | Deny | Own orders only | Only orders/line items legitimately assigned to seller | Authorized admin | RLS/API checks; avoid trusting client-supplied IDs |
| Order create/checkout | Deny | Authenticated customer; server computes trusted totals | Deny except explicitly designed seller workflow | No bypass of ledger invariants | Edge Function + atomic DB transaction |
| Payment status/verification | Deny | Own payment/order only | No ability to set Paid | Reconciled, audited admin workflow only | Provider verification and atomic state transition |
| ShubhCoins balance/ledger | Deny | Own balance and ledger read; spend within server rules | Deny | Explicit audited permissions | Atomic ledger; never accept client-set balance |
| Stock/variant mutation | Deny | No direct write | Own inventory only via validated operation | Authorized admin | Atomic product+variant reservation/release |
| Refund/cancel/return | Deny | Own order within policy | Only assigned permitted steps | Explicitly authorized role | State machine, idempotency, audit trail |
| Sensitive RPC execution | Deny by default | Only narrow user-scoped RPCs | Only narrow seller-scoped RPCs | Explicit allowlist | EXECUTE grants, internal authorization, safe search_path |

## Required review for each resource
- Identify every table, view, storage bucket, RPC, Edge Function, and API route exposing the resource.
- Document anonymous/authenticated role grants, RLS enabled state, policies, ownership predicates, and privileged paths.
- Test customer A vs customer B, seller A vs seller B, customer vs seller, non-admin vs admin, anonymous, missing/expired JWT, and service-role context.
- Confirm the server ignores or rejects client attempts to set user_id, seller_id, role, price, discount, payment state, coin balance, stock, and refund status.
- Record exact test IDs and sanitized evidence in SECURITY_TEST_MATRIX.md.

## Status rule
Until current policies/grants and isolated negative tests are inspected, every row is UNVERIFIED. Do not infer enforcement from hidden UI buttons or verify_jwt=true alone.