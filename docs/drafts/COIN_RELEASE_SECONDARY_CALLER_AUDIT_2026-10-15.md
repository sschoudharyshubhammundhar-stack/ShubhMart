# ShubhMart — Secondary coin-release caller audit (2026-10-15)

**Status: HIGH-PRIORITY FINDING / DESIGN AND SOURCE AUDIT ONLY. No production changes.**

## Newly confirmed finding

The live Supabase database currently contains these SECURITY DEFINER routines:

- `public.release_shubhcoins_for_order(uuid)`: `search_path=public`; ACL includes `authenticated` and `service_role`. It requires `auth.uid()`, checks order ownership and only rejects the exact case-sensitive string `payment_status = 'Paid'`. It does not query Razorpay/provider payment state and does not lock the order row before deciding to release.
- `public.cancel_customer_order(uuid,text)`: its live definition calls `public.release_shubhcoins_for_order(p_order_id)` for the unpaid/cancelled branch. It is executable by `authenticated`. Thus, removing the direct browser RPC call does **not** close every path to the unsafe release logic.
- `public.cancel_unpaid_order(uuid)`: its live definition locks the order, then deletes local payment rows, order items and the order after restoring reserved stock. It does not prove the provider order is terminal before deleting local payment evidence. A later provider capture could therefore become difficult to reconcile if this routine is used on a live Razorpay attempt.
- `public.mark_razorpay_paid_secure(...)` in the live database differs from the newer candidate source: live version uses `search_path=public`, does not lock the order row, and updates every payment row for that order/customer instead of a single deterministically selected attempt. The candidate SQL in the branch is **not deployed**.

These are observations from read-only inspection of live function definitions and ACLs. No exploit was attempted and no customer record or balance was modified.

## Why this changes the remediation order

The previous browser-side patch is only a partial mitigation. The legacy release function remains callable in the live database until a coordinated migration is reviewed and deployed. In addition, the customer-cancellation RPC calls it internally. Merely revoking the legacy grant before replacing that caller can make cancellation fail and roll back the whole transaction. Merely replacing the frontend call does not fix direct RPC invocation by an authenticated customer.

## Required coordinated fix — do not cherry-pick a single item

1. Implement and test a private, append-only provider-reconciliation evidence record. The browser must not be able to write or forge it.
2. Implement a narrowly scoped service-only database transition that revalidates the evidence, locks the order first, locks all associated payment attempts in stable order, locks redeem ledger and wallet rows, and credits exactly once in one transaction.
3. Change `cancel_customer_order` so cancellation cannot independently release coins based on local status alone. Cancellation, inventory restoration and payment reconciliation need one defined state machine and a consistent lock order.
4. Change `cancel_unpaid_order` so it does not delete the only local payment-attempt evidence while the provider order may still capture. Retain/audit attempt history and use a terminal-close protocol before stock/coin settlement.
5. Change `mark_razorpay_paid_secure` to lock the same order and payment attempts in the same order, target one verified attempt, reject conflicting release ledger state, and make same-payment retries idempotent.
6. Only after all internal callers and frontend paths are coordinated, revoke EXECUTE on the legacy release RPC from `PUBLIC`, `anon`, and `authenticated`. Verify effective privileges with `has_function_privilege` for each role and inspect `proacl` after deployment.
7. Run isolated DB tests for cancellation vs capture, cancellation vs release, late capture, duplicate webhook/verification, cross-customer IDs, lock contention, and injected failures. Verify inventory, wallet balance, lifetime_spent, and ledger invariants after each test.

## Important implementation boundary

The branch Edge Function `reconcile-shubhcoins-payment` is deliberately fail-closed and **does not release coins**. It currently returns an indeterminate/blocked outcome unless it can safely classify the provider history; even a list of failed attempts is not treated as proof that the order is permanently non-capturable. It is not a complete remediation service and must not be represented as one or deployed as a completed fix.

## Evidence and limits

- Live DB function definitions and ACLs were read-only queried on 2026-10-15.
- Live Edge Function inventory contained `razorpay-payment`, `create-customer-order`, and `shubhmart-ai`; it did **not** contain `reconcile-shubhcoins-payment` at the time of inspection.
- No production SQL, grant changes, function deployment, real payment, customer balance update, or PR merge was performed.
- Static checks cannot establish race safety. The database transaction protocol and provider terminal-state semantics remain release blockers.
