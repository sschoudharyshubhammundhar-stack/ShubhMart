-- Server-side cart quantity/stock validation.
create or replace function public.set_cart_quantity(p_cart_id uuid,p_quantity integer)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_product uuid; v_stock integer; v_status text;
begin
 v_user:=(select auth.uid()); if v_user is null then raise exception 'Authentication required'; end if;
 if p_quantity<1 then raise exception 'Quantity must be at least 1'; end if;
 select c.product_id,p.stock,p.status into v_product,v_stock,v_status from public.cart c join public.products p on p.id=c.product_id where c.id=p_cart_id and c.customer_id=v_user for update;
 if not found then raise exception 'Cart item not found'; end if;
 if v_status<>'Active' then raise exception 'Product is no longer active'; end if;
 if p_quantity>coalesce(v_stock,0) then raise exception 'Only % item(s) available',coalesce(v_stock,0); end if;
 update public.cart set quantity=p_quantity,updated_at=now() where id=p_cart_id and customer_id=v_user;
 return true;
end $$;
revoke all on function public.set_cart_quantity(uuid,integer) from public,anon;
grant execute on function public.set_cart_quantity(uuid,integer) to authenticated;