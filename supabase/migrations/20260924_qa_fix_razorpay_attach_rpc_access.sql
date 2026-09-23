-- Checkout QA fix: Razorpay Edge Function calls this RPC after verifying
-- the signed-in customer owns the order. The function itself remains
-- SECURITY DEFINER and validates auth.uid() before updating payment metadata.
revoke execute on function public.attach_razorpay_order(uuid,text,text) from public, anon;
grant execute on function public.attach_razorpay_order(uuid,text,text) to authenticated;
