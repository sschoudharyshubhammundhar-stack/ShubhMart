-- DRAFT ONLY — DO NOT APPLY TO THE CONNECTED / PRODUCTION DATABASE.
-- Roadmap stage: variant-aware stock reservation.
-- This is a complete candidate replacement based on a read-only snapshot of
-- public.create_order_from_cart_with_coins from 2026-10-10. It is NOT approved.
-- No live SQL has been executed by this draft.
--
-- IMPORTANT RELEASE GATES:
-- 1. Validate every referenced column, constraint, trigger, RLS/grant, and
--    payment/refund/cancellation path in an isolated database.
-- 2. This draft DOES NOT implement database-backed idempotency. Do not release
--    until duplicate checkout retries are handled transactionally.
-- 3. This draft preserves the current one-order-per-cart model; it does not
--    solve multi-seller order splitting.
-- 4. Verify variant status/lifecycle rules and price semantics before use.
-- 5. Test COD, Razorpay, coins, coupons, cancellation and unpaid cleanup with
--    synthetic data before considering any production migration.
--
-- Candidate function replacement (review only; not a migration):
-- Existing signature/result are retained so current callers remain compatible.

CREATE OR REPLACE FUNCTION public.create_order_from_cart_with_coins(
  p_customer_id uuid,
  p_address_id uuid,
  p_payment_method text DEFAULT 'razorpay'::text,
  p_delivery_method text DEFAULT 'standard'::text,
  p_coupon_code text DEFAULT ''::text,
  p_shubhcoins bigint DEFAULT 0
)
RETURNS TABLE(order_id uuid, total_amount numeric, coins_redeemed bigint, coin_discount numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_order_id uuid;
  v_item_total numeric := 0;
  v_product_discount numeric := 0;
  v_coupon numeric := 0;
  v_delivery numeric := 0;
  v_total numeric := 0;
  v_address record;
  v_item record;
  v_product public.products%ROWTYPE;
  v_variant public.product_variants%ROWTYPE;
  v_wallet public.shubhcoins_wallets%ROWTYPE;
  v_coin_discount numeric := 0;
  v_coin_limit bigint := 0;
  v_requested bigint := greatest(0, coalesce(p_shubhcoins, 0));
  v_delivery_method text := lower(coalesce(p_delivery_method, 'standard'));
  v_coupon_code text := upper(trim(coalesce(p_coupon_code, '')));
  v_unit_price numeric;
  v_mrp numeric;
BEGIN
  IF p_customer_id IS NULL OR auth.uid() IS NULL OR auth.uid() <> p_customer_id THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF lower(p_payment_method) NOT IN ('cod','razorpay','upi','card','netbanking') THEN
    RAISE EXCEPTION 'Invalid payment method';
  END IF;
  IF v_delivery_method NOT IN ('standard','fast','express','scheduled') THEN
    RAISE EXCEPTION 'Invalid delivery method';
  END IF;

  SELECT id, name, mobile, house_shop, area, city, state, pincode
    INTO v_address
    FROM public.addresses
   WHERE id = p_address_id AND customer_id = p_customer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Address not found'; END IF;

  -- Lock cart rows in a deterministic order; lock the actual inventory rows
  -- below in the same product_id / variant_id order.
  PERFORM c.id
    FROM public.cart AS c
   WHERE c.customer_id = p_customer_id
   ORDER BY c.product_id, c.variant_id NULLS FIRST
   FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Cart empty'; END IF;

  FOR v_item IN
    SELECT c.product_id, c.variant_id, c.quantity
      FROM public.cart AS c
     WHERE c.customer_id = p_customer_id
     ORDER BY c.product_id, c.variant_id NULLS FIRST
  LOOP
    IF v_item.quantity IS NULL OR v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity';
    END IF;

    SELECT * INTO v_product
      FROM public.products
     WHERE id = v_item.product_id
     FOR UPDATE;
    IF NOT FOUND OR v_product.status <> 'Active' THEN
      RAISE EXCEPTION 'Product is no longer active';
    END IF;

    IF v_item.variant_id IS NOT NULL THEN
      SELECT * INTO v_variant
        FROM public.product_variants
       WHERE id = v_item.variant_id
         AND product_id = v_item.product_id
         AND status = 'Active'
       FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Selected variant is unavailable'; END IF;

      v_unit_price := v_variant.price;
      v_mrp := v_variant.mrp;
      IF v_unit_price IS NULL OR v_unit_price < 0 THEN
        RAISE EXCEPTION 'Invalid product price: %', v_product.name;
      END IF;

      -- Variant owns its inventory: do not also decrement parent product stock.
      UPDATE public.product_variants
         SET stock = stock - v_item.quantity,
             updated_at = now()
       WHERE id = v_variant.id
         AND product_id = v_product.id
         AND stock >= v_item.quantity;
      IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient stock: %', v_product.name; END IF;
    ELSE
      v_unit_price := v_product.price;
      v_mrp := v_product.mrp;
      IF v_unit_price IS NULL OR v_unit_price < 0 THEN
        RAISE EXCEPTION 'Invalid product price: %', v_product.name;
      END IF;

      UPDATE public.products
         SET stock = stock - v_item.quantity
       WHERE id = v_product.id
         AND stock >= v_item.quantity;
      IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient stock: %', v_product.name; END IF;
    END IF;

    v_item_total := v_item_total + (v_unit_price * v_item.quantity);
    v_product_discount := v_product_discount
      + (greatest(0, coalesce(v_mrp, v_unit_price) - v_unit_price) * v_item.quantity);
  END LOOP;

  IF v_item_total <= 0 THEN RAISE EXCEPTION 'Invalid order amount'; END IF;

  IF v_coupon_code = 'WELCOME10' THEN
    v_coupon := least(v_item_total * 0.10, 200);
  ELSE
    v_coupon := 0;
    v_coupon_code := NULL;
  END IF;

  IF v_delivery_method = 'express' THEN
    v_delivery := 99;
  ELSIF v_delivery_method = 'fast' THEN
    v_delivery := 49;
  ELSIF v_delivery_method = 'scheduled' THEN
    v_delivery := 79;
  ELSIF v_item_total < 499 THEN
    v_delivery := 40;
  ELSE
    v_delivery := 0;
  END IF;

  IF v_requested > 0 THEN
    SELECT * INTO v_wallet
      FROM public.shubhcoins_wallets
     WHERE customer_id = p_customer_id
     FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'ShubhCoins wallet not found'; END IF;

    v_coin_limit := least(v_wallet.balance, floor(v_item_total * 0.20)::bigint);
    IF v_requested > v_coin_limit THEN
      RAISE EXCEPTION 'Maximum % ShubhCoins can be redeemed on this order', v_coin_limit;
    END IF;
    v_coin_discount := v_requested;
  END IF;

  v_total := greatest(0, v_item_total - v_coupon - v_coin_discount + v_delivery);
  IF v_total <= 0 THEN RAISE EXCEPTION 'Invalid order amount'; END IF;

  INSERT INTO public."Orders"(
    customer_id, customer_name, customer_phone, total_amount, item_total,
    product_discount, coupon_code, coupon_discount, delivery_method,
    delivery_charge, payment_method, payment_status, order_status,
    shipping_address, address_id, currency, commission_amount, seller_earning,
    stock_reserved
  )
  VALUES (
    p_customer_id, v_address.name, v_address.mobile, v_total, v_item_total,
    v_product_discount, v_coupon_code, v_coupon, v_delivery_method,
    v_delivery, lower(p_payment_method), 'Pending', 'Pending',
    concat_ws(', ', nullif(v_address.house_shop,''), nullif(v_address.area,''),
      nullif(v_address.city,''), nullif(v_address.state,''), nullif(v_address.pincode,'')),
    v_address.id, 'INR', 0, 0, true
  )
  RETURNING id INTO v_order_id;

  -- Persist the chosen variant and the same effective price used for totals.
  INSERT INTO public."Order_items"(order_id, product_id, variant_id, quantity, unit_price, total_price)
  SELECT v_order_id, c.product_id, c.variant_id, c.quantity,
         CASE WHEN c.variant_id IS NOT NULL THEN pv.price ELSE p.price END,
         CASE WHEN c.variant_id IS NOT NULL THEN pv.price ELSE p.price END * c.quantity
    FROM public.cart AS c
    JOIN public.products AS p ON p.id = c.product_id
    LEFT JOIN public.product_variants AS pv
      ON pv.id = c.variant_id AND pv.product_id = c.product_id
   WHERE c.customer_id = p_customer_id;

  INSERT INTO public.payments(order_id, customer_id, amount, currency, method, status)
  VALUES (v_order_id, p_customer_id, v_total, 'INR', lower(p_payment_method), 'Pending');

  IF v_requested > 0 THEN
    UPDATE public.shubhcoins_wallets
       SET balance = balance - v_requested,
           lifetime_spent = lifetime_spent + v_requested,
           updated_at = now()
     WHERE customer_id = p_customer_id;

    INSERT INTO public.shubhcoins_ledger(customer_id, amount, balance_after, type, reference_id, note)
    SELECT customer_id, -v_requested, balance, 'redeem', v_order_id::text,
           'Redeemed at checkout (₹1 per coin)'
      FROM public.shubhcoins_wallets
     WHERE customer_id = p_customer_id;
  END IF;

  RETURN QUERY SELECT v_order_id, v_total, v_requested, v_coin_discount;
END;
$function$;

-- Do not apply until separately reviewed: function grants, idempotency design,
-- cancellation/payment-failure consistency, and all lifecycle tests.
