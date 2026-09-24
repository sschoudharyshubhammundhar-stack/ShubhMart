create index if not exists orders_status_created_idx on public."Orders"(order_status,created_at desc);
create index if not exists orders_payment_status_created_idx on public."Orders"(payment_status,created_at desc);
create index if not exists refunds_status_created_idx on public.refunds(status,created_at desc);
create index if not exists returns_status_created_idx on public.returns(status,created_at desc);
create index if not exists buyer_protection_status_created_idx on public.buyer_protection_claims(status,created_at desc);

create or replace function public.admin_update_order_status(p_order_id uuid,p_status text,p_note text default null)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Pending','Confirmed','Processing','Packed','Dispatched','Delivered','Cancelled') then raise exception 'Invalid order status'; end if;
 update public."Orders" set order_status=p_status where id=p_order_id;
 if not found then raise exception 'Order not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata)
 values(auth.uid(),'order_status','order',p_order_id,jsonb_build_object('status',p_status,'note',nullif(trim(coalesce(p_note,'')),'')));
 return true;
end $$;
revoke all on function public.admin_update_order_status(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_update_order_status(uuid,text,text) to authenticated;

create or replace function public.admin_update_buyer_protection_claim(p_claim_id uuid,p_status text,p_resolution text default null)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Under Review','Approved','Resolved','Rejected') then raise exception 'Invalid claim status'; end if;
 update public.buyer_protection_claims set status=p_status,updated_at=now(),resolution=case when p_status='Resolved' then nullif(trim(coalesce(p_resolution,'')),'') else resolution end where id=p_claim_id;
 if not found then raise exception 'Claim not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata)
 values(auth.uid(),'buyer_protection_status','buyer_protection_claim',p_claim_id,jsonb_build_object('status',p_status,'resolution',nullif(trim(coalesce(p_resolution,'')),'')));
 return true;
end $$;
revoke all on function public.admin_update_buyer_protection_claim(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_update_buyer_protection_claim(uuid,text,text) to authenticated;