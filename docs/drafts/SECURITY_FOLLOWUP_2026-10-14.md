# Follow-up Security Findings — 2026-10-14

## Correction to payment verification notes
The current branch version of the Razorpay Edge Function fetches the provider payment record and checks payment ID, order ID, amount in paise, INR currency and captured status before asking the privileged database function to mark the order paid. An earlier report paragraph described an older source snapshot. This branch evidence does not prove the live deployed Edge Function has been updated.

## Additional database integrity controls prepared in draft
- The read-only index inventory found no unique index on payments.gateway_payment_id. The payment migration candidate now proposes a partial unique index for non-null values, preceded by a duplicate preflight query. Existing duplicates must be reconciled before applying it.
- The payment attachment candidate now permits only an empty gateway order ID or a retry using the same ID, and rejects already-paid orders.
- SECURITY DEFINER functions in the payment candidate now pin an empty search_path and qualify application objects.

## Still blocked from release
- End-to-end database-backed checkout idempotency.
- Provider-order creation idempotency and orphan-order reconciliation.
- Refund cumulative limits and partial-refund state transitions.
- Runtime SQL compilation, isolated integration and concurrency tests.
- Verification that the live deployed Edge Function matches this branch.

No production SQL, Edge Function, payment, Auth setting, or deployment was changed.