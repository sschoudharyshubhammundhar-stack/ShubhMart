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
set search_path = ''
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
    where id = p_order_id
      and customer_id = auth.uid()
      and payment_status is distinct from 'Paid'
  ) then
    raise exception 'Order not found or already paid';
  end if;

  -- Do not let a customer replace a previously attached gateway order ID.
  -- Same-ID retries are idempotent; a different ID requires reconciliation.
  -- Update exactly one current payment-attempt row. Do not mutate historical
  -- attempts if the schema permits more than one payment row per order.
  with target as (
    select id
    from public.payments
    where order_id = p_order_id
      and customer_id = auth.uid()
      and status is distinct from 'Paid'
      and (gateway_order_id is null or gateway_order_id = p_gateway_order_id)
    order by updated_at desc nulls last, id desc
    for update
    limit 1
  )
  update public.payments as p
     set gateway = 'Razorpay',
         gateway_order_id = p_gateway_order_id,
         method = coalesce(nullif(trim(p_method), ''), 'razorpay'),
         status = 'Pending',
         updated_at = now()
    from target
   where p.id = target.id;

  if not found then
    raise exception 'Payment record missing, already paid, or gateway order already attached';
  end if;
end;
$function$;

revoke all on function public.attach_razorpay_order(uuid, text, text) from public, anon;
grant execute on function public.attach_razorpay_order(uuid, text, text) to authenticated, service_role;


-- Payment IDs must never be claimed by two orders, including concurrent callbacks.
-- PRE-FLIGHT REQUIRED before creating this index:
--   SELECT gateway_payment_id, count(*) FROM public.payments
--   WHERE gateway_payment_id IS NOT NULL
--   GROUP BY gateway_payment_id HAVING count(*) > 1;
-- If this returns rows, reconcile them manually; do not delete/merge records automatically.
-- Only create the unique index after the preflight returns no rows.
create unique index if not exists payments_gateway_payment_id_unique
  on public.payments (gateway_payment_id)
  where gateway_payment_id is not null;

-- The payment UPDATE trigger currently denies a service-role request because
-- auth.uid() is null and private.is_admin() is false. Allow only the signed
-- service_role JWT to make the server-verified payment-state update.
create or replace function public.guard_customer_payment_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.role() = 'service_role' then
    return new;
  end if;
  if private.is_admin() then
    return new;
  end if;
  if auth.uid() is null or old.customer_id is distinct from auth.uid() then
    raise exception 'Payment update denied';
  end if;
  if new.amount is distinct from old.amount
     or new.customer_id is distinct from old.customer_id
     or new.status is distinct from old.status
     or new.gateway_payment_id is distinct from old.gateway_payment_id
     or new.gateway_signature is distinct from old.gateway_signature then
    raise exception 'Protected payment fields cannot be changed by customer';
  end if;
  return new;
end;
$function$;

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
set search_path = ''
as $function$
declare
  v_customer_id uuid;
  v_order_payment_status text;
  v_order_payment_id text;
  v_gateway_order_id text;
  v_existing_gateway_payment_id text;
  v_payment_row_id uuid;
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

  -- Resolve the exact provider attempt, never "the newest payment row".
  -- An older callback must not mutate a newer attempt just because updated_at is later.
  select id, gateway_order_id, gateway_payment_id
    into v_payment_row_id, v_gateway_order_id, v_existing_gateway_payment_id
  from public.payments
  where order_id = p_order_id
    and customer_id = p_customer_id
    and gateway_order_id = p_razorpay_order_id
  order by id
  limit 1
  for update;

  if v_payment_row_id is null
     or v_gateway_order_id is null
     or v_gateway_order_id <> p_razorpay_order_id then
    raise exception 'Payment attempt not found for this gateway order';
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
  where id = v_payment_row_id
    and order_id = p_order_id
    and customer_id = p_customer_id
    and gateway_order_id = p_razorpay_order_id;

  if not found then
    raise exception 'Payment record not found or changed during verification';
  end if;
end;
$function$;

revoke all on function public.mark_razorpay_paid_secure(uuid, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.mark_razorpay_paid_secure(uuid, uuid, text, text, text) to service_role;

commit;
