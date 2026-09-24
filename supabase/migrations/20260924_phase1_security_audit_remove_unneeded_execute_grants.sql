-- Phase 1 production security audit: remove unnecessary API execution grants.
revoke execute on function public.attach_razorpay_order(uuid,text,text) from public, anon, authenticated;
revoke execute on function public.ensure_shubhcoins_wallet() from anon;
