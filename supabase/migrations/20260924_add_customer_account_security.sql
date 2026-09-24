create index if not exists addresses_customer_created_idx on public.addresses(customer_id,created_at desc);
create index if not exists addresses_customer_default_idx on public.addresses(customer_id,is_default);
alter table public.addresses enable row level security;
drop policy if exists addresses_select_own on public.addresses;
drop policy if exists addresses_insert_own on public.addresses;
drop policy if exists addresses_update_own on public.addresses;
drop policy if exists addresses_delete_own on public.addresses;
create policy addresses_select_own on public.addresses for select to authenticated using(customer_id=(select auth.uid()));
create policy addresses_insert_own on public.addresses for insert to authenticated with check(customer_id=(select auth.uid()));
create policy addresses_update_own on public.addresses for update to authenticated using(customer_id=(select auth.uid())) with check(customer_id=(select auth.uid()));
create policy addresses_delete_own on public.addresses for delete to authenticated using(customer_id=(select auth.uid()));
create or replace function public.set_default_address(p_address_id uuid) returns boolean language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from public.addresses where id=p_address_id and customer_id=auth.uid()) then raise exception 'Address not found'; end if;
 update public.addresses set is_default=false,updated_at=now() where customer_id=auth.uid();
 update public.addresses set is_default=true,updated_at=now() where id=p_address_id and customer_id=auth.uid();
 return true;
end $$;
revoke all on function public.set_default_address(uuid) from public,anon;
grant execute on function public.set_default_address(uuid) to authenticated;
create or replace function public.delete_customer_address(p_address_id uuid) returns boolean language plpgsql security definer set search_path=public as $$
declare was_default boolean;
begin
 select is_default into was_default from public.addresses where id=p_address_id and customer_id=auth.uid();
 if not found then raise exception 'Address not found'; end if;
 delete from public.addresses where id=p_address_id and customer_id=auth.uid();
 if was_default then update public.addresses set is_default=true,updated_at=now() where id=(select id from public.addresses where customer_id=auth.uid() order by created_at desc limit 1); end if;
 return true;
end $$;
revoke all on function public.delete_customer_address(uuid) from public,anon;
grant execute on function public.delete_customer_address(uuid) to authenticated;
create table if not exists public.customer_account_audit (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id) on delete cascade,
 action text not null check(action in ('profile_update','address_add','address_update','address_delete','default_address_change','password_reset_requested')),
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists customer_account_audit_customer_created_idx on public.customer_account_audit(customer_id,created_at desc);
alter table public.customer_account_audit enable row level security;
create policy "customers view own account audit" on public.customer_account_audit for select to authenticated using(customer_id=(select auth.uid()));
create or replace function public.record_customer_account_audit(p_action text,p_metadata jsonb default '{}'::jsonb) returns uuid language plpgsql security invoker set search_path=public as $$
declare rid uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_action not in ('profile_update','address_add','address_update','address_delete','default_address_change','password_reset_requested') then raise exception 'Invalid audit action'; end if;
 insert into public.customer_account_audit(customer_id,action,metadata) values(auth.uid(),p_action,coalesce(p_metadata,'{}'::jsonb)) returning id into rid; return rid;
end $$;
revoke all on function public.record_customer_account_audit(text,jsonb) from public,anon;
grant execute on function public.record_customer_account_audit(text,jsonb) to authenticated;