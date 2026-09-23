-- Secure ShubhCoins redemption at order creation.
-- Rule: 1 coin = ₹1, maximum 20% of item total, and coins are deducted
-- atomically with order creation. Client cannot directly change the wallet.
create or replace function public.create_order_from_cart_with_coins(
  p_customer_id uuid,
  p_address_id uuid,
  p_payment_method text default 'razorpay',
  p_delivery_method text default 'standard',
  p_coupon_code text default '',
  p_shubhcoins bigint default 0
) returns table(order_id uuid,total_amount numeric,coins_redeemed bigint,coin_discount numeric)
language plpgsql
security definer
set search_path=public
as $function$
declare
 v_order_id uuid; v_item_total numeric:=0; v_product_discount numeric:=0; v_coupon numeric:=0; v_delivery numeric:=0; v_total numeric:=0;
 v_address record; v_item record; v_wallet public.shubhcoins_wallets; v_coin_discount numeric:=0; v_coin_limit bigint:=0; v_requested bigint:=greatest(0,coalesce(p_shubhcoins,0));
 v_delivery_method text:=lower(coalesce(p_delivery_method,'standard')); v_coupon_code text:=upper(trim(coalesce(p_coupon_code,'')));
begin
 if p_customer_id is null or auth.uid() is null or auth.uid()<>p_customer_id then raise exception 'Unauthorized'; end if;
 if lower(p_payment_method) not in ('cod','razorpay','upi','card','netbanking') then raise exception 'Invalid payment method'; end if;
 if v_delivery_method not in ('standard','fast','express','scheduled') then raise exception 'Invalid delivery method'; end if;
 select id,name,mobile,house_shop,area,city,state,pincode into v_address from public.addresses where id=p_address_id and customer_id=p_customer_id;
 if not found then raise exception 'Address not found'; end if;
 if not exists(select 1 from public.cart where customer_id=p_customer_id) then raise exception 'Cart empty'; end if;
 for v_item in select c.product_id,c.quantity,p.name,p.price,p.mrp,p.stock,p.status from public.cart c join public.products p on p.id=c.product_id where c.customer_id=p_customer_id for update of c loop
  if v_item.status <> 'Active' then raise exception 'Product is no longer active: %',v_item.name; end if;
  if v_item.price is null or v_item.price<0 then raise exception 'Invalid product price: %',v_item.name; end if;
  if coalesce(v_item.stock,0)<v_item.quantity then raise exception 'Insufficient stock: %',v_item.name; end if;
  v_item_total:=v_item_total+(v_item.price*v_item.quantity);
  v_product_discount:=v_product_discount+(greatest(0,coalesce(v_item.mrp,v_item.price)-v_item.price)*v_item.quantity);
 end loop;
 if v_item_total<=0 then raise exception 'Invalid order amount'; end if;
 if v_coupon_code='WELCOME10' then v_coupon:=least(v_item_total*0.10,200); else v_coupon:=0; v_coupon_code:=null; end if;
 if v_delivery_method='express' then v_delivery:=99; elsif v_delivery_method='fast' then v_delivery:=49; elsif v_delivery_method='scheduled' then v_delivery:=79; elsif v_item_total<499 then v_delivery:=40; else v_delivery:=0; end if;
 if v_requested>0 then
   select * into v_wallet from public.shubhcoins_wallets where customer_id=p_customer_id for update;
   if not found then raise exception 'ShubhCoins wallet not found'; end if;
   v_coin_limit:=least(v_wallet.balance,floor(v_item_total*0.20)::bigint);
   if v_requested>v_coin_limit then raise exception 'Maximum % ShubhCoins can be redeemed on this order',v_coin_limit; end if;
   v_coin_discount:=v_requested;
 end if;
 v_total:=greatest(0,v_item_total-v_coupon-v_coin_discount+v_delivery);
 if v_total<=0 then raise exception 'Invalid order amount'; end if;
 insert into public."Orders"(customer_id,customer_name,customer_phone,total_amount,item_total,product_discount,coupon_code,coupon_discount,delivery_method,delivery_charge,payment_method,payment_status,order_status,shipping_address,address_id,currency,commission_amount,seller_earning)
 values(p_customer_id,v_address.name,v_address.mobile,v_total,v_item_total,v_product_discount,v_coupon_code,v_coupon,v_delivery_method,v_delivery,lower(p_payment_method),'Pending','Pending',concat_ws(', ',nullif(v_address.house_shop,''),nullif(v_address.area,''),nullif(v_address.city,''),nullif(v_address.state,''),nullif(v_address.pincode,'')),v_address.id,'INR',0,0) returning id into v_order_id;
 insert into public."Order_items"(order_id,product_id,quantity,unit_price,total_price)
 select v_order_id,c.product_id,c.quantity,p.price,p.price*c.quantity from public.cart c join public.products p on p.id=c.product_id where c.customer_id=p_customer_id;
 insert into public.payments(order_id,customer_id,amount,currency,method,status) values(v_order_id,p_customer_id,v_total,'INR',lower(p_payment_method),'Pending');
 if v_requested>0 then
   update public.shubhcoins_wallets set balance=balance-v_requested,lifetime_spent=lifetime_spent+v_requested,updated_at=now() where customer_id=p_customer_id;
   insert into public.shubhcoins_ledger(customer_id,amount,balance_after,type,reference_id,note)
   select customer_id,-v_requested,balance,'redeem',v_order_id::text,'Redeemed at checkout (₹1 per coin)';
 end if;
 return query select v_order_id,v_total,v_requested,v_coin_discount;
