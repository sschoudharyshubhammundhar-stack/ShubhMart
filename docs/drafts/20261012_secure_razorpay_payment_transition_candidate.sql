-- DRAFT MIGRATION CANDIDATE — do not apply to production until isolated DB tests and review pass.
-- Purpose: let the authenticated customer call the ownership-checking attach RPC,
-- and make the privileged "mark paid" transition safe to retry for the same payment.

begin;

create or replace function public.attach_razorpay_order(
  p_order_id uuid,
  p_gateway_order_id text,
  p_method text
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;
  if p_order_id is null or nullif(trim(p_gateway_order_id), '') is null then
    raise exception 'Invalid payment order';
  end if;
  if not exists (
    select 1 from public."Orders"
    where id = p_order_id and customer_id = auth.uid()
  ) then
    raise exception 'Order not found';
  end if;

  update public.payments
  set gateway = 'Razorpay',
      gateway_order_id = p_gateway_order_id,
      method = coalesce(nullif(trim(p_method), ''), 'razorpay'),
      status = 'Pending',
      updated_at = now()
  where order_id = p_order_id
    and customer_id = auth.uid();

  if not found then
    raise exception 'Payment record not found';
  end if;
end;
$function$;

revoke all on function public.attach_razorpay_order(uuid, text, text) from public, anon;
grant execute on function public.attach_razorpay_order(uuid, text, text) to authenticated, service_role;

create or replace function public.mark_razorpay_paid_secure(
  p_order_id uuid,
  p_customer_id uuid,
  p_razorpay_order_id text,
  p_payment_id text,
  p_signature text
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_customer_id uuid;
  v_order_payment_status text;
  v_order_payment_id text;
  v_gateway_order_id text;
  v_existing_gateway_payment_id text;
begin
  if p_order_id is null
     or p_customer_id is null
     or nullif(trim(p_razorpay_order_id), '') is null
     or nullif(trim(p_payment_id), '') is null
     or nullif(trim(p_signature), '') is null then
    raise exception 'Invalid payment verification request';
  end if;

  select customer_id, payment_status, payment_transaction_id
    into v_customer_id, v_order_payment_status, v_order_payment_id
  from public."Orders"
  where id = p_order_id
  for update;

  if v_customer_id is null or v_customer_id <> p_customer_id then
    raise exception 'Order not found';
  end if;

  select gateway_order_id, gateway_payment_id
    into v_gateway_order_id, v_existing_gateway_payment_id
  from public.payments
  where order_id = p_order_id
    and customer_id = p_customer_id
  order by updated_at desc nulls last
  limit 1
  for update;

  if v_gateway_order_id is null or v_gateway_order_id <> p_razorpay_order_id then
    raise exception 'Payment gateway order mismatch';
  end if;

  -- Idempotent retry: same already-confirmed payment is a no-op.
  if v_order_payment_status = 'Paid' then
    if v_order_payment_id = p_payment_id
       and v_existing_gateway_payment_id = p_payment_id then
      return;
    end if;
    raise exception 'Order already paid with a different payment';
  end if;

  if exists (
    select 1
    from public.payments p
    where p.gateway_payment_id = p_payment_id
      and p.order_id <> p_order_id
  ) then
    raise exception 'Payment already linked to another order';
  end if;

  update public."Orders"
  set payment_status = 'Paid',
      payment_transaction_id = p_payment_id
  where id = p_order_id
    and customer_id = p_customer_id
    and payment_status is distinct from 'Paid';

  if not found then
    raise exception 'Order payment state changed; retry verification';
  end if;

  update public.payments
  set status = 'Paid',
      gateway = 'Razorpay',
      gateway_order_id = p_razorpay_order_id,
      gateway_payment_id = p_payment_id,
      gateway_signature = p_signature,
      updated_at = now()
  where order_id = p_order_id
    and customer_id = p_customer_id
    and gateway_order_id = p_razorpay_order_id;

  if not found then
    raise exception 'Payment record not found';
  end if;
end;
$function$;

revoke all on function public.mark_razorpay_paid_secure(uuid, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.mark_razorpay_paid_secure(uuid, uuid, text, text, text) to service_role;

commit;
