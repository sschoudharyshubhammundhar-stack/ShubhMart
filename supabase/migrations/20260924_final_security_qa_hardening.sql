-- ShubhMart final security/QA hardening
-- Add FK indexes and transaction-safe service booking/status operations.

create index if not exists order_items_order_id_idx on public."Order_items"(order_id);
create index if not exists order_items_product_id_idx on public."Order_items"(product_id);
create index if not exists cart_product_id_idx on public.cart(product_id);
create index if not exists commissions_order_item_id_idx on public.commissions(order_item_id);
create index if not exists delivery_events_actor_user_id_idx on public.delivery_events(actor_user_id);
create index if not exists notifications_order_id_idx on public.notifications(order_id);
create index if not exists returns_customer_id_idx on public.returns(customer_id);
create index if not exists returns_order_id_idx on public.returns(order_id);
create index if not exists service_slots_provider_id_idx on public.service_slots(provider_id);
create index if not exists wholesale_inquiries_product_id_idx on public.wholesale_inquiries(product_id);
create index if not exists wishlist_product_id_idx on public.wishlist(product_id);

revoke execute on function public.is_admin() from public, anon, authenticated;

drop policy if exists "customer create service bookings" on public.service_bookings;
drop policy if exists "customer cancel own service bookings" on public.service_bookings;
drop policy if exists "provider update own service bookings" on public.service_bookings;
drop policy if exists "customer insert service bookings" on public.service_bookings;
drop policy if exists "customer can create valid service booking" on public.service_bookings;
drop policy if exists "customer can cancel own booking" on public.service_bookings;
drop policy if exists "provider can update own bookings" on public.service_bookings;

create policy "service bookings admin manage"
on public.service_bookings for all to authenticated
using ((select private.is_admin()))
with check ((select private.is_admin()));

create or replace function public.book_service_slot(p_service_id uuid,p_slot_id uuid,p_address text,p_customer_note text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_user uuid := (select auth.uid()); v_provider uuid; v_price numeric; v_booking uuid;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if p_service_id is null or p_slot_id is null then raise exception 'Service and slot are required'; end if;
 if coalesce(trim(p_address),'')='' then raise exception 'Service address is required'; end if;
 select s.provider_id,s.price into v_provider,v_price from public.services s
 join public.service_providers sp on sp.id=s.provider_id
 where s.id=p_service_id and s.status='Active' and sp.status='Approved';
 if v_provider is null then raise exception 'Service is not available'; end if;
 update public.service_slots set status='Booked'
 where id=p_slot_id and service_id=p_service_id and provider_id=v_provider and status='Available' and slot_start>=now();
 if not found then raise exception 'Slot is no longer available'; end if;
 insert into public.service_bookings(customer_id,provider_id,service_id,slot_id,total_amount,address,customer_note,booking_status,payment_status)
 values(v_user,v_provider,p_service_id,p_slot_id,v_price,p_address,p_customer_note,'Pending','Pending') returning id into v_booking;
 insert into public.service_events(booking_id,status,note,actor_user_id)
 values(v_booking,'Pending','Booking created by customer',v_user);
 return v_booking;
end; $$;

revoke all on function public.book_service_slot(uuid,uuid,text,text) from public,anon;
grant execute on function public.book_service_slot(uuid,uuid,text,text) to authenticated;

create or replace function public.cancel_service_booking(p_booking_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_user uuid := (select auth.uid()); v_slot uuid;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 update public.service_bookings set booking_status='Cancelled',updated_at=now()
 where id=p_booking_id and customer_id=v_user and booking_status in ('Pending','Confirmed','Provider Accepted','Scheduled')
 returning slot_id into v_slot;
 if not found then raise exception 'Booking cannot be cancelled'; end if;
 if v_slot is not null then update public.service_slots set status='Available' where id=v_slot and status='Booked'; end if;
 insert into public.service_events(booking_id,status,note,actor_user_id)
 values(p_booking_id,'Cancelled','Booking cancelled by customer',v_user);
 return true;
end; $$;
revoke all on function public.cancel_service_booking(uuid) from public,anon;
grant execute on function public.cancel_service_booking(uuid) to authenticated;

create or replace function public.update_service_booking_status(p_booking_id uuid,p_status text,p_note text default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_user uuid := (select auth.uid()); v_provider uuid; v_current text; v_provider_user uuid;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select b.booking_status,b.provider_id,sp.user_id into v_current,v_provider,v_provider_user
 from public.service_bookings b join public.service_providers sp on sp.id=b.provider_id where b.id=p_booking_id;
 if v_provider is null then raise exception 'Booking not found'; end if;
 if v_provider_user<>v_user then raise exception 'Not authorized'; end if;
 if p_status not in ('Provider Accepted','Rejected','Scheduled','In Progress','Completed','No Show','Disputed') then raise exception 'Invalid provider status'; end if;
 if (v_current,p_status) not in (
 ('Pending','Provider Accepted'),('Pending','Rejected'),('Provider Accepted','Scheduled'),
 ('Scheduled','In Progress'),('In Progress','Completed'),('Scheduled','No Show'),
 ('In Progress','No Show'),('Provider Accepted','Disputed'),('Scheduled','Disputed'),('In Progress','Disputed')
 ) then raise exception 'Invalid booking status transition'; end if;
 update public.service_bookings set booking_status=p_status,updated_at=now() where id=p_booking_id;
 insert into public.service_events(booking_id,status,note,actor_user_id)
 values(p_booking_id,p_status,coalesce(p_note,'Provider updated booking'),v_user);
 return true;
end; $$;
revoke all on function public.update_service_booking_status(uuid,text,text) from public,anon;
grant execute on function public.update_service_booking_status(uuid,text,text) to authenticated;

drop policy if exists "provider manage own service slots" on public.service_slots;
drop policy if exists "provider manage own slots" on public.service_slots;
create policy "provider insert available service slots" on public.service_slots for insert to authenticated
with check (provider_id in (select id from public.service_providers where user_id=(select auth.uid())) and status='Available');
create policy "provider update unbooked service slots" on public.service_slots for update to authenticated
using (provider_id in (select id from public.service_providers where user_id=(select auth.uid())) and status<>'Booked')
with check (provider_id in (select id from public.service_providers where user_id=(select auth.uid())) and status in ('Available','Blocked'));
create policy "provider delete unbooked service slots" on public.service_slots for delete to authenticated
using (provider_id in (select id from public.service_providers where user_id=(select auth.uid())) and status<>'Booked');
