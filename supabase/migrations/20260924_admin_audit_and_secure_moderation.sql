create table if not exists public.admin_audit_logs(
 id uuid primary key default gen_random_uuid(),
 admin_id uuid not null references auth.users(id) on delete restrict,
 action text not null,
 entity_type text,
 entity_id uuid,
 metadata jsonb,
 created_at timestamptz not null default now()
);
create index if not exists admin_audit_created_idx on public.admin_audit_logs(created_at desc);
create index if not exists admin_audit_entity_idx on public.admin_audit_logs(entity_type,entity_id,created_at desc);
alter table public.admin_audit_logs enable row level security;
drop policy if exists "admins_view_audit_logs" on public.admin_audit_logs;
create policy "admins_view_audit_logs" on public.admin_audit_logs for select to authenticated using((select private.is_admin()));
create or replace function public.admin_set_seller_status(p_seller_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Approved','Rejected','Suspended','Pending') then raise exception 'Invalid seller status'; end if;
 update public."Sellers" set status=p_status,approved_at=case when p_status='Approved' then now() else null end,rejection_reason=case when p_status='Rejected' then 'Rejected by admin' else null end where id=p_seller_id;
 if not found then raise exception 'Seller not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata) values(auth.uid(),'seller_status', 'seller',p_seller_id,jsonb_build_object('status',p_status));
 return true;
end $$;
revoke all on function public.admin_set_seller_status(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_set_seller_status(uuid,text) to authenticated;
create or replace function public.admin_set_product_status(p_product_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Active','Rejected','Pending') then raise exception 'Invalid product status'; end if;
 update public.products set status=p_status,approved_at=case when p_status='Active' then now() else null end,rejection_reason=case when p_status='Rejected' then 'Rejected by admin' else null end where id=p_product_id;
 if not found then raise exception 'Product not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata) values(auth.uid(),'product_status','product',p_product_id,jsonb_build_object('status',p_status));
 return true;
end $$;
revoke all on function public.admin_set_product_status(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_set_product_status(uuid,text) to authenticated;
create or replace function public.admin_set_wholesale_pricing_status(p_pricing_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Active','Rejected','Pending') then raise exception 'Invalid pricing status'; end if;
 update public.wholesale_pricing set status=p_status,updated_at=now() where id=p_pricing_id;
 if not found then raise exception 'Wholesale pricing not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata) values(auth.uid(),'wholesale_pricing_status','wholesale_pricing',p_pricing_id,jsonb_build_object('status',p_status));
 return true;
end $$;
revoke all on function public.admin_set_wholesale_pricing_status(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_set_wholesale_pricing_status(uuid,text) to authenticated;