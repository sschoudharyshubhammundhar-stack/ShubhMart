create or replace function public.admin_update_seller_payout(p_payout_id uuid,p_status text,p_reference text default null)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin') then raise exception 'Admin access required'; end if;
 if p_status not in ('Processing','Paid','Rejected') then raise exception 'Invalid payout status'; end if;
 if p_status='Paid' and nullif(trim(coalesce(p_reference,'')),'') is null then raise exception 'Payout reference required'; end if;
 update public.payouts set status=p_status,payout_reference=nullif(trim(p_reference),''),paid_at=case when p_status='Paid' then now() else null end where id=p_payout_id and status in ('Pending','Processing');
 if not found then raise exception 'Payout not found or already finalized'; end if;
 return true;
end $$;
revoke all on function public.admin_update_seller_payout(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_update_seller_payout(uuid,text,text) to authenticated;