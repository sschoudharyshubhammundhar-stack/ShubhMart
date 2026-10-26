# Critical Review — ShubhCoins Release Race Condition
Date: 2026-10-15
Status: Confirmed source/database logic finding; remediation is draft-only
Scope: Read-only inspection of the existing Supabase project and branch source. No production writes or payments were performed.

## Executive summary

The live public.release_shubhcoins_for_order(uuid) function is executable by the authenticated role and releases redeemed ShubhCoins whenever the order's database payment_status is not exactly the case-sensitive string 'Paid', provided a redeem ledger entry exists and a prior coin_release ledger entry does not. It does not inspect the payments table, does not require an authoritative terminal payment outcome, and does not lock the order row before deciding. The browser currently invokes this function on Razorpay modal dismissal, payment.failed, and verification/catch errors.

This creates a confirmed payment-state race: if Razorpay has captured a payment but the database order has not yet been marked Paid (for example, provider capture succeeds but verification/DB update is delayed or fails), a browser error/dismissal can release the redeemed coins. If the payment later reconciles to Paid, the customer may retain the purchased order while also receiving the redeemed coins back. The precise exploitability depends on timing and the remaining checkout/payment paths, but the invariant violation is supported by the inspected code.

## Evidence gathered

### Live database function
- Function: public.release_shubhcoins_for_order(p_order_id uuid)
- SECURITY DEFINER: true
- Function setting: search_path=public
- Effective routine privileges reported by information_schema.routine_privileges include EXECUTE for authenticated and service_role (and postgres).
- Body checks auth.uid() is non-null, loads an order matching both p_order_id and auth.uid(), and returns false only when payment_status = 'Paid'.
- It then locks a matching redeem ledger row, checks for an existing coin_release ledger row, locks the wallet, credits abs(redeem amount), updates lifetime_spent, writes a coin_release ledger entry and returns true.
- The function does not query public.payments, does not verify gateway status, does not require order/payment status to be a normalized terminal state such as failed/cancelled/expired, and does not SELECT the order FOR UPDATE before making the release decision.
- It sets search_path to public instead of an empty path with schema-qualified names.

### Live browser checkout flow
- customer/customer-app.js calls releaseShubhCoinsForOrder from payment verification catch, Razorpay modal dismissal, payment.failed, and an outer checkout catch.
- releaseShubhCoinsForOrder directly calls sb.rpc("release_shubhcoins_for_order", {p_order_id: orderId}) with the signed-in user's client.
- The browser cannot authoritatively establish that the provider did not capture a payment merely because the modal closed, a callback said failed, or a verification request failed.

### Related state and schema facts
- The live payments table has status, gateway_order_id, gateway_payment_id, amount and currency columns.
- The live Orders table has payment_status and customer_id.
- The existing cancel_unpaid_order routine locks the order row and permits deletion only for pending/failed/cancelled statuses, but this is not equivalent to safe ShubhCoins release and must not be used as a substitute for provider reconciliation.
- Supabase Security Advisor also reports the release function as an authenticated-callable SECURITY DEFINER routine.

## Severity and boundaries

Severity: HIGH — financial integrity / business logic race.

This is not a claim that every authenticated SECURITY DEFINER function is vulnerable, nor proof of a currently exploited incident. The issue is the mismatch between a browser-triggered release and a database decision based solely on a possibly stale payment_status field. No other customer's records were accessed, no balance was changed, and no adversarial live call was executed.

## Required safe remediation design (not applied)

1. Remove browser authority to release coins directly. The customer client must not call the release RPC; the UI may request a server-side reconciliation only.
2. Implement a trusted Edge Function recovery action that authenticates the caller and verifies order ownership, then queries Razorpay using server-held credentials for the exact gateway order and all associated payment attempts.
3. Fail closed for captured, authorized, created, pending, processing, unknown, timeout, provider API error, mismatched amount/currency, or incomplete provider history. Do not release on a browser callback alone.
4. Release only after the server establishes a terminal, non-captured outcome according to a documented provider-state policy, including handling late/out-of-order callbacks. A pending attempt should keep coins reserved until safely reconciled or the gateway order is conclusively closed/expired with no captured payment.
5. Move the actual release into a narrowly granted internal database routine callable only by service_role; require an explicit server-generated reconciliation decision/record and atomically lock the order, payment rows, redeem ledger row, and wallet before the one-time credit.
6. Enforce idempotency with a unique ledger invariant for the release event per order and a transaction that changes the release state and wallet/ledger together. Repeated requests must have no additional balance effect.
7. Ensure the payment-success transition refuses to finalize inconsistently if a release already occurred; send the case to reconciliation rather than silently allowing both a paid order and a released coin redemption.
8. Pin SECURITY DEFINER search_path to empty and schema-qualify all objects in the replacement routine. Revoke authenticated/PUBLIC execute only in the same coordinated release that removes the direct browser RPC call; doing so alone would break the current frontend flow.
9. Build an isolated synthetic test environment and prove: captured payment + browser error never releases; unknown/pending provider state never releases; provider API timeout never releases; duplicate release has one ledger event and one balance credit; concurrent release/payment-success serializes safely; late capture after attempted release enters reconciliation; different customer cannot request another order's release; malformed/mismatched order, amount, and currency fail closed.
10. Verify the exact deployed Edge Function version and run end-to-end/concurrency tests before any production rollout.

## Acceptance criteria

- No customer-facing browser path can directly credit back ShubhCoins.
- The trusted server reconciles provider state; unknown is not treated as failed.
- Wallet balance and ledger update atomically and at most once.
- A captured payment can never coexist with an automatic coin release for the same redemption.
- The release routine has least-privilege grants and a hardened search_path.
- Tests demonstrate the invariants under concurrent and out-of-order events.

## Change control

This is a finding and remediation plan only. No production SQL, grants, Auth settings, live Edge Functions, deployment, PR merge, or real payment was changed. The existing checkout flow must not be modified piecemeal; frontend and server/database changes must ship as a coordinated, tested unit.
