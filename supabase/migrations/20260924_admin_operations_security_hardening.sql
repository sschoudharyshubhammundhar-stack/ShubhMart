-- Admin operations security hardening
create or replace function public.admin_set_delivery_partner_status(p_partner_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Pending','Approved','Suspended','Rejected') then raise exception 'Invalid partner status'; end if;
 update public.delivery_partners set status=p_status,availability='Offline',updated_at=now() where id=p_partner_id;
 if not found then raise exception 'Delivery partner not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata) values(auth.uid(),'delivery_partner_status','delivery_partner',p_partner_id,jsonb_build_object('status',p_status));
 return true;
end $$;
revoke all on function public.admin_set_delivery_partner_status(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_set_delivery_partner_status(uuid,text) to authenticated;

create or replace function public.admin_create_shipment(p_order_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid; tracking text;
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if exists(select 1 from public.shipments where order_id=p_order_id) then select id into sid from public.shipments where order_id=p_order_id limit 1; return sid; end if;
 if not exists(select 1 from public."Orders" where id=p_order_id) then raise exception 'Order not found'; end if;
 tracking='SM'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 insert into public.shipments(order_id,tracking_number,shipment_status) values(p_order_id,tracking,'Pending') returning id into sid;
 insert into public.delivery_events(shipment_id,status,note,actor_user_id) values(sid,'Pending','Shipment created by admin',auth.uid());
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata) values(auth.uid(),'shipment_create','shipment',sid,jsonb_build_object('order_id',p_order_id,'tracking_number',tracking));
 return sid;
end $$;
revoke all on function public.admin_create_shipment(uuid) from public,anon,authenticated;
grant execute on function public.admin_create_shipment(uuid) to authenticated;

create or replace function public.admin_assign_shipment(p_shipment_id uuid,p_partner_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if not exists(select 1 from public.shipments where id=p_shipment_id) then raise exception 'Shipment not found'; end if;
 if not exists(select 1 from public.delivery_partners where id=p_partner_id and status='Approved') then raise exception 'Approved delivery partner required'; end if;
 update public.shipments set delivery_partner_id=p_partner_id,shipment_status='Assigned',updated_at=now() where id=p_shipment_id;
 insert into public.delivery_events(shipment_id,status,note,actor_user_id) values(p_shipment_id,'Assigned','Assigned by admin',auth.uid());
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata) values(auth.uid(),'shipment_assign','shipment',p_shipment_id,jsonb_build_object('partner_id',p_partner_id));
 return true;
end $$;
revoke all on function public.admin_assign_shipment(uuid,uuid) from public,anon,authenticated;
grant execute on function public.admin_assign_shipment(uuid,uuid) to authenticated;

create or replace function public.admin_set_service_provider_status(p_provider_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Pending','Approved','Rejected','Suspended') then raise exception 'Invalid provider status'; end if;
 update public.service_providers set status=p_status,kyc_status=case when p_status='Approved' then 'Verified' when p_status='Rejected' then 'Rejected' else 'Pending' end,updated_at=now() where id=p_provider_id;
 if not found then raise exception 'Provider not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata) values(auth.uid(),'service_provider_status','service_provider',p_provider_id,jsonb_build_object('status',p_status));
 return true;
end $$;
revoke all on function public.admin_set_service_provider_status(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_set_service_provider_status(uuid,text) to authenticated;

create or replace function public.admin_set_service_status(p_service_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Pending','Active','Rejected','Suspended') then raise exception 'Invalid service status'; end if;
 update public.services set status=p_status,updated_at=now() where id=p_service_id;
 if not found then raise exception 'Service not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata) values(auth.uid(),'service_status','service',p_service_id,jsonb_build_object('status',p_status));
 return true;
end $$;
revoke all on function public.admin_set_service_status(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_set_service_status(uuid,text) to authenticated;

create or replace function public.admin_set_credit_application_status(p_application_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Pending','Under Review','Approved','Rejected') then raise exception 'Invalid credit status'; end if;
 update public.shubhcredit_applications set status=p_status,updated_at=now() where id=p_application_id;
 if not found then raise exception 'Credit application not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata) values(auth.uid(),'credit_application_status','shubhcredit_application',p_application_id,jsonb_build_object('status',p_status));
 return true;
end $$;
revoke all on function public.admin_set_credit_application_status(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_set_credit_application_status(uuid,text) to authenticated;
