create index if not exists commissions_seller_status_created_idx on public.commissions(seller_id,status,created_at desc);
create index if not exists payouts_seller_status_requested_idx on public.payouts(seller_id,status,requested_at desc);

create or replace function public.request_seller_payout(p_amount numeric)
returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid; pid uuid; available numeric;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select id into sid from public."Sellers" where user_id=auth.uid() and status='Approved';
 if sid is null then raise exception 'Approved seller access required'; end if;
 if p_amount is null or p_amount <= 0 then raise exception 'Invalid payout amount'; end if;
 select coalesce(sum(case when status in ('Available','Approved') then seller_earning else 0 end),0)
      - coalesce((select sum(amount) from public.payouts where seller_id=sid and status in ('Pending','Processing','Paid')),0)
 into available from public.commissions where seller_id=sid;
 if p_amount > available then raise exception 'Payout amount exceeds available balance'; end if;
 insert into public.payouts(seller_id,amount,status) values(sid,p_amount,'Pending') returning id into pid;
 insert into public.seller_account_audit(seller_id,action,metadata) values(sid,'payout_request',jsonb_build_object('payout_id',pid,'amount',p_amount));
 return pid;
end $$;
revoke all on function public.request_seller_payout(numeric) from public,anon;
grant execute on function public.request_seller_payout(numeric) to authenticated;