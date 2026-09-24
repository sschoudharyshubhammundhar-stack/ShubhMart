create or replace function public.add_customer_address(
 p_name text,p_mobile text,p_house_shop text,p_area text,p_city text,p_state text,p_pincode text
) returns uuid language plpgsql security definer set search_path=public as $$
declare aid uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if length(trim(coalesce(p_name,'')))<2 or length(trim(coalesce(p_mobile,'')))<7 or length(trim(coalesce(p_city,'')))<2 or length(trim(coalesce(p_state,'')))<2 or length(trim(coalesce(p_pincode,'')))<4 then raise exception 'Incomplete address'; end if;
 update public.addresses set is_default=false,updated_at=now() where customer_id=auth.uid();
 insert into public.addresses(customer_id,name,mobile,house_shop,area,city,state,pincode,is_default)
 values(auth.uid(),trim(p_name),trim(p_mobile),nullif(trim(p_house_shop),''),nullif(trim(p_area),''),trim(p_city),trim(p_state),trim(p_pincode),true)
 returning id into aid;
 return aid;
end $$;
revoke all on function public.add_customer_address(text,text,text,text,text,text,text) from public,anon;
grant execute on function public.add_customer_address(text,text,text,text,text,text,text) to authenticated;
create or replace function public.set_cart_quantity(p_cart_id uuid,p_quantity integer) returns boolean language plpgsql security definer set search_path=public as $$
declare v_product uuid; v_stock integer;
begin
 if auth.uid() is null or p_quantity<1 then raise exception 'Invalid cart quantity'; end if;
 select product_id into v_product from public.cart where id=p_cart_id and customer_id=auth.uid() for update;
 if not found then raise exception 'Cart item not found'; end if;
 select stock into v_stock from public.products where id=v_product and status='Active' for update;
 if not found then raise exception 'Product unavailable'; end if;
 if p_quantity>v_stock then raise exception 'Only % items available',v_stock; end if;
 update public.cart set quantity=p_quantity,updated_at=now() where id=p_cart_id and customer_id=auth.uid();
 return true;
end $$;
revoke all on function public.set_cart_quantity(uuid,integer) from public,anon;
grant execute on function public.set_cart_quantity(uuid,integer) to authenticated;