create index if not exists wholesale_inquiries_buyer_status_created_idx on public.wholesale_inquiries(buyer_id,status,created_at desc);
create index if not exists wholesale_inquiries_seller_status_created_idx on public.wholesale_inquiries(seller_id,status,created_at desc);
create index if not exists wholesale_pricing_product_status_min_idx on public.wholesale_pricing(product_id,status,min_quantity);
create or replace function public.seller_update_wholesale_inquiry(p_inquiry_id uuid,p_status text,p_quoted_price numeric default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare sid uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select id into sid from public."Sellers" where user_id=auth.uid() and status='Approved';
 if sid is null then raise exception 'Approved seller access required'; end if;
 if p_status not in ('Quoted','Rejected') then raise exception 'Invalid inquiry status'; end if;
 if p_status='Quoted' and (p_quoted_price is null or p_quoted_price<=0) then raise exception 'Valid quoted price required'; end if;
 update public.wholesale_inquiries set status=p_status,quoted_price=case when p_status='Quoted' then p_quoted_price else null end,updated_at=now()
 where id=p_inquiry_id and seller_id=sid and status in ('Pending','Quoted');
 if not found then raise exception 'Inquiry not found or not editable'; end if;
 return true;
end $$;
revoke all on function public.seller_update_wholesale_inquiry(uuid,text,numeric) from public,anon;
grant execute on function public.seller_update_wholesale_inquiry(uuid,text,numeric) to authenticated;
create or replace function public.buyer_update_wholesale_inquiry(p_inquiry_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_status not in ('Accepted','Cancelled') then raise exception 'Invalid buyer status'; end if;
 update public.wholesale_inquiries set status=p_status,updated_at=now()
 where id=p_inquiry_id and buyer_id=auth.uid() and status in ('Pending','Quoted');
 if not found then raise exception 'Inquiry not found or not editable'; end if;
 return true;
end $$;
revoke all on function public.buyer_update_wholesale_inquiry(uuid,text) from public,anon;
grant execute on function public.buyer_update_wholesale_inquiry(uuid,text) to authenticated;