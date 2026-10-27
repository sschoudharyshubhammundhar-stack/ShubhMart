# ShubhMart Checkout and Payment State Machine

Status: target contract only. Compare against current schema, triggers, RPCs, Edge Functions, and provider integration before implementation. Do not apply database changes based on this document.

## Core invariants
1. The server calculates the final amount using trusted live prices and validated discounts/shipping/tax rules; client totals are hints only.
2. Each checkout idempotency key is bound to the authenticated customer and normalized request. Repeating it returns the same logical result; conflicting reuse is rejected.
3. Order, payment attempt, stock reservation, and ShubhCoins ledger operations have explicit states and durable IDs.
4. Paid is allowed only after server-to-server provider verification binds payment ID, provider order ID, internal order, exact amount in paise, INR currency, and captured status.
5. State transitions are atomic and idempotent. A retry cannot double-create an order, debit coins, reserve/release stock, or mark Paid.
6. Parent-product and variant inventory remain consistent and are reserved atomically under concurrency.
7. Cancellation, failed payment, expiry, refund, and retry behavior is explicitly defined; each reservation/debit is released at most once.

## Suggested lifecycle (validate before adopting)
- Checkout request received -> validate identity, payload, stock, price, promotion, coin balance and idempotency key.
- Atomic order preparation -> create/reuse pending order, reserve parent+variant stock, and record coin reservation/debit according to one documented model.
- Payment attempt -> create provider order using server-calculated amount and persist the exact binding.
- Verification -> fetch provider payment entity server-to-server; validate all bindings and captured status.
- Commit paid -> one transaction moves order/payment to Paid and finalizes stock/coin ledger exactly once.
- Failure/cancel/expiry -> one transaction or durable compensating workflow releases reservations/debits exactly once; record the reason and provider state.
- Refund/return -> separate authorized state machine; never treat refund request as completed refund.

## Concurrency and failure tests
- Two simultaneous buyers request the final stock unit.
- Two requests reuse the same idempotency key with identical and conflicting payloads.
- Provider order creation succeeds but database persistence fails, and vice versa.
- Verification receives wrong payment ID, wrong provider order, amount mismatch, non-INR currency, failed/authorized-not-captured status, invalid signature, or unknown order.
- Two webhook/client verification requests race; duplicate webhook/retry arrives after Paid.
- Cancel, expiry, and successful capture race.
- Coin balance changes concurrently; insufficient balance; duplicate debit/release.
- Variant stock changes while parent stock changes; no negative stock or oversell.
- Network timeout after provider success; retry safely reconciles without double effects.

## Evidence and safety
Run only with synthetic accounts, isolated database, provider test mode, and an approved test plan. Verify unique constraints, transaction boundaries, locking strategy, RPC permissions, and audit ledger. Do not run payment or mutation tests on production. Current production behavior remains UNVERIFIED until this contract is reconciled with actual database code and tests.