end;
$function$;
revoke all on function public.create_order_from_cart_with_coins(uuid,uuid,text,text,text,bigint) from public,anon;
grant execute on function public.create_order_from_cart_with_coins(uuid,uuid,text,text,text,bigint) to service_role;

-- Release a checkout redemption reservation when an online payment is abandoned or fails.
alter table public.shubhcoins_ledger drop constraint if exists shubhcoins_ledger_type_check;
alter table public.shubhcoins_ledger add constraint shubhcoins_ledger_type_check check(type in ('welcome','order_reward','referral','bonus','redeem','refund','adjustment','coin_release'));

create or replace function public.release_shubhcoins_for_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $function$
declare v_order record; v_redeem record; v_wallet public.shubhcoins_wallets;
begin
 if auth.uid() is null then raise exception 'Unauthorized'; end if;
 select id,customer_id,payment_status from public."Orders" where id=p_order_id and customer_id=auth.uid() into v_order;
 if not found then raise exception 'Order not found'; end if;
 if v_order.payment_status='Paid' then return false; end if;
 select id,customer_id,amount,reference_id from public.shubhcoins_ledger where customer_id=auth.uid() and type='redeem' and reference_id=p_order_id::text for update into v_redeem;
 if not found then return false; end if;
 if exists(select 1 from public.shubhcoins_ledger where customer_id=auth.uid() and type='coin_release' and reference_id=p_order_id::text) then return false; end if;
 select * into v_wallet from public.shubhcoins_wallets where customer_id=auth.uid() for update;
 if not found then raise exception 'ShubhCoins wallet not found'; end if;
 update public.shubhcoins_wallets set balance=balance+abs(v_redeem.amount),lifetime_spent=greatest(0,lifetime_spent-abs(v_redeem.amount)),updated_at=now() where customer_id=auth.uid();
 insert into public.shubhcoins_ledger(customer_id,amount,balance_after,type,reference_id,note)
 select customer_id,abs(v_redeem.amount),balance,'coin_release',p_order_id::text,'Released after unpaid/failed checkout';
 return true;
end;
$function$;
revoke all on function public.release_shubhcoins_for_order(uuid) from public,anon;
grant execute on function public.release_shubhcoins_for_order(uuid) to authenticated;

-- Defense-in-depth: order creation is only callable by the Edge Function's service role.
revoke all on function public.create_order_from_cart_with_coins(uuid,uuid,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.create_order_from_cart_with_coins(uuid,uuid,text,text,text,bigint) to service_role;
