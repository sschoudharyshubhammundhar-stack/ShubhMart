# ShubhMart Checkout Red-Team Test Matrix — 2026-10-14

**Status: DRAFT / RELEASE BLOCKER.** This is a test specification, not evidence that the tests have run. It contains no credentials and performs no live requests. Run only against a disposable isolated Supabase/Postgres project with synthetic users and inventory.

## Non-negotiable invariants

1. **Identity:** a caller cannot create an order for another customer by changing a body field, URL, JWT metadata, or RPC argument. The trusted identity must come from a server-verified access token and the server-side boundary.
2. **Exactly-once logical checkout:** for a given customer and idempotency key, one canonical request creates at most one logical order, one inventory reservation, one payment intent association, and one coin debit. Same key + same fingerprint returns the original result; same key + different fingerprint returns a conflict without side effects.
3. **Atomicity:** order, order items, stock reservation, idempotency result, and coin ledger/debit commit or roll back together. No committed half-order and no stock/coin mutation after a failed transaction.
4. **Inventory:** a variant item reserves only that variant's stock; a non-variant item reserves parent stock. No stock may go below zero, including under concurrent requests. Product and variant must belong to one another and both be sellable under the actual lifecycle rules.
5. **Server-owned money:** client totals, discounts, coin balances, seller IDs, prices, payment statuses, gateway IDs, and order ownership are never trusted. Server-calculated values are persisted and returned.
6. **Payment authenticity:** an order is not marked paid from browser claims, a signature alone, an untrusted webhook body, or a payment ID without checking provider order ID, amount in paise, currency, captured/settled state, and association with the expected internal order.
7. **Refund correctness:** cumulative successful + in-flight refunds cannot exceed captured amount. Retries are idempotent. Partial refund does not silently become a full-refund state.
8. **Least privilege:** browser roles cannot execute privileged checkout/payment/refund functions or read internal idempotency records. SECURITY DEFINER routines use a pinned empty search_path and fully-qualified objects; every routine has a reviewed caller/authorization guard.
9. **Fail closed:** unexpected schema, provider, RPC, timeout, or validation errors must not result in success UI, paid state, inventory release, or a second order.
10. **Privacy:** API errors and logs never reveal secrets, raw SQL, access tokens, payment signatures, or another customer's address/order details.

## Required adversarial test cases

| ID | Scenario | Expected safe outcome |
|---|---|---|
| AUTH-01 | Missing, malformed, expired, revoked, or wrong-project bearer token | 401; no DB side effects |
| AUTH-02 | Customer A submits Customer B's ID/address/order ID | Reject; no cross-account read/write |
| AUTH-03 | Authenticated customer calls privileged RPC directly | Permission denied |
| IDEM-01 | Repeat same request and same idempotency key sequentially | Same order/result; stock and coins change once |
| IDEM-02 | 10–50 simultaneous identical requests with same key | Exactly one logical order and one set of effects |
| IDEM-03 | Reuse key with different address/payment/cart/coins | 409/conflict; no second side effect |
| IDEM-04 | Client loses response after DB commit, then retries | Original result replayed; no duplicate |
| IDEM-05 | Transaction fails after reservation but before completion | Full rollback; retry can safely succeed |
| IDEM-06 | Order is cancelled/deleted after key completed, then key replayed | Never silently recreate the purchase |
| CART-01 | Empty cart, deleted product, null/zero/negative/huge quantity | Reject before commit |
| CART-02 | Variant belongs to a different product | Reject; no inventory changes |
| CART-03 | Inactive/hidden product or inactive/missing variant | Reject; no order |
| STOCK-01 | Quantity equals available stock | Exactly zero remains; order succeeds once |
| STOCK-02 | Quantity exceeds available stock by one | Reject; stock unchanged |
| STOCK-03 | Two customers buy the last unit concurrently | At most one succeeds; stock never negative |
| STOCK-04 | Variant and parent stock are both present | Only the configured source of inventory decrements |
| PRICE-01 | Client tampers with total, item price, MRP, discount or seller | Server recomputes; client values ignored |
| COIN-01 | Negative, fractional, NaN, infinite, excessive, or stale coin amount | Reject/normalize according to explicit contract; no overdraft |
| COIN-02 | Two simultaneous checkouts redeem the same wallet balance | Wallet never negative; ledger and balance reconcile |
| COIN-03 | Payment fails, is dismissed, or provider times out | One defined compensating transition; no double credit |
| PAY-01 | Payment ID is valid but belongs to another gateway order | Reject; order remains unpaid |
| PAY-02 | Correct IDs but wrong amount/currency or not captured | Reject; order remains unpaid |
| PAY-03 | Duplicate/out-of-order payment callback | Idempotent state transition; no duplicate effects |
| PAY-04 | Provider order created but DB attachment fails | Reconciliation path records/reuses orphan; no blind duplicate provider order |
| PAY-05 | RPC permission denied after provider order creation | Safe recoverable state; no false success and no blind re-create |
| REF-01 | Two concurrent partial refunds would exceed captured amount | Lock/atomic aggregate cap permits only safe amount |
| REF-02 | Duplicate refund request/callback | One provider refund and one ledger/state effect |
| REF-03 | Partial refund followed by another partial refund | Correct cumulative amount and partial/full status |
| RLS-01 | User A selects/updates/deletes user B's cart, address, order, wallet, payment | Zero unauthorized rows changed or returned |
| RPC-01 | Enumerate every SECURITY DEFINER routine and effective grants | Each routine has documented caller, guard, search_path and test |
| ERR-01 | SQL exception or malformed response includes internal details | Generic safe response; correlation ID only in protected logs |
| CORS-01 | Untrusted Origin sends browser request | Strict origin policy where applicable; authorization remains server-side |
| RATE-01 | Burst/replay checkout and expensive RPC calls | Defined throttling/abuse controls; no correctness dependency on rate limits |

## Evidence required before a release decision

- [ ] Test schema built from a current schema-only export of the exact target migration baseline.
- [ ] Candidate SQL compiles on the target Postgres/Supabase version.
- [ ] Integration tests run against disposable synthetic data; include rollback assertions.
- [ ] Concurrency tests demonstrate idempotency and last-stock invariants, not just sequential happy paths.
- [ ] Property/state-transition tests cover payment, cancellation, cleanup, coins and refunds.
- [ ] Effective grants are inspected for anon, authenticated, service_role, function owner and PUBLIC.
- [ ] RLS tests use two separate customer identities and attempt both reads and writes.
- [ ] Current deployed Edge Function source/version is compared with the reviewed branch commit.
- [ ] Secret scan, static checks, and full test suite pass on the exact candidate commit.
- [ ] Rollback plan and post-deploy verification are written before any production change.

## Current known blockers from source review

- The current frontend does not send a database-backed checkout idempotency key to `create-customer-order`.
- The existing idempotency schema draft explicitly does not implement atomic claim/replay in the checkout RPC.
- The variant-stock SQL is a candidate function body only; it has not been compiled against an isolated database or exercised under concurrent transactions.
- Cancellation, unpaid cleanup, coin release, gateway retry/orphan recovery, and cumulative refunds still require an end-to-end state-machine review.
- Static source tests do not prove SQL semantics, database grants, RLS behavior, concurrency safety, or live deployment parity.

## Safety boundary

Do not run destructive, cross-account, payment, or concurrency tests against production. Do not use real payment instruments. Do not apply the candidate SQL, change Auth settings, deploy an Edge Function, merge the PR, or enable payments until the owner explicitly approves after the isolated test evidence is reviewed.
