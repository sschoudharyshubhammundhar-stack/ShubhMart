-- ShubhMart: secure checkout hardening + data-driven coupon validation
-- Applied to production on 2026-09-26; kept in migrations for source-of-truth parity.
create or replace function public.create_order_from_cart(p_customer_id uuid,p_address_id uuid,p_payment_method text default 'razorpay',p_delivery_method text default 'standard',p_coupon_code text default '')
returns table(order_id uuid,total_amount numeric)
language plpgsql security definer set search_path=public
as $function$
declare
 v_order_id uuid; v_item_total numeric:=0; v_product_discount numeric:=0; v_coupon numeric:=0; v_delivery numeric:=0; v_total numeric:=0;
 v_address record; v_item record; v_coupon_row record; v_delivery_method text:=lower(coalesce(p_delivery_method,'standard')); v_coupon_code text:=upper(trim(coalesce(p_coupon_code,'')));
begin
 if p_customer_id is null or auth.uid() is distinct from p_customer_id then raise exception 'Unauthorized'; end if;
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
 if v_coupon_code<>'' then
  select * into v_coupon_row from public.coupons c where upper(c.code)=v_coupon_code and c.active=true and c.start_date<=now() and (c.end_date is null or c.end_date>=now()) limit 1;
  if found and v_item_total>=coalesce(v_coupon_row.min_order,0) then v_coupon:=least(greatest(0,coalesce(v_coupon_row.discount_amount,0)),v_item_total); else v_coupon_code:=null; end if;
 else v_coupon_code:=null; end if;
 if v_delivery_method='express' then v_delivery:=99; elsif v_delivery_method='fast' then v_delivery:=49; elsif v_delivery_method='scheduled' then v_delivery:=79; elsif v_item_total<499 then v_delivery:=40; else v_delivery:=0; end if;
 v_total:=greatest(0,v_item_total-v_coupon+v_delivery);
 insert into public."Orders"(customer_id,customer_name,customer_phone,total_amount,item_total,product_discount,coupon_code,coupon_discount,delivery_method,delivery_charge,payment_method,payment_status,order_status,shipping_address,address_id,currency,commission_amount,seller_earning)
 values(p_customer_id,v_address.name,v_address.mobile,v_total,v_item_total,v_product_discount,v_coupon_code,v_coupon,v_delivery_method,v_delivery,lower(p_payment_method),'Pending','Pending',concat_ws(', ',nullif(v_address.house_shop,''),nullif(v_address.area,''),nullif(v_address.city,''),nullif(v_address.state,''),nullif(v_address.pincode,'')),v_address.id,'INR',0,0)
 returning id into v_order_id;
 insert into public."Order_items"(order_id,product_id,quantity,unit_price,total_price)
 select v_order_id,c.product_id,c.quantity,p.price,p.price*c.quantity from public.cart c join public.products p on p.id=c.product_id where c.customer_id=p_customer_id;
 insert into public.payments(order_id,customer_id,amount,currency,method,status) values(v_order_id,p_customer_id,v_total,'INR',lower(p_payment_method),'Pending');
 return query select v_order_id,v_total;
end;
$function$;
revoke all on function public.create_order_from_cart(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.create_order_from_cart(uuid,uuid,text,text,text) to authenticated;