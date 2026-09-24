create or replace function public.seller_add_product_variant(p_product_id uuid,p_sku text,p_variant_name text,p_option_value text,p_price numeric,p_mrp numeric,p_stock integer,p_image_url text) returns uuid language plpgsql security definer set search_path=public as $$
declare v_seller uuid; v_id uuid; v_user uuid := (select auth.uid());
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select id into v_seller from public."Sellers" where user_id=v_user and status='Approved' limit 1;
 if v_seller is null then raise exception 'Approved seller account required'; end if;
 if not exists(select 1 from public.products where id=p_product_id and seller_id=v_seller) then raise exception 'Product access denied'; end if;
 if length(trim(coalesce(p_variant_name,'')))<1 or length(trim(coalesce(p_option_value,'')))<1 or p_price<=0 or p_mrp<p_price or p_stock<0 then raise exception 'Invalid variant details'; end if;
 insert into public.product_variants(product_id,sku,variant_name,option_value,price,mrp,stock,image_url,status) values(p_product_id,nullif(trim(coalesce(p_sku,'')),''),trim(p_variant_name),trim(p_option_value),p_price,p_mrp,p_stock,nullif(trim(coalesce(p_image_url,'')),''),'Pending') returning id into v_id;
 insert into public.seller_account_audit(seller_id,action,metadata) values(v_seller,'variant_created',jsonb_build_object('product_id',p_product_id,'variant_id',v_id));
 return v_id;
end $$;
revoke all on function public.seller_add_product_variant(uuid,text,text,text,numeric,numeric,integer,text) from public,anon;
grant execute on function public.seller_add_product_variant(uuid,text,text,text,numeric,numeric,integer,text) to authenticated;