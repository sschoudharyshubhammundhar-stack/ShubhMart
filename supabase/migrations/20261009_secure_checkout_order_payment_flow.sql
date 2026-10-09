-- ShubhMart Stage 2: secure checkout, stock reservation, idempotency and Razorpay integrity.
-- Source-only until the release gate. Do not apply to production before reviewed validation.

alter table public."Orders"
  add column if not exists checkout_request_id uuid;

create unique index if not exists orders_customer_checkout_request_id_uidx
  on public."Orders"(customer_id, checkout_request_id)
  where checkout_request_id is not null;

create unique index if not exists payments_gateway_order_id_uidx
  on public.payments(gateway_order_id)
  where gateway_order_id is not null;

create unique index if not exists payments_gateway_payment_id_uidx
  on public.payments(gateway_payment_id)
  where gateway_payment_id is not null;

-- The live products table has no updated_at column; the existing trigger referenced it,
-- which would make product stock updates fail. Preserve protected fields without that invalid assignment.
create or replace function public.protect_product_admin_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner_approved boolean;
begin
  select exists(
    select 1
    from public."Sellers" s
    where s.id = old.seller_id
      and s.user_id = (select auth.uid())
      and s.status = 'Approved'
  ) into v_owner_approved;

  if not private.is_admin() then
    new.id := old.id;
    new.seller_id := old.seller_id;
    new.status := old.status;
    new.commission_rate := old.commission_rate;
    new.approved_at := old.approved_at;
    new.approved_by := old.approved_by;
    new.rejection_reason := old.rejection_reason;
    new.is_live := old.is_live;
    new.compliance_status := old.compliance_status;
    new.compliance_notes := old.compliance_notes;
    new.ai_status := old.ai_status;
    new.ai_reviewed_by_seller := old.ai_reviewed_by_seller;
    if not v_owner_approved then
      new.wholesale_enabled := old.wholesale_enabled;
      new.wholesale_moq := old.wholesale_moq;
      new.wholesale_price := old.wholesale_price;
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.create_customer_order_secure(
  p_customer_id uuid,
  p_address_id uuid,
  p_payment_method text,
  p_delivery_method text,
  p_coupon_code text,
  p_shubhcoins bigint,
  p_request_id uuid
)
returns table(order_id uuid, total_amount numeric, coins_redeemed bigint, coin_discount numeric, payment_method text, delivery_method text, address_id uuid, coupon_code text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_cart record;
  v_product record;
  v_variant record;
  v_address record;
  v_coupon record;
  v_existing record;
  v_order_id uuid;
  v_method text := lower(trim(coalesce(p_payment_method, '')));
  v_delivery_method text := lower(trim(coalesce(p_delivery_method, 'standard')));
  v_coupon_code text := upper(trim(coalesce(p_coupon_code, '')));
  v_item_total numeric := 0;
  v_product_discount numeric := 0;
  v_coupon_discount numeric := 0;
  v_delivery_charge numeric := 0;
  v_total numeric := 0;
  v_unit_price numeric;
  v_unit_mrp numeric;
  v_stock integer;
  v_coin_limit bigint := 0;
  v_coin_discount numeric := 0;
  v_coin_balance bigint := 0;
  v_balance_after bigint := 0;
begin
  if auth.uid() is null or auth.uid() is distinct from p_customer_id then
    raise exception 'Unauthorized';
  end if;
  if p_request_id is null then
    raise exception 'Checkout request id is required';
  end if;
  if p_shubhcoins is null or p_shubhcoins < 0 then
    raise exception 'Invalid ShubhCoins amount';
  end if;
  if v_method not in ('cod', 'razorpay', 'upi', 'card', 'netbanking') then
    raise exception 'Invalid payment method';
  end if;
  if v_delivery_method not in ('standard', 'fast', 'express', 'scheduled') then
    raise exception 'Invalid delivery method';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_customer_id::text || ':' || p_request_id::text, 0));

  select o.id, o.total_amount, o.payment_method, o.delivery_method, o.address_id, o.coupon_code into v_existing
  from public."Orders" o
  where o.customer_id = p_customer_id and o.checkout_request_id = p_request_id
  limit 1;
  if found then
    select coalesce(sum(abs(amount)), 0)::bigint into v_coin_balance
    from public.shubhcoins_ledger
    where customer_id = p_customer_id and type = 'redeem' and reference_id = v_existing.id::text;
    return query select v_existing.id, v_existing.total_amount, v_coin_balance, v_coin_balance::numeric,
      v_existing.payment_method, v_existing.delivery_method, v_existing.address_id, v_existing.coupon_code;
    return;
  end if;

  select id, name, mobile, house_shop, area, city, state, pincode
  into v_address
  from public.addresses
  where id = p_address_id and customer_id = p_customer_id;
  if not found then raise exception 'Address not found'; end if;

  if not exists (select 1 from public.cart where customer_id = p_customer_id) then
    raise exception 'Cart empty';
  end if;

  -- Lock cart rows and inventory rows in a deterministic order; any exception rolls the whole transaction back.
  for v_cart in
    select id, product_id, variant_id, quantity
    from public.cart
    where customer_id = p_customer_id
    order by product_id, variant_id nulls first, id
    for update
  loop
    if coalesce(v_cart.quantity, 0) < 1 then raise exception 'Invalid cart quantity'; end if;

    select id, name, price, mrp, stock, status, is_live
    into v_product
    from public.products
    where id = v_cart.product_id
    for update;
    if not found then raise exception 'Product is no longer available'; end if;
    if v_product.status is distinct from 'Active' or not coalesce(v_product.is_live, false) then
      raise exception 'Product is no longer available';
    end if;

    if v_cart.variant_id is not null then
      select id, product_id, price, mrp, stock, status
      into v_variant
      from public.product_variants
      where id = v_cart.variant_id and product_id = v_cart.product_id
      for update;
      if not found then raise exception 'Product variant is no longer available'; end if;
      if v_variant.status is distinct from 'Active' then
        raise exception 'Product variant is no longer available';
      end if;
      v_unit_price := v_variant.price;
      v_unit_mrp := greatest(coalesce(v_variant.mrp, v_variant.price), v_variant.price);
      v_stock := coalesce(v_variant.stock, 0);
      if v_stock < v_cart.quantity then raise exception 'Insufficient stock for selected variant'; end if;
      update public.product_variants
      set stock = stock - v_cart.quantity, updated_at = now()
      where id = v_variant.id and product_id = v_cart.product_id and stock >= v_cart.quantity;
      if not found then raise exception 'Stock changed; please retry checkout'; end if;
    else
      v_unit_price := v_product.price;
      v_unit_mrp := greatest(coalesce(v_product.mrp, v_product.price), v_product.price);
      v_stock := coalesce(v_product.stock, 0);
      if v_stock < v_cart.quantity then raise exception 'Insufficient stock'; end if;
      update public.products
      set stock = stock - v_cart.quantity
      where id = v_product.id and stock >= v_cart.quantity;
      if not found then raise exception 'Stock changed; please retry checkout'; end if;
    end if;

    if v_unit_price is null or v_unit_price <= 0 then raise exception 'Invalid product price'; end if;
    v_item_total := v_item_total + (v_unit_price * v_cart.quantity);
    v_product_discount := v_product_discount + (greatest(0, v_unit_mrp - v_unit_price) * v_cart.quantity);
  end loop;

  if v_item_total <= 0 then raise exception 'Invalid order amount'; end if;

  if v_coupon_code <> '' then
    select min_order, discount_amount
    into v_coupon
    from public.coupons
    where upper(code) = v_coupon_code
      and active = true
      and start_date <= now()
      and (end_date is null or end_date >= now())
    order by created_at desc
    limit 1;
    if found then
      if v_item_total < coalesce(v_coupon.min_order, 0) then
        raise exception 'Minimum order amount for coupon not met';
      end if;
      v_coupon_discount := least(greatest(0, coalesce(v_coupon.discount_amount, 0)), v_item_total);
    elsif exists (select 1 from public.coupons where upper(code) = v_coupon_code) then
      raise exception 'Coupon invalid or expired';
    elsif v_coupon_code = 'WELCOME10' then
      v_coupon_discount := least(v_item_total * 0.10, 200);
    else
      raise exception 'Coupon invalid or expired';
    end if;
  end if;

  if v_delivery_method = 'express' then
    v_delivery_charge := 99;
  elsif v_delivery_method = 'fast' then
    v_delivery_charge := 49;
  elsif v_delivery_method = 'scheduled' then
    v_delivery_charge := 79;
  elsif v_item_total < 499 then
    v_delivery_charge := 40;
  end if;

  if p_shubhcoins > 0 then
    select balance into v_coin_balance
    from public.shubhcoins_wallets
    where customer_id = p_customer_id
    for update;
    if not found then raise exception 'ShubhCoins wallet not found'; end if;
    v_coin_limit := least(v_coin_balance, floor(v_item_total * 0.20)::bigint);
    if p_shubhcoins > v_coin_limit then
      raise exception 'Maximum % ShubhCoins can be redeemed on this order', v_coin_limit;
    end if;
    v_coin_discount := p_shubhcoins;
  end if;

  v_total := round(greatest(0, v_item_total - v_coupon_discount - v_coin_discount + v_delivery_charge), 2);
  if v_total <= 0 then raise exception 'Invalid order amount'; end if;

  insert into public."Orders"(
    customer_id, customer_name, customer_phone, total_amount, item_total, product_discount,
    coupon_code, coupon_discount, delivery_method, delivery_charge, payment_method,
    payment_status, order_status, shipping_address, address_id, currency,
    commission_amount, seller_earning, stock_reserved, checkout_request_id
  )
  values(
    p_customer_id, v_address.name, v_address.mobile, v_total, v_item_total, v_product_discount,
    nullif(v_coupon_code, ''), v_coupon_discount, v_delivery_method, v_delivery_charge, v_method,
    'Pending', 'Pending',
    concat_ws(', ', nullif(v_address.house_shop, ''), nullif(v_address.area, ''),
      nullif(v_address.city, ''), nullif(v_address.state, ''), nullif(v_address.pincode, '')),
    v_address.id, 'INR', 0, 0, true, p_request_id
  )
  returning id into v_order_id;

  insert into public."Order_items"(order_id, product_id, variant_id, quantity, unit_price, total_price)
  select v_order_id, c.product_id, c.variant_id, c.quantity,
         case when c.variant_id is not null then pv.price else p.price end,
         (case when c.variant_id is not null then pv.price else p.price end) * c.quantity
  from public.cart c
  join public.products p on p.id = c.product_id
  left join public.product_variants pv on pv.id = c.variant_id and pv.product_id = c.product_id
  where c.customer_id = p_customer_id;

  insert into public.payments(order_id, customer_id, amount, currency, method, status)
  values(v_order_id, p_customer_id, v_total, 'INR', v_method, 'Pending');

  if p_shubhcoins > 0 then
    update public.shubhcoins_wallets
    set balance = balance - p_shubhcoins,
        lifetime_spent = lifetime_spent + p_shubhcoins,
        updated_at = now()
    where customer_id = p_customer_id and balance >= p_shubhcoins
    returning balance into v_balance_after;
    if not found then raise exception 'ShubhCoins balance changed; please retry'; end if;
    insert into public.shubhcoins_ledger(customer_id, amount, balance_after, type, reference_id, note)
    values(p_customer_id, -p_shubhcoins, v_balance_after, 'redeem', v_order_id::text, 'Redeemed at checkout (₹1 per coin)');
  end if;

  return query select v_order_id, v_total, p_shubhcoins, v_coin_discount,
    v_method, v_delivery_method, v_address.id, nullif(v_coupon_code, '');
end;
$function$;

revoke all on function public.create_customer_order_secure(uuid,uuid,text,text,text,bigint,uuid) from public, anon, service_role;
grant execute on function public.create_customer_order_secure(uuid,uuid,text,text,text,bigint,uuid) to authenticated;

create or replace function public.attach_razorpay_order_secure(
  p_order_id uuid,
  p_customer_id uuid,
  p_gateway_order_id text,
  p_method text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order record;
  v_payment record;
  v_method text := lower(trim(coalesce(p_method, '')));
begin
  if p_customer_id is null then raise exception 'Customer is required'; end if;
  select id, customer_id, payment_method, payment_status, order_status, total_amount
  into v_order
  from public."Orders"
  where id = p_order_id and customer_id = p_customer_id
  for update;
  if not found then raise exception 'Order not found'; end if;
  if lower(coalesce(v_order.payment_status, 'pending')) <> 'pending'
     or lower(coalesce(v_order.order_status, 'pending')) in ('cancelled', 'delivered', 'returned', 'refunded') then
    raise exception 'Order is not payable';
  end if;
  if lower(coalesce(v_order.payment_method, '')) not in ('razorpay', 'upi', 'card', 'netbanking')
     or v_method <> lower(v_order.payment_method) then
    raise exception 'Payment method mismatch';
  end if;
  if nullif(trim(coalesce(p_gateway_order_id, '')), '') is null then
    raise exception 'Invalid gateway order id';
  end if;

  select id, customer_id, amount, status, gateway_order_id, method
  into v_payment
  from public.payments
  where order_id = p_order_id and customer_id = p_customer_id
  for update;
  if not found then raise exception 'Payment record not found'; end if;
  if round(v_payment.amount, 2) <> round(v_order.total_amount, 2) then
    raise exception 'Payment amount mismatch';
  end if;
  if lower(coalesce(v_payment.status, 'pending')) <> 'pending' then
    raise exception 'Payment is not pending';
  end if;
  if v_payment.gateway_order_id is not null and v_payment.gateway_order_id <> p_gateway_order_id then
    raise exception 'Gateway order already attached';
  end if;

  update public.payments
  set gateway = 'Razorpay', gateway_order_id = p_gateway_order_id,
      method = v_method, status = 'Pending', updated_at = now()
  where id = v_payment.id;
end;
$function$;

revoke all on function public.attach_razorpay_order_secure(uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.attach_razorpay_order_secure(uuid,uuid,text,text) to service_role;

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
  v_order record;
  v_payment record;
begin
  if p_order_id is null or p_customer_id is null
     or nullif(trim(coalesce(p_razorpay_order_id, '')), '') is null
     or nullif(trim(coalesce(p_payment_id, '')), '') is null
     or nullif(trim(coalesce(p_signature, '')), '') is null then
    raise exception 'Missing payment verification fields';
  end if;

  select o.id, o.customer_id, o.total_amount, o.payment_status, o.order_status, o.payment_transaction_id,
         p.id as payment_row_id, p.amount as payment_amount, p.status as payment_row_status,
         p.gateway_order_id, p.gateway_payment_id
  into v_order
  from public."Orders" o
  join public.payments p on p.order_id = o.id and p.customer_id = o.customer_id
  where o.id = p_order_id and o.customer_id = p_customer_id
  for update of o, p;
  if not found then raise exception 'Order/payment record not found'; end if;
  if v_order.gateway_order_id is distinct from p_razorpay_order_id then
    raise exception 'Payment gateway order mismatch';
  end if;
  if round(v_order.payment_amount, 2) <> round(v_order.total_amount, 2) then
    raise exception 'Payment amount mismatch';
  end if;

  if lower(coalesce(v_order.payment_status, 'pending')) = 'paid' then
    if v_order.payment_transaction_id = p_payment_id and v_order.gateway_payment_id = p_payment_id then
      return;
    end if;
    raise exception 'Order already paid with a different payment';
  end if;
  if lower(coalesce(v_order.payment_status, 'pending')) not in ('pending')
     or lower(coalesce(v_order.payment_row_status, 'pending')) not in ('pending')
     or lower(coalesce(v_order.order_status, 'pending')) in ('cancelled', 'returned', 'refunded') then
    raise exception 'Order is not payable';
  end if;

  update public."Orders"
  set payment_status = 'Paid', payment_transaction_id = p_payment_id
  where id = p_order_id and customer_id = p_customer_id;

  update public.payments
  set status = 'Paid', gateway = 'Razorpay', gateway_payment_id = p_payment_id,
      gateway_signature = p_signature, updated_at = now()
  where id = v_order.payment_row_id;
end;
$function$;

revoke all on function public.mark_razorpay_paid_secure(uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.mark_razorpay_paid_secure(uuid,uuid,text,text,text) to service_role;

create or replace function public.guard_customer_payment_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- Service-role mutations are permitted only for trusted server-side Edge Functions.
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    return new;
  end if;
  if private.is_admin() then return new; end if;
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

create or replace function public.cancel_unpaid_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_customer_id uuid;
  v_payment_status text;
  v_reserved boolean;
  v_gateway_order_id text;
  v_payment_row_status text;
  i record;
begin
  select o.customer_id, o.payment_status, o.stock_reserved, p.gateway_order_id, p.status
  into v_customer_id, v_payment_status, v_reserved, v_gateway_order_id, v_payment_row_status
  from public."Orders" o
  left join public.payments p on p.order_id = o.id and p.customer_id = o.customer_id
  where o.id = p_order_id
  for update of o;

  if v_customer_id is null or v_customer_id <> (select auth.uid()) then
    raise exception 'Order not found or not owned by customer';
  end if;
  if lower(coalesce(v_payment_status, 'pending')) not in ('pending', 'failed', 'cancelled') then
    raise exception 'Paid order cannot be cancelled by this action';
  end if;
  if v_gateway_order_id is not null
     and lower(coalesce(v_payment_row_status, 'pending')) not in ('failed', 'cancelled') then
    raise exception 'Gateway payment attempt must be reconciled before cancellation';
  end if;

  if coalesce(v_reserved, false) then
    for i in
      select product_id, variant_id, quantity
      from public."Order_items"
      where order_id = p_order_id
    loop
      if i.variant_id is not null then
        update public.product_variants
        set stock = stock + i.quantity
        where id = i.variant_id and product_id = i.product_id;
      else
        update public.products
        set stock = stock + i.quantity
        where id = i.product_id;
      end if;
    end loop;
  end if;

  -- Release any ShubhCoins before deleting the order, while the order and ledger reference still exist.
  perform public.release_shubhcoins_for_order(p_order_id);

  delete from public.payments where order_id = p_order_id and customer_id = (select auth.uid());
  delete from public."Order_items" where order_id = p_order_id;
  delete from public."Orders" where id = p_order_id and customer_id = (select auth.uid());
end;
$function$;

revoke all on function public.cancel_unpaid_order(uuid) from public, anon;
grant execute on function public.cancel_unpaid_order(uuid) to authenticated;
