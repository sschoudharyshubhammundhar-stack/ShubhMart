create table if not exists public.wholesale_orders(
 id uuid primary key default gen_random_uuid(),
 inquiry_id uuid not null references public.wholesale_inquiries(id) on delete restrict,
 order_id uuid references public."Orders"(id) on delete set null,
 buyer_id uuid not null references auth.users(id) on delete restrict,
 seller_id uuid not null references public."Sellers"(id) on delete restrict,
 product_id uuid not null references public.products(id) on delete restrict,
 quantity integer not null check(quantity>0),
 unit_price numeric not null check(unit_price>0),
 total_amount numeric not null check(total_amount>0),
 status text not null default 'Order Created' check(status in ('Order Created','Payment Pending','Confirmed','Processing','Packed','Dispatched','Delivered','Cancelled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists wholesale_orders_inquiry_uidx on public.wholesale_orders(inquiry_id);
create index if not exists wholesale_orders_buyer_created_idx on public.wholesale_orders(buyer_id,created_at desc);
create index if not exists wholesale_orders_seller_created_idx on public.wholesale_orders(seller_id,created_at desc);
alter table public.wholesale_orders enable row level security;
drop policy if exists "buyers_view_own_wholesale_orders" on public.wholesale_orders;
create policy "buyers_view_own_wholesale_orders" on public.wholesale_orders for select to authenticated using((select auth.uid())=buyer_id);
drop policy if exists "sellers_view_own_wholesale_orders" on public.wholesale_orders;
create policy "sellers_view_own_wholesale_orders" on public.wholesale_orders for select to authenticated using(seller_id in(select id from public."Sellers" where user_id=(select auth.uid())));
drop policy if exists "admin_all_wholesale_orders" on public.wholesale_orders;
create policy "admin_all_wholesale_orders" on public.wholesale_orders for all to authenticated using((select private.is_admin())) with check((select private.is_admin()));
create or replace function public.create_wholesale_order_from_quote(p_inquiry_id uuid,p_address_id uuid,p_payment_method text default 'cod')
returns uuid language plpgsql security definer set search_path=public as $$
declare q record; addr record; oid uuid; wid uuid; total numeric; cust_name text; cust_phone text; shipping text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into q from public.wholesale_inquiries where id=p_inquiry_id and buyer_id=auth.uid() and status='Accepted' for update;
 if not found then raise exception 'Accepted wholesale quote required'; end if;
 if q.quoted_price is null or q.quoted_price<=0 then raise exception 'Valid seller quote required'; end if;
 if exists(select 1 from public.wholesale_orders where inquiry_id=q.id) then select id into wid from public.wholesale_orders where inquiry_id=q.id; return wid; end if;
 select * into addr from public.addresses where id=p_address_id and customer_id=auth.uid();
 if not found then raise exception 'Valid delivery address required'; end if;
 select coalesce(full_name,'Customer') into cust_name from public.profiles where id=auth.uid();
 select coalesce(phone,'') into cust_phone from auth.users where id=auth.uid();
 shipping:=concat_ws(', ',addr.name,addr.house_shop,addr.area,addr.city,addr.state,addr.pincode);
 total:=q.quantity*q.quoted_price;
 insert into public."Orders"(customer_name,customer_phone,total_amount,payment_method,order_status,shipping_address,seller_id,payment_status,customer_id,address_id,item_total,currency)
 values(cust_name,cust_phone,total,coalesce(nullif(p_payment_method,''),'cod'),'Pending',shipping,q.seller_id,'Pending',auth.uid(),p_address_id,total,'INR') returning id into oid;
 insert into public."Order_items"(order_id,product_id,quantity,unit_price,total_price) values(oid,q.product_id,q.quantity,q.quoted_price,total);
 insert into public.wholesale_orders(inquiry_id,order_id,buyer_id,seller_id,product_id,quantity,unit_price,total_amount)
 values(q.id,oid,auth.uid(),q.seller_id,q.product_id,q.quantity,q.quoted_price,total) returning id into wid;
 update public.wholesale_inquiries set updated_at=now() where id=q.id;
 return wid;
end $$;
revoke all on function public.create_wholesale_order_from_quote(uuid,uuid,text) from public,anon;
grant execute on function public.create_wholesale_order_from_quote(uuid,uuid,text) to authenticated;