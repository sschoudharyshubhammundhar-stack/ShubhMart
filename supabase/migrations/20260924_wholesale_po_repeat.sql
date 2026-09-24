create table if not exists public.wholesale_purchase_orders(
 id uuid primary key default gen_random_uuid(),
 wholesale_order_id uuid not null references public.wholesale_orders(id) on delete restrict,
 buyer_id uuid not null references auth.users(id) on delete restrict,
 po_number text not null,
 notes text,
 status text not null default 'Issued' check(status in ('Draft','Issued','Accepted','Rejected','Closed')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(buyer_id,po_number)
);
create index if not exists wholesale_po_buyer_created_idx on public.wholesale_purchase_orders(buyer_id,created_at desc);
create index if not exists wholesale_po_order_idx on public.wholesale_purchase_orders(wholesale_order_id);
alter table public.wholesale_purchase_orders enable row level security;
drop policy if exists "buyers_view_own_wholesale_po" on public.wholesale_purchase_orders;
create policy "buyers_view_own_wholesale_po" on public.wholesale_purchase_orders for select to authenticated using((select auth.uid())=buyer_id);
drop policy if exists "sellers_view_wholesale_po" on public.wholesale_purchase_orders;
create policy "sellers_view_wholesale_po" on public.wholesale_purchase_orders for select to authenticated using(wholesale_order_id in(select id from public.wholesale_orders where seller_id in(select id from public."Sellers" where user_id=(select auth.uid()))));
drop policy if exists "admin_all_wholesale_po" on public.wholesale_purchase_orders;
create policy "admin_all_wholesale_po" on public.wholesale_purchase_orders for all to authenticated using((select private.is_admin())) with check((select private.is_admin()));

create or replace function public.create_wholesale_purchase_order(p_wholesale_order_id uuid,p_po_number text,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare wid uuid; pid uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select id into wid from public.wholesale_orders where id=p_wholesale_order_id and buyer_id=auth.uid() and status not in('Cancelled') for update;
 if wid is null then raise exception 'Wholesale order not found'; end if;
 if nullif(trim(p_po_number),'') is null then raise exception 'PO number required'; end if;
 insert into public.wholesale_purchase_orders(wholesale_order_id,buyer_id,po_number,notes)
 values(wid,auth.uid(),trim(p_po_number),nullif(trim(p_notes),''))
 returning id into pid;
 return pid;
exception when unique_violation then
 raise exception 'PO number already used for this buyer';
end $$;
revoke all on function public.create_wholesale_purchase_order(uuid,text,text) from public,anon;
grant execute on function public.create_wholesale_purchase_order(uuid,text,text) to authenticated;

create or replace function public.repeat_wholesale_order(p_wholesale_order_id uuid,p_address_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare w record; addr record; wid uuid; oid uuid; total numeric; shipping text; cname text; cphone text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into w from public.wholesale_orders where id=p_wholesale_order_id and buyer_id=auth.uid() and status not in('Cancelled') ;
 if not found then raise exception 'Wholesale order not found'; end if;
 select * into addr from public.addresses where id=p_address_id and customer_id=auth.uid();
 if not found then raise exception 'Valid delivery address required'; end if;
 if not exists(select 1 from public.products where id=w.product_id and status='Active') then raise exception 'Product no longer available'; end if;
 total:=w.quantity*w.unit_price;
 select coalesce(full_name,'Customer') into cname from public.profiles where id=auth.uid();
 select coalesce(phone,'') into cphone from auth.users where id=auth.uid();
 shipping:=concat_ws(', ',addr.name,addr.house_shop,addr.area,addr.city,addr.state,addr.pincode);
 insert into public."Orders"(customer_name,customer_phone,total_amount,payment_method,order_status,shipping_address,seller_id,payment_status,customer_id,address_id,item_total,currency)
 values(cname,cphone,total,'cod','Pending',shipping,w.seller_id,'Pending',auth.uid(),p_address_id,total,'INR') returning id into oid;
 insert into public."Order_items"(order_id,product_id,quantity,unit_price,total_price) values(oid,w.product_id,w.quantity,w.unit_price,total);
 insert into public.wholesale_orders(inquiry_id,order_id,buyer_id,seller_id,product_id,quantity,unit_price,total_amount,status)
 values(w.inquiry_id,oid,auth.uid(),w.seller_id,w.product_id,w.quantity,w.unit_price,total,'Order Created') returning id into wid;
 return wid;
end $$;
revoke all on function public.repeat_wholesale_order(uuid,uuid) from public,anon;
grant execute on function public.repeat_wholesale_order(uuid,uuid) to authenticated;