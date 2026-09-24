-- ShubhMart Phase 2: customer cancel/return/refund + buyer protection
create table if not exists public.refunds (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public."Orders"(id) on delete cascade,
 return_id uuid references public.returns(id) on delete set null,
 customer_id uuid not null references auth.users(id) on delete cascade,
 amount numeric not null check(amount>=0),
 method text not null default 'Original Payment' check(method in ('Original Payment','COD Refund','ShubhCoins','Manual')),
 status text not null default 'Pending' check(status in ('Pending','Processing','Completed','Failed','Cancelled')),
 gateway text,
 gateway_ref text,
 notes text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(order_id,return_id)
);
create unique index if not exists refunds_order_cancel_uidx on public.refunds(order_id) where return_id is null;
create index if not exists refunds_customer_created_idx on public.refunds(customer_id,created_at desc);
create index if not exists refunds_order_idx on public.refunds(order_id);

create table if not exists public.buyer_protection_claims (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public."Orders"(id) on delete cascade,
 customer_id uuid not null references auth.users(id) on delete cascade,
 reason text not null,
 description text,
 status text not null default 'Open' check(status in ('Open','Under Review','Approved','Rejected','Resolved','Cancelled')),
 resolution text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists buyer_protection_customer_created_idx on public.buyer_protection_claims(customer_id,created_at desc);
create index if not exists buyer_protection_order_idx on public.buyer_protection_claims(order_id);

alter table public.returns add column if not exists return_type text not null default 'Return' check(return_type in ('Return','Exchange'));
alter table public.returns add column if not exists requested_at timestamptz not null default now();
alter table public.returns add column if not exists decision_at timestamptz;
alter table public.returns add column if not exists pickup_status text not null default 'Pending' check(pickup_status in ('Pending','Scheduled','Picked Up','Failed','Completed'));
alter table public.returns add column if not exists refund_status text not null default 'Not Requested' check(refund_status in ('Not Requested','Pending','Processing','Completed','Failed'));
alter table public.returns add column if not exists item_count integer not null default 1 check(item_count>0);
alter table public.returns add column if not exists reason_code text;
alter table public.returns add column if not exists customer_note text;

alter table public.returns enable row level security;
alter table public.refunds enable row level security;
alter table public.buyer_protection_claims enable row level security;

drop policy if exists customer_insert_returns on public.returns;
drop policy if exists customer_update_pending_returns on public.returns;
drop policy if exists customer_own_returns on public.returns;
create policy customer_own_returns on public.returns for select to authenticated using(customer_id=(select auth.uid()));
drop policy if exists admin_all_returns on public.returns;
create policy admin_all_returns on public.returns for all to authenticated using((select private.is_admin())) with check((select private.is_admin()));

drop policy if exists customer_own_refunds on public.refunds;
create policy customer_own_refunds on public.refunds for select to authenticated using(customer_id=(select auth.uid()));
drop policy if exists admin_all_refunds on public.refunds;
create policy admin_all_refunds on public.refunds for all to authenticated using((select private.is_admin())) with check((select private.is_admin()));

drop policy if exists customer_own_buyer_claims on public.buyer_protection_claims;
create policy customer_own_buyer_claims on public.buyer_protection_claims for select to authenticated using(customer_id=(select auth.uid()));
drop policy if exists customer_insert_buyer_claims on public.buyer_protection_claims;
drop policy if exists customer_update_open_buyer_claims on public.buyer_protection_claims;
drop policy if exists admin_all_buyer_claims on public.buyer_protection_claims;
create policy admin_all_buyer_claims on public.buyer_protection_claims for all to authenticated using((select private.is_admin())) with check((select private.is_admin()));

create or replace function public.cancel_customer_order(p_order_id uuid,p_reason text default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare o public."Orders"%rowtype;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into o from public."Orders" where id=p_order_id and customer_id=auth.uid() for update;
 if not found then raise exception 'Order not found'; end if;
 if o.order_status not in ('Pending','Confirmed') then raise exception 'Order cannot be cancelled at this stage'; end if;
 if lower(coalesce(o.payment_status,'pending'))='paid' then
   update public."Orders" set order_status='Cancelled' where id=p_order_id;
   insert into public.refunds(order_id,customer_id,amount,method,status,notes)
   values(p_order_id,o.customer_id,greatest(0,o.total_amount),'Original Payment','Pending',left(coalesce(p_reason,'Customer cancellation'),500))
   on conflict (order_id) where return_id is null do nothing;
 else
   update public."Orders" set order_status='Cancelled',payment_status=case when lower(coalesce(o.payment_status,'pending'))='failed' then 'failed' else 'cancelled' end where id=p_order_id;
   perform public.release_shubhcoins_for_order(p_order_id);
 end if;
 return true;
end $$;
revoke all on function public.cancel_customer_order(uuid,text) from public,anon;
grant execute on function public.cancel_customer_order(uuid,text) to authenticated;

create or replace function public.request_order_return(p_order_id uuid,p_reason_code text,p_reason text default null,p_return_type text default 'Return')
returns uuid language plpgsql security definer set search_path=public as $$
declare o public."Orders"%rowtype; rid uuid; delivered_at timestamptz;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_return_type not in ('Return','Exchange') then raise exception 'Invalid return type'; end if;
 select * into o from public."Orders" where id=p_order_id and customer_id=auth.uid();
 if not found then raise exception 'Order not found'; end if;
 if o.order_status <> 'Delivered' then raise exception 'Return is available only after delivery'; end if;
 select s.delivered_at into delivered_at from public.shipments s where s.order_id=p_order_id limit 1;
 if coalesce(delivered_at,o.created_at) < now()-interval '7 days' then raise exception 'Return window has expired'; end if;
 if exists(select 1 from public.returns where order_id=p_order_id and status not in ('Rejected','Cancelled')) then raise exception 'A return request already exists'; end if;
 insert into public.returns(order_id,customer_id,reason,status,refund_amount,return_type,reason_code,customer_note,requested_at)
 values(o.id,o.customer_id,left(coalesce(p_reason,p_reason_code),1000),'Requested',greatest(0,o.total_amount),p_return_type,left(p_reason_code,100),left(p_reason,1000),now())
 returning id into rid;
 return rid;
end $$;
revoke all on function public.request_order_return(uuid,text,text,text) from public,anon;
grant execute on function public.request_order_return(uuid,text,text,text) to authenticated;

create or replace function public.request_buyer_protection(p_order_id uuid,p_reason text,p_description text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare oid uuid; cid uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Protection reason required'; end if;
 select id into oid from public."Orders" where id=p_order_id and customer_id=auth.uid();
 if oid is null then raise exception 'Order not found'; end if;
 if exists(select 1 from public.buyer_protection_claims where order_id=oid and status not in ('Rejected','Resolved','Cancelled')) then raise exception 'An active protection claim already exists'; end if;
 insert into public.buyer_protection_claims(order_id,customer_id,reason,description)
 values(oid,auth.uid(),left(trim(p_reason),200),left(coalesce(p_description,''),2000))
 returning id into cid;
 return cid;
end $$;
revoke all on function public.request_buyer_protection(uuid,text,text) from public,anon;
grant execute on function public.request_buyer_protection(uuid,text,text) to authenticated;

create or replace function public.admin_finalize_refund(p_refund_id uuid,p_gateway_ref text,p_notes text default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare r public.refunds%rowtype; o public."Orders"%rowtype; w public.shubhcoins_wallets%rowtype; coin_amount bigint;
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if nullif(trim(coalesce(p_gateway_ref,'')),'') is null then raise exception 'Refund transaction reference required'; end if;
 select * into r from public.refunds where id=p_refund_id for update;
 if not found then raise exception 'Refund not found'; end if;
 if r.status='Completed' then return true; end if;
 select * into o from public."Orders" where id=r.order_id for update;
 update public.refunds set status='Completed',gateway_ref=left(trim(p_gateway_ref),200),notes=left(coalesce(p_notes,notes),1000),updated_at=now() where id=r.id;
 update public."Orders" set payment_status='refunded',order_status=case when order_status='Cancelled' then order_status else 'Returned' end where id=o.id;
 update public.returns set refund_status='Completed',status='Completed',decision_at=coalesce(decision_at,now()),updated_at=now() where id=r.return_id;
 select amount into coin_amount from public.shubhcoins_ledger where customer_id=o.customer_id and type='redeem' and reference_id=o.id::text limit 1;
 if coin_amount is not null and coin_amount>0 and not exists(select 1 from public.shubhcoins_ledger where customer_id=o.customer_id and type='coin_release' and reference_id=o.id::text) then
   insert into public.shubhcoins_wallets(customer_id) values(o.customer_id) on conflict(customer_id) do nothing;
   select * into w from public.shubhcoins_wallets where customer_id=o.customer_id for update;
   update public.shubhcoins_wallets set balance=balance+coin_amount,lifetime_spent=greatest(0,lifetime_spent-coin_amount),updated_at=now() where customer_id=o.customer_id;
   insert into public.shubhcoins_ledger(customer_id,amount,balance_after,type,reference_id,note) values(o.customer_id,coin_amount,w.balance+coin_amount,'coin_release',o.id::text,'Refund completed — ShubhCoins restored');
 end if;
 return true;
end $$;
revoke all on function public.admin_finalize_refund(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_finalize_refund(uuid,text,text) to authenticated;

create or replace function public.admin_update_return_status(p_return_id uuid,p_status text,p_refund_amount numeric default null,p_note text default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare r public.returns%rowtype; amt numeric;
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Approved','Rejected','Pickup Scheduled','Pickup Completed','Refund Pending','Cancelled') then raise exception 'Invalid return status'; end if;
 select * into r from public.returns where id=p_return_id for update;
 if not found then raise exception 'Return not found'; end if;
 if r.status in ('Completed','Rejected','Cancelled') then raise exception 'Return already closed'; end if;
 if p_status='Approved' then
   amt=greatest(0,coalesce(p_refund_amount,r.refund_amount));
   update public.returns set status='Approved',refund_amount=amt,decision_at=now(),updated_at=now(),notes=left(coalesce(p_note,notes),1000) where id=r.id;
 elsif p_status='Rejected' then
   update public.returns set status='Rejected',decision_at=now(),updated_at=now(),notes=left(coalesce(p_note,notes),1000) where id=r.id;
 elsif p_status='Pickup Scheduled' then
   update public.returns set status=p_status,pickup_status='Scheduled',updated_at=now() where id=r.id;
 elsif p_status='Pickup Completed' then
   update public.returns set status=p_status,pickup_status='Completed',updated_at=now() where id=r.id;
 elsif p_status='Refund Pending' then
   amt=greatest(0,coalesce(p_refund_amount,r.refund_amount));
   insert into public.refunds(order_id,return_id,customer_id,amount,method,status,notes)
   values(r.order_id,r.id,r.customer_id,amt,'Original Payment','Pending',left(coalesce(p_note,'Refund pending gateway processing'),1000))
   on conflict(order_id,return_id) do update set amount=excluded.amount,notes=excluded.notes,updated_at=now();
   update public.returns set status='Refund Pending',refund_amount=amt,refund_status='Pending',updated_at=now() where id=r.id;
 else
   update public.returns set status=p_status,updated_at=now();
 end if;
 return true;
end $$;
revoke all on function public.admin_update_return_status(uuid,text,numeric,text) from public,anon,authenticated;
grant execute on function public.admin_update_return_status(uuid,text,numeric,text) to authenticated;