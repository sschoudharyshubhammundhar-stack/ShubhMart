# ShubhMart Checkout Security Test Matrix — 2026-10-25

Status: TEST SPECIFICATION ONLY. No tests in this document have been executed against a database, Razorpay sandbox, deployed Edge Function, or production environment.

Scope: candidate checkout/payment SQL and Edge Functions on `fix/secure-checkout-edge-function`. This document is not approval to deploy or execute SQL.

## Safety boundary

- Use a disposable, isolated PostgreSQL/Supabase test project with synthetic users, products, variants, carts, addresses, wallets, orders and payment rows.
- Never use production credentials, production customer data, live Razorpay keys, or production checkout as a test.
- Do not run candidate SQL against production. Capture schema, indexes, triggers, RLS policies and function grants from the isolated test database first.
- For provider tests, use Razorpay test mode only. Use a mock provider for negative cases where feasible.
- Every test must record environment, commit SHA, test input, expected result, actual result, and evidence. Mark anything not run as UNVERIFIED, not PASS.

## P0 — Release-blocking invariants

| ID | Test | Expected invariant |
|---|---|---|
| P0-01 | Same customer submits the same checkout request twice with the same idempotency key, sequentially | Exactly one order, one inventory reservation, one coin debit and one stable response |
| P0-02 | Same request arrives concurrently from two workers | Unique idempotency constraint/transaction ensures one logical order; no double stock/coin debit |
| P0-03 | Same idempotency key is reused with a different cart/address/payment/coin fingerprint | Reject as conflict; do not return the unrelated prior order |
| P0-04 | Two customers attempt to buy the final unit concurrently | At most one succeeds; stock never becomes negative |
| P0-05 | Variant selected | Decrement only the selected variant stock; parent stock behavior follows documented schema invariant |
| P0-06 | Invalid/foreign variant ID paired with another product | Reject without order, payment, coin, or stock side effects |
| P0-07 | Address belongs to another customer | Reject; no order created |
| P0-08 | Product is inactive, not live, deleted, or price changed after cart insertion | Reject or recompute using the authoritative locked price; never trust client total |
| P0-09 | Requested ShubhCoins are null, negative, non-numeric, NaN, fractional, excessive, or wallet missing | Deterministic validation; never negative balance, fractional coin debit, or silent NaN propagation |
| P0-10 | Failure after stock decrement but before order/items/payment/coin ledger completion | Entire database transaction rolls back all side effects |
| P0-11 | Payment ID from one order is submitted for another order | Reject; no state mutation |
| P0-12 | Duplicate payment ID is concurrently verified for two orders | Unique constraint and transaction permit at most one association |
| P0-13 | Valid HMAC but provider payment is authorized/not captured, wrong amount, wrong currency, wrong provider order, or unknown payment ID | Do not mark order Paid |
| P0-14 | Forged signature, malformed hex, wrong secret, missing fields, or replayed callback | Reject safely; no order/payment state change |
| P0-15 | Two different payment IDs race to pay the same order | At most one payment is accepted; the other is rejected/reconciled, never overwrites the winner |
| P0-16 | Duplicate callback for the same captured payment | Idempotent no-op; no duplicate coin credit, fulfilment, notification, or ledger effect |
| P0-17 | Old attempt callback arrives after a new attempt exists | Resolve by explicit attempt identity; never update a different/latest row merely due to timestamp ordering |
| P0-18 | Customer invokes privileged payment-transition RPC directly | Permission denied; only intended trusted server role can invoke |
| P0-19 | Anonymous/other customer invokes order/cart/address/coin RPCs with another customer's IDs | Denied by authorization and ownership checks |
| P0-20 | Customer cancels pending COD/Razorpay order | Inventory and coins released exactly once according to the documented state machine |
| P0-21 | Unpaid cleanup runs twice or races with cancellation | Idempotent; no double stock restore/coin release; ledger remains balanced |
| P0-22 | Paid order cancellation/refund path | Never silently restore stock or mark refund complete before provider/refund evidence; ledger/status transitions consistent |
| P0-23 | DB trigger rejects service-role update or unexpected grants allow customer update | Test grants and triggers as anon, authenticated owner, authenticated non-owner, admin and service_role; only intended transitions succeed |
| P0-24 | RPC raises an internal database/provider error | Client receives generic safe error; server logs contain correlation ID without secrets or sensitive payloads |
| P0-25 | CORS preflight from approved origin and unapproved origin | Approved app origins work; unapproved browser origins are not authorized by permissive policy; CORS is not treated as authentication |
| P0-26 | Malformed JSON, oversized body, wrong HTTP method, missing/expired bearer token | Consistent 4xx response; no side effects; no raw stack/SQL/provider errors |
| P0-27 | Razorpay order creation succeeds but attaching gateway order ID fails | Order remains safely recoverable/reconcilable; no second chargeable attempt is silently created |
| P0-28 | Provider timeout after create-order request | Retry/reconciliation avoids duplicate provider orders or duplicate customer charges |
| P0-29 | Order total is zero, negative, excessively large, decimal precision edge, or currency mismatch | Reject or normalize under explicit currency rules; never use client-supplied amount as authority |
| P0-30 | Seller/customer changes product ownership or seller state during checkout | Checkout follows a locked, validated seller/product ownership model; no cross-seller leakage |

## SQL candidate review gates before any database execution

1. **Attempt identity:** the draft currently chooses a payment row using `updated_at DESC, id DESC`. A timestamp is not a payment-attempt identifier. Introduce an explicit attempt ID or enforce a single active attempt per order and match updates to the exact `gateway_order_id`. Define how older attempts are reconciled.
2. **Attach retry semantics:** if an order already has a gateway order ID, a new different ID must not be attached to another otherwise-empty row without an explicit attempt creation/reconciliation contract.
3. **Unique payment ID preflight:** run a read-only duplicate report in the isolated database first. Define same-order duplicate behavior as well as cross-order duplicates before creating a unique index.
4. **Idempotency contract:** define key storage, request fingerprint, response replay, expiry/retention, concurrency constraint, and behavior after partial provider success. A frontend-only lock is insufficient.
5. **Cancellation symmetry:** prove every cancellation/unpaid cleanup path restores only previously reserved stock and releases debited coins exactly once. Avoid deleting an order before a release function that depends on the order row.
6. **Stock/order/coins atomicity:** confirm all database side effects occur in one transaction and any raised error rolls the whole transaction back.
7. **RLS/grants/triggers:** test effective permissions for anon, authenticated owner, authenticated non-owner, admin and service_role against the exact schema and function signatures.
8. **Order item pricing:** confirm stored item prices and totals use the same locked effective price, variant, quantity, coupon, delivery and coin rules.
9. **Server verification:** independently fetch the payment entity from the provider using server-held test credentials; verify payment ID, provider order ID, captured status, amount in paise, currency, and relevant account/environment before privileged state transition.
10. **No raw error leakage:** return stable client-safe error codes; retain internal diagnostics only in protected logs.

## Required evidence to close a test

For each case, preserve:
- test case ID and exact source commit SHA;
- disposable environment/project identifier (not credentials);
- synthetic fixture IDs;
- before/after order, payment, stock, wallet and ledger state;
- request/response status and sanitized logs;
- concurrency run count and observed invariant;
- reviewer and date.

A static regex/source test is not a substitute for SQL execution, provider sandbox verification, or concurrency testing.

## Current release verdict

**BLOCKED / NOT TESTED.** This is a test plan only. It does not certify the candidate SQL or deployed checkout. Do not merge, deploy, run migrations, or enable live payments until P0 cases pass in an isolated environment and a separate reviewer signs off.
