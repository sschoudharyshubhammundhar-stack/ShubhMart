# ShubhMart Release Checklist

## Locked production rules
- `main` is production/safe branch.
- `development` is for new work.
- Never expose Supabase secret/service-role keys in browser code.
- Customer order creation must go through the protected Edge Function.
- Browser must not directly INSERT into Orders, Order_items, or payments.

## Security verification
- [x] Authenticated role cannot INSERT Orders.
- [x] Authenticated role cannot INSERT Order_items.
- [x] Authenticated role cannot INSERT payments.
- [x] Authenticated role cannot EXECUTE create_order_from_cart.
- [x] service_role can EXECUTE create_order_from_cart.
- [x] Security Advisor no longer reports authenticated SECURITY DEFINER execution warnings.
- [ ] Legacy public.Coustomer table retired only after final dependency review.
- [ ] Leaked Password Protection enabled when available on the project plan.

## Browser/runtime test required before merging PR #3
1. Open the development deployment.
2. Confirm homepage and active products load.
3. Create a new customer account.
4. Confirm login works.
5. Add a product to cart.
6. Save/select a delivery address.
7. Place a COD test order.
8. Confirm the order appears under My Orders.
9. Confirm Razorpay test checkout opens.
10. Use a Razorpay test payment only; confirm server-side verification and order status.
11. Confirm failed/dismissed payment does not falsely mark the order paid.
12. Confirm logout/login preserves the correct customer data.
13. Confirm one customer cannot see another customer's cart, address, or orders.

## Merge gate
PR #3 must remain unmerged until the browser/runtime checks above are completed successfully.
