-- Delivery status transition hardening: all partner status changes go through one atomic RPC.
create or replace function public.update_delivery_shipment_status(
  p_shipment_id uuid,
  p_status text,
  p_note text default null
) returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_partner uuid;
  v_current text;
  v_now timestamptz := now();
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select dp.id into v_partner from public.delivery_partners dp
  where dp.user_id=v_uid and dp.status='Approved' limit 1;
  if v_partner is null then raise exception 'Approved delivery partner required'; end if;

  select shipment_status, delivery_partner_id into v_current, v_partner
  from public.shipments where id=p_shipment_id for update;

  if not found or v_partner is null or not exists (
    select 1 from public.delivery_partners dp
    where dp.id=v_partner and dp.user_id=v_uid and dp.status='Approved'
  ) then raise exception 'Shipment is not assigned to this delivery partner'; end if;

  if p_status not in ('Picked Up','Packed','Dispatched','Out for Delivery','Delivered','Failed','RTO','Return Pickup','Returned') then
    raise exception 'Invalid delivery status';
  end if;

  if not (
    (v_current='Assigned' and p_status in ('Picked Up','Failed','RTO')) or
    (v_current='Picked Up' and p_status in ('Packed','Failed','RTO')) or
    (v_current='Packed' and p_status in ('Dispatched','Failed','RTO')) or
    (v_current='Dispatched' and p_status in ('Out for Delivery','Failed','RTO')) or
    (v_current='Out for Delivery' and p_status in ('Delivered','Failed','RTO','Return Pickup')) or
    (v_current='Return Pickup' and p_status in ('Returned','Failed')) or
    (v_current='Failed' and p_status in ('RTO','Return Pickup')) or
    (v_current='RTO' and p_status='Return Pickup')
  ) then raise exception 'Invalid shipment status transition: % -> %',v_current,p_status; end if;

  update public.shipments set
    shipment_status=p_status,
    picked_up_at=case when p_status='Picked Up' then v_now else picked_up_at end,
    dispatched_at=case when p_status='Dispatched' then v_now else dispatched_at end,
    out_for_delivery_at=case when p_status='Out for Delivery' then v_now else out_for_delivery_at end,
    delivered_at=case when p_status='Delivered' then v_now else delivered_at end,
    failed_reason=case when p_status='Failed' then nullif(left(coalesce(p_note,''),500),'') else failed_reason end,
    rto_reason=case when p_status='RTO' then nullif(left(coalesce(p_note,''),500),'') else rto_reason end,
    updated_at=v_now where id=p_shipment_id;

  insert into public.delivery_events(shipment_id,status,note,actor_user_id)
  values(p_shipment_id,p_status,left(coalesce(p_note,'Updated by delivery partner'),500),v_uid);
  return true;
end;
$$;

revoke all on function public.update_delivery_shipment_status(uuid,text,text) from public,anon;
grant execute on function public.update_delivery_shipment_status(uuid,text,text) to authenticated;