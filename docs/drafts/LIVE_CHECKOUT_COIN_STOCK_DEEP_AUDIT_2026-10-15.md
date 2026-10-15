# Live Checkout Function Deep Audit — 2026-10-15
**Scope:** Read-only inspection of the connected Supabase project `yauveaexbpokhytqijae`.  
**No changes performed:** This inspection executed SELECT/catalog reads only. No SQL DDL/DML, migration, grant change, function deployment, payment, or production data mutation was performed.  
**Important:** Findings below describe the live function definitions returned by the database at audit time, not the candidate code in the Git branch.

## Executive conclusion

**Do not treat checkout/payment/coin handling as launch-ready yet.** The live database contains multiple interacting integrity risks. Fixing only the browser callback or only the release RPC is insufficient. The most important newly confirmed issue is that the live `create_order_from_cart_with_coins` definition does not implement variant stock reservation or any stock decrement, while it writes order items without `variant_id` and leaves the order's `stock_reserved` default false. This conflicts with the locked requirement that both parent and variant inventory are handled consistently.

## Confirmed live findings

### CRITICAL — Coin release RPC remains callable by authenticated customers
Live `public.release_shubhcoins_for_order(uuid)`:
- `SECURITY DEFINER`, `search_path=public`.
- Effective ACL shown in `pg_proc.proacl`: `authenticated` has EXECUTE; `service_role` and owner also have EXECUTE. The output did not list PUBLIC explicitly, but inherited/default privilege behavior should still be verified through `has_function_privilege` for anon/authenticated/service_role before remediation.
- Uses `auth.uid()` to establish the customer/order relationship, then treats order `payment_status='Paid'` as the main paid guard.
- Does not verify provider payment state, does not require authoritative provider-side closure/non-capturability, and does not lock the order row before deciding to release.
- Can credit the redeem amount from the ledger while provider state is unknown or stale.
- A single existing `coin_release` row is used as an idempotency guard, but it is not sufficient to solve the race with payment success unless both transitions lock and check the same order in one transaction.

**Impact:** A customer may be able to call a privileged wallet-crediting RPC directly; additionally, a provider capture racing with release can create a contradictory paid/released outcome.

### CRITICAL — Live coin-aware checkout skips inventory reservation
Live `public.create_order_from_cart_with_coins(...)`:
- `SECURITY DEFINER` with `search_path=public` (not the hardened empty path).
- Verifies `auth.uid() = p_customer_id` and locks the wallet if coins are requested.
- Its cart/product loop selects `c.product_id,c.quantity,p.name,p.price,p.mrp,p.stock,p.status`; it does **not** select `c.variant_id` or lock the parent product rows.
- It checks parent product stock in the loop, but does not decrement `products.stock` or `product_variants.stock`.
- It inserts `Order_items` using only `order_id,product_id,quantity,unit_price,total_price`; it omits `variant_id`.
- It inserts an order without setting `stock_reserved=true`, so the schema default applies.
- It creates a payment row and redeems coins atomically in the same function transaction, but inventory is not reserved by this path.

**Impact:** Concurrent coin checkout can oversell stock; variant selection is not preserved in the order item; cancellation logic may not know which variant stock to restore. This is a separate, high-priority defect from the coin-release race.

### HIGH — Paid transition is not serialized with cancellation/release
Live `public.mark_razorpay_paid_secure(...)`:
- `SECURITY DEFINER`, `search_path=public`.
- Checks customer ownership, reads a gateway order ID from `payments`, then updates the order and all matching payment rows.
- Does not `FOR UPDATE` lock the order before transition.
- Uses `LIMIT 1` without deterministic ordering to choose the gateway order ID.
- Does not target a single exact payment attempt for the state transition.
- The function itself receives `p_signature`, but DB function body does not cryptographically validate it; this must remain exclusively a server-side verification responsibility and be guaranteed by every caller.
- Does not coordinate against a committed coin-release ledger entry.

**Impact:** Duplicate or concurrent payment attempts can be ambiguous; paid/cancel/release operations lack a unified serialization protocol.

### HIGH — Customer cancellation invokes legacy coin release internally
Live `public.cancel_customer_order(uuid,text)`:
- Locks the order row and checks customer ownership.
- Restores reserved inventory if `stock_reserved` is true.
- In the unpaid branch, updates order to Cancelled and then invokes `public.release_shubhcoins_for_order(p_order_id)`.
- Because this is an internal call, removing the frontend's direct RPC call alone does not remove the path.
- It does not first prove the provider can no longer capture a payment.

**Impact:** Cancellation can enter the unsafe release path and race with a provider-side capture.

### HIGH — Unpaid-order cancellation deletes payment attempt evidence
Live `public.cancel_unpaid_order(uuid)`:
- Locks order row and checks owner/status.
- Restores inventory based on `stock_reserved`.
- Deletes rows from `payments`, then order items, then order.
- It does not verify provider-side terminal closure/non-capturability before deleting payment evidence.

**Impact:** If a provider capture arrives late, the local attempt/order evidence needed to reconcile it may have been deleted. Cancellation and late capture need a durable state machine, not deletion as a shortcut.

### HIGH — SECURITY DEFINER search_path hardening is inconsistent
Catalog output showed:
- `release_shubhcoins_for_order`: `search_path=public`
- `create_order_from_cart_with_coins`: `search_path=public`
- `mark_razorpay_paid_secure`: `search_path=public`
- `cancel_customer_order` and `cancel_unpaid_order`: `search_path=''`

The latter two use schema-qualified names; the first three should be rewritten with `SET search_path = ''` and fully qualified names after all dependencies are reviewed. Do not mass-edit all SECURITY DEFINER functions blindly; inventory and review each one individually.

## Safe remediation architecture (design only, not applied)

1. **Define one order transition state machine.** Explicit states for pending, provider-indeterminate, paid, cancelled-but-reconciling, and terminal non-capturable. Do not map network errors to failed.
2. **Preserve provider attempt evidence.** Do not delete payment rows as the cancellation mechanism. Mark attempts/orders for reconciliation and retain immutable identifiers/events. If privacy/data retention requires cleanup, do so only after terminal reconciliation and retention policy.
3. **One lock order for all transitions.** Order row first; then payment attempt rows in deterministic key order; then wallet/ledger and stock rows in deterministic key order. Every release, cancel, paid transition, and webhook must follow the same order to reduce deadlocks and eliminate contradictory transitions.
4. **Service-authenticated provider evidence.** A server-only reconciliation function should retrieve provider state itself, validate payment ID, gateway order ID, amount in exact integer paise, currency, and status, and persist a minimal audit record. Client/browser callbacks are not evidence. Provider timeout, pagination truncation, unknown status, mismatch, or missing attempt history remains indeterminate.
5. **Do not release merely because all listed attempts failed.** Require provider-supported proof that the order/attempt is no longer capturable or a documented, tested provider cancellation/closure operation. If Razorpay semantics do not provide that guarantee, hold coins in an explicit pending-reconciliation state rather than risk double-spend.
6. **Atomic coin release.** A service-only DB function must lock the order, require trusted durable terminal evidence, reject if any paid/captured transition exists, verify exactly one authoritative redeem ledger entry, lock wallet, insert one release ledger entry protected by a unique constraint, and update wallet in the same transaction.
7. **Atomic paid transition.** Lock the same order first, target one exact payment attempt, reject contradictory coin-release/cancellation state, and idempotently accept only a verified provider capture. A late capture after a terminal coin release becomes an explicit incident/compensation workflow; never silently overwrite status.
8. **Repair coin-aware stock path.** Preserve cart variant IDs; validate and lock parent and variant rows; reserve both levels according to a single inventory model; persist variant_id on each order item; set stock_reserved only after all reservations succeed; transaction rollback must undo all partial changes. Cancellation restores exactly what was reserved, once.
9. **Checkout idempotency.** A client idempotency key is scoped to authenticated customer and stored with a canonical request fingerprint. The database atomically claims it; same key/same request returns same order; same key/different request rejects; concurrent requests cannot create duplicate orders.
10. **Least privilege rollout.** Migrate all internal callers first, verify effective ACLs for `anon`, `authenticated`, `service_role`, and PUBLIC, then revoke client EXECUTE on legacy release RPC. Use `has_function_privilege` in tests. Do not revoke before callers are migrated.

## Required next evidence before any migration is approved

- Read-only inventory of `payments`, `shubhcoins_wallets`, `shubhcoins_ledger`, `product_variants`, relevant indexes/unique constraints/triggers, and all function callers.
- A schema snapshot or isolated Supabase branch matching live migrations; the current Free-plan/project constraints must be respected. If an isolated DB cannot be created under the existing plan, do not substitute production for testing.
- Runtime tests for: same-order paid/release race; cancel/late-capture race; two simultaneous last-item checkouts; variant checkout/cancel; duplicate request keys; duplicate provider webhook; provider timeout after mock capture; cross-customer IDOR; direct RPC invocation and effective ACLs.
- SQL test assertions on wallet balance, ledger rows, payment rows, order state, order item variant_id, parent stock, variant stock, and stock_reserved before/after every scenario.
- Review of the provider's documented closure/capture semantics before implementing any automatic coin release.

## Explicit release gate

No production migration, function deployment, grant change, PR merge, real payment test, or live data modification is authorized by this document. The candidate branch reconciliation function intentionally does not release coins; it is fail-closed but incomplete. The production RPC remains risky until a coordinated fix is reviewed and explicitly approved.


## Additional catalog verification — effective permissions and RLS (read-only)

A direct `has_function_privilege` query confirmed effective privileges for the inspected functions:
- `anon`: cannot execute the inspected release, checkout-with-coins, or cancellation functions.
- `authenticated`: **can execute** `release_shubhcoins_for_order(uuid)`, `cancel_customer_order(uuid,text)`, and `cancel_unpaid_order(uuid)`; cannot execute `create_order_from_cart_with_coins(...)`.
- `service_role` and `postgres`: can execute all inspected functions.

This verifies that the legacy release function is not merely a theoretical explicit-ACL concern: the authenticated role has effective EXECUTE permission. Revoke only after internal call sites have been migrated and regression-tested, because the cancellation function currently invokes it internally.

Read-only RLS policy inventory for core tables showed owner-scoped SELECT policies for `Orders`, `Order_items`, `payments`, `shubhcoins_wallets`, and `shubhcoins_ledger`; cart operations are owner-scoped; active product variants are publicly selectable, with seller/admin policies for variant management. This is a useful baseline but **not a full RLS certification**: table grants, every policy on every table, views, RPC execution, triggers, and cross-table write paths still require review. In particular, RLS does not protect against a vulnerable SECURITY DEFINER function that is executable by a customer.

