create index if not exists seller_kyc_seller_status_idx on public.seller_kyc(seller_id,status);
create index if not exists commissions_seller_status_created_idx on public.commissions(seller_id,status,created_at desc);
create index if not exists payouts_seller_requested_idx on public.payouts(seller_id,requested_at desc);

create table if not exists public.seller_account_audit (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public."Sellers"(id) on delete cascade,
 action text not null,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
alter table public.seller_account_audit enable row level security;
drop policy if exists "sellers view own audit" on public.seller_account_audit;
create policy "sellers view own audit" on public.seller_account_audit for select to authenticated
using (seller_id in (select s.id from public."Sellers" s where s.user_id=(select auth.uid())));

create or replace function public.update_seller_profile(p_seller_id uuid,p_seller_name text,p_mobile text,p_shop_name text,p_address text,p_pan text,p_gst text) returns boolean language plpgsql security definer set search_path=public as $$
declare v_user uuid := (select auth.uid());
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from public."Sellers" where id=p_seller_id and user_id=v_user) then raise exception 'Seller access denied'; end if;
 if length(trim(coalesce(p_seller_name,'')))<2 or length(trim(coalesce(p_shop_name,'')))<2 then raise exception 'Seller name and shop name are required'; end if;
 update public."Sellers" set seller_name=trim(p_seller_name),mobile=trim(coalesce(p_mobile,'')),shop_name=trim(p_shop_name),address=trim(coalesce(p_address,'')),pan=upper(trim(coalesce(p_pan,''))),gst_number=upper(trim(coalesce(p_gst,''))),updated_at=now() where id=p_seller_id;
 insert into public.seller_account_audit(seller_id,action,metadata) values(p_seller_id,'profile_update',jsonb_build_object('shop_name',trim(p_shop_name),'gst_present',length(trim(coalesce(p_gst,'')))>0));
 return true;
end $$;

create or replace function public.update_seller_product_stock(p_product_id uuid,p_stock integer) returns boolean language plpgsql security definer set search_path=public as $$
declare v_seller uuid; v_user uuid := (select auth.uid());
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if p_stock is null or p_stock<0 then raise exception 'Invalid stock'; end if;
 select s.id into v_seller from public."Sellers" s where s.user_id=v_user and s.status='Approved' limit 1;
 if v_seller is null then raise exception 'Approved seller account required'; end if;
 if not exists(select 1 from public.products where id=p_product_id and seller_id=v_seller) then raise exception 'Product access denied'; end if;
 update public.products set stock=p_stock where id=p_product_id and seller_id=v_seller;
 insert into public.seller_account_audit(seller_id,action,metadata) values(v_seller,'inventory_update',jsonb_build_object('product_id',p_product_id,'stock',p_stock));
 return true;
end $$;

create or replace function public.update_seller_order_status(p_order_id uuid,p_status text) returns boolean language plpgsql security definer set search_path=public as $$
declare v_seller uuid; v_old text; v_user uuid := (select auth.uid());
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select s.id into v_seller from public."Sellers" s where s.user_id=v_user and s.status='Approved' limit 1;
 if v_seller is null then raise exception 'Approved seller account required'; end if;
 select order_status into v_old from public."Orders" where id=p_order_id and seller_id=v_seller for update;
 if v_old is null then raise exception 'Order not found'; end if;
 if p_status not in ('Confirmed','Processing','Packed','Dispatched','Cancelled') then raise exception 'Invalid seller order status'; end if;
 if (v_old='Pending' and p_status not in ('Confirmed','Cancelled')) or (v_old='Confirmed' and p_status not in ('Processing','Cancelled')) or (v_old='Processing' and p_status not in ('Packed','Cancelled')) or (v_old='Packed' and p_status not in ('Dispatched')) or (v_old='Dispatched') then raise exception 'Invalid order status transition'; end if;
 update public."Orders" set order_status=p_status where id=p_order_id and seller_id=v_seller;
 insert into public.seller_account_audit(seller_id,action,metadata) values(v_seller,'order_status_update',jsonb_build_object('order_id',p_order_id,'from',v_old,'to',p_status));
 return true;
end $$;

create or replace function public.submit_seller_kyc(p_seller_id uuid,p_document_type text,p_document_number text,p_document_url text) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_user uuid := (select auth.uid());
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from public."Sellers" where id=p_seller_id and user_id=v_user) then raise exception 'Seller access denied'; end if;
 if length(trim(coalesce(p_document_type,'')))<2 or length(trim(coalesce(p_document_number,'')))<4 then raise exception 'KYC document details required'; end if;
 insert into public.seller_kyc(seller_id,document_type,document_number,document_url,status) values(p_seller_id,trim(p_document_type),trim(p_document_number),nullif(trim(coalesce(p_document_url,'')),''),'Pending') returning id into v_id;
 update public."Sellers" set kyc_status='Pending',updated_at=now() where id=p_seller_id;
 insert into public.seller_account_audit(seller_id,action,metadata) values(p_seller_id,'kyc_submitted',jsonb_build_object('document_type',trim(p_document_type)));
 return v_id;
end $$;

revoke all on function public.update_seller_profile(uuid,text,text,text,text,text,text) from public,anon;
grant execute on function public.update_seller_profile(uuid,text,text,text,text,text,text) to authenticated;
revoke all on function public.update_seller_product_stock(uuid,integer) from public,anon;
grant execute on function public.update_seller_product_stock(uuid,integer) to authenticated;
revoke all on function public.update_seller_order_status(uuid,text) from public,anon;
grant execute on function public.update_seller_order_status(uuid,text) to authenticated;
revoke all on function public.submit_seller_kyc(uuid,text,text,text) from public,anon;
grant execute on function public.submit_seller_kyc(uuid,text,text,text) to authenticated;