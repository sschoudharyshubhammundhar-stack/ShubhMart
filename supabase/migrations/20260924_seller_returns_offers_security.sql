create index if not exists returns_order_status_idx on public.returns(order_id,status,created_at desc);
create index if not exists refunds_order_status_idx on public.refunds(order_id,status,created_at desc);
create index if not exists product_offers_seller_status_idx on public.product_offers(seller_id,status,created_at desc);

drop policy if exists sellers_view_own_returns on public.returns;
create policy sellers_view_own_returns on public.returns for select to authenticated using (exists (select 1 from public."Orders" o where o.id=returns.order_id and o.seller_id=(select s.id from public."Sellers" s where s.user_id=(select auth.uid()))));

drop policy if exists sellers_view_own_refunds on public.refunds;
create policy sellers_view_own_refunds on public.refunds for select to authenticated using (exists (select 1 from public."Orders" o where o.id=refunds.order_id and o.seller_id=(select s.id from public."Sellers" s where s.user_id=(select auth.uid()))));

drop policy if exists sellers_view_own_offers on public.product_offers;
create policy sellers_view_own_offers on public.product_offers for select to authenticated using (seller_id=(select s.id from public."Sellers" s where s.user_id=(select auth.uid())));

create or replace function public.seller_create_product_offer(p_product_id uuid,p_code text,p_title text,p_discount_type text,p_discount_value numeric,p_min_order_amount numeric default 0,p_max_discount numeric default null,p_starts_at timestamptz default now(),p_ends_at timestamptz default null) returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid; oid uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select id into sid from public."Sellers" where user_id=auth.uid() and status='Approved';
 if sid is null then raise exception 'Approved seller access required'; end if;
 if not exists(select 1 from public.products where id=p_product_id and seller_id=sid) then raise exception 'Product ownership required'; end if;
 if nullif(trim(p_title),'') is null or nullif(trim(p_code),'') is null then raise exception 'Offer title and code required'; end if;
 if p_discount_type not in ('percent','flat') or p_discount_value<=0 then raise exception 'Invalid discount'; end if;
 if p_discount_type='percent' and p_discount_value>100 then raise exception 'Percent discount cannot exceed 100'; end if;
 if p_min_order_amount<0 or coalesce(p_max_discount,0)<0 then raise exception 'Invalid minimum/max discount'; end if;
 if p_ends_at is not null and p_ends_at<=p_starts_at then raise exception 'Offer end must be after start'; end if;
 insert into public.product_offers(product_id,seller_id,code,title,discount_type,discount_value,min_order_amount,max_discount,starts_at,ends_at,status)
 values(p_product_id,sid,upper(trim(p_code)),left(trim(p_title),200),p_discount_type,p_discount_value,greatest(0,p_min_order_amount),p_max_discount,p_starts_at,p_ends_at,'Pending') returning id into oid;
 insert into public.seller_account_audit(seller_id,action,metadata) values(sid,'offer_create',jsonb_build_object('offer_id',oid,'product_id',p_product_id));
 return oid;
end $$;
revoke all on function public.seller_create_product_offer(uuid,text,text,text,numeric,numeric,numeric,timestamptz,timestamptz) from public,anon;
grant execute on function public.seller_create_product_offer(uuid,text,text,text,numeric,numeric,numeric,timestamptz,timestamptz) to authenticated;

create or replace function public.seller_update_product_offer(p_offer_id uuid,p_title text,p_discount_type text,p_discount_value numeric,p_min_order_amount numeric default 0,p_max_discount numeric default null,p_starts_at timestamptz default now(),p_ends_at timestamptz default null) returns boolean language plpgsql security definer set search_path=public as $$
declare sid uuid;
begin
 select id into sid from public."Sellers" where user_id=auth.uid() and status='Approved';
 if sid is null then raise exception 'Approved seller access required'; end if;
 if not exists(select 1 from public.product_offers where id=p_offer_id and seller_id=sid) then raise exception 'Offer ownership required'; end if;
 if nullif(trim(p_title),'') is null or p_discount_type not in ('percent','flat') or p_discount_value<=0 then raise exception 'Invalid offer'; end if;
 if p_discount_type='percent' and p_discount_value>100 then raise exception 'Percent discount cannot exceed 100'; end if;
 if p_min_order_amount<0 or coalesce(p_max_discount,0)<0 then raise exception 'Invalid discount limits'; end if;
 if p_ends_at is not null and p_ends_at<=p_starts_at then raise exception 'Offer end must be after start'; end if;
 update public.product_offers set title=left(trim(p_title),200),discount_type=p_discount_type,discount_value=p_discount_value,min_order_amount=greatest(0,p_min_order_amount),max_discount=p_max_discount,starts_at=p_starts_at,ends_at=p_ends_at,status='Pending' where id=p_offer_id and seller_id=sid;
 insert into public.seller_account_audit(seller_id,action,metadata) values(sid,'offer_update',jsonb_build_object('offer_id',p_offer_id));
 return true;
end $$;
revoke all on function public.seller_update_product_offer(uuid,text,text,numeric,numeric,numeric,timestamptz,timestamptz) from public,anon;
grant execute on function public.seller_update_product_offer(uuid,text,text,numeric,numeric,numeric,timestamptz,timestamptz) to authenticated;

create or replace function public.seller_cancel_product_offer(p_offer_id uuid) returns boolean language plpgsql security definer set search_path=public as $$
declare sid uuid;
begin
 select id into sid from public."Sellers" where user_id=auth.uid() and status='Approved';
 if sid is null then raise exception 'Approved seller access required'; end if;
 update public.product_offers set status='Expired' where id=p_offer_id and seller_id=sid and status in ('Pending','Active');
 if not found then raise exception 'Offer not found or already closed'; end if;
 insert into public.seller_account_audit(seller_id,action,metadata) values(sid,'offer_cancel',jsonb_build_object('offer_id',p_offer_id));
 return true;
end $$;
revoke all on function public.seller_cancel_product_offer(uuid) from public,anon;
grant execute on function public.seller_cancel_product_offer(uuid) to authenticated;