-- Server-side checkout validation for stock, coupon/offers and delivery method.
create or replace function public.validate_checkout_cart(p_customer_id uuid,p_coupon_code text default '',p_delivery_method text default 'standard')
returns table(item_total numeric,product_discount numeric,coupon_discount numeric,delivery_charge numeric,total_amount numeric,valid boolean,message text)
language plpgsql security definer set search_path=public as $$
declare v_item record; v_total numeric:=0; v_discount numeric:=0; v_coupon numeric:=0; v_delivery numeric:=0; v_code text:=upper(trim(coalesce(p_coupon_code,''))); v_method text:=lower(coalesce(p_delivery_method,'standard')); v_found boolean:=false;
begin
 if auth.uid() is null or auth.uid()<>p_customer_id then raise exception 'Unauthorized'; end if;
 if v_method not in ('standard','fast','express','scheduled') then raise exception 'Invalid delivery method'; end if;
 for v_item in select c.product_id,c.quantity,p.name,p.price,p.mrp,p.stock,p.status from public.cart c join public.products p on p.id=c.product_id where c.customer_id=p_customer_id loop
  if v_item.status<>'Active' then return query select 0::numeric,0::numeric,0::numeric,0::numeric,0::numeric,false,('Product is no longer active: '||v_item.name); return; end if;
  if coalesce(v_item.stock,0)<v_item.quantity then return query select 0::numeric,0::numeric,0::numeric,0::numeric,0::numeric,false,('Insufficient stock: '||v_item.name); return; end if;
  v_total:=v_total+v_item.price*v_item.quantity; v_discount:=v_discount+greatest(0,coalesce(v_item.mrp,v_item.price)-v_item.price)*v_item.quantity;
 end loop;
 if v_total<=0 then return query select 0::numeric,0::numeric,0::numeric,0::numeric,0::numeric,false,'Cart is empty'; return; end if;
 if v_code='WELCOME10' then v_coupon:=least(v_total*.10,200); v_found:=true;
 elsif v_code<>'' then
   select exists(select 1 from public.product_offers o where upper(o.code)=v_code and o.status='Active' and o.starts_at<=now() and (o.ends_at is null or o.ends_at>now())) into v_found;
   if v_found then
     select least(sum(case when o.discount_type='percent' then least(v_total*o.discount_value/100,coalesce(o.max_discount,1e18)) else o.discount_value end),v_total) into v_coupon from public.product_offers o where upper(o.code)=v_code and o.status='Active' and o.starts_at<=now() and (o.ends_at is null or o.ends_at>now());
   else return query select v_total,v_discount,0::numeric,0::numeric,v_total,false,'Coupon invalid or expired'; return; end if;
 end if;
 if v_method='express' then v_delivery:=99; elsif v_method='fast' then v_delivery:=49; elsif v_method='scheduled' then v_delivery:=79; elsif v_total<499 then v_delivery:=40; end if;
 return query select v_total,v_discount,v_coupon,v_delivery,greatest(0,v_total-v_coupon+v_delivery),true,'Checkout ready';
end $$;
revoke all on function public.validate_checkout_cart(uuid,text,text) from public,anon;
grant execute on function public.validate_checkout_cart(uuid,text,text) to authenticated;