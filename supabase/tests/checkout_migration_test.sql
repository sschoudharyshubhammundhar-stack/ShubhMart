\set ON_ERROR_STOP on

-- Disposable PostgreSQL schema to exercise the checkout migration without production data.
DO $$
BEGIN
  CREATE ROLE anon;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  CREATE ROLE authenticated;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  CREATE ROLE service_role;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS private;
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS jsonb LANGUAGE sql STABLE
AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $$;
CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean LANGUAGE sql STABLE
AS $$ SELECT false $$;

CREATE TABLE public."Sellers" (
  id uuid PRIMARY KEY,
  user_id uuid,
  status text
);
CREATE TABLE public.addresses (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL,
  name text,
  mobile text,
  house_shop text,
  area text,
  city text,
  state text,
  pincode text
);
CREATE TABLE public.products (
  id uuid PRIMARY KEY,
  name text,
  price numeric,
  mrp numeric,
  stock integer,
  status text,
  is_live boolean,
  seller_id uuid,
  commission_rate numeric,
  approved_at timestamptz,
  approved_by uuid,
  rejection_reason text,
  compliance_status text,
  compliance_notes text,
  ai_status text,
  ai_reviewed_by_seller boolean,
  wholesale_enabled boolean,
  wholesale_moq integer,
  wholesale_price numeric,
  created_at timestamptz DEFAULT now()
);
CREATE TABLE public.product_variants (
  id uuid PRIMARY KEY,
  product_id uuid NOT NULL,
  price numeric,
  mrp numeric,
  stock integer,
  status text,
  updated_at timestamptz DEFAULT now()
);
CREATE TABLE public.cart (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL,
  product_id uuid NOT NULL,
  variant_id uuid,
  quantity integer NOT NULL
);
CREATE TABLE public."Orders" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid,
  customer_name text,
  customer_phone text,
  total_amount numeric,
  item_total numeric,
  product_discount numeric,
  coupon_code text,
  coupon_discount numeric,
  delivery_method text,
  delivery_charge numeric,
  payment_method text,
  payment_status text,
  order_status text,
  shipping_address text,
  address_id uuid,
  currency text,
  commission_amount numeric,
  seller_earning numeric,
  stock_reserved boolean DEFAULT false,
  payment_transaction_id text
);
CREATE TABLE public."Order_items" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL,
  product_id uuid NOT NULL,
  variant_id uuid,
  quantity integer NOT NULL,
  unit_price numeric NOT NULL,
  total_price numeric NOT NULL
);
CREATE TABLE public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  amount numeric,
  currency text,
  method text,
  status text,
  gateway text,
  gateway_order_id text,
  gateway_payment_id text,
  gateway_signature text,
  updated_at timestamptz DEFAULT now()
);
CREATE TABLE public.coupons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text,
  min_order numeric,
  discount_amount numeric,
  start_date timestamptz DEFAULT now(),
  end_date timestamptz,
  category text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE TABLE public.shubhcoins_wallets (
  customer_id uuid PRIMARY KEY,
  balance bigint DEFAULT 0,
  lifetime_earned bigint DEFAULT 0,
  lifetime_spent bigint DEFAULT 0,
  updated_at timestamptz DEFAULT now()
);
CREATE TABLE public.shubhcoins_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL,
  amount bigint NOT NULL,
  balance_after bigint NOT NULL,
  type text NOT NULL,
  reference_id text,
  note text,
  created_at timestamptz DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.calculate_order_financials()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.commission_amount := round(coalesce(NEW.total_amount,0) * 0.10, 2);
  NEW.seller_earning := greatest(coalesce(NEW.total_amount,0) - NEW.commission_amount, 0);
  RETURN NEW;
END $$;
CREATE TRIGGER trg_calculate_order_financials
BEFORE INSERT OR UPDATE OF total_amount ON public."Orders"
FOR EACH ROW EXECUTE FUNCTION public.calculate_order_financials();

CREATE OR REPLACE FUNCTION public.guard_customer_payment_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_order record;
BEGIN
  IF private.is_admin() THEN RETURN NEW; END IF;
  IF auth.uid() IS NULL OR NEW.customer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Payment customer mismatch';
  END IF;
  SELECT total_amount, currency INTO v_order
  FROM public."Orders" WHERE id = NEW.order_id AND customer_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment order access denied'; END IF;
  NEW.customer_id := auth.uid();
  NEW.amount := v_order.total_amount;
  NEW.currency := coalesce(v_order.currency, 'INR');
  NEW.status := 'Pending';
  NEW.gateway := NULL;
  NEW.gateway_order_id := NULL;
  NEW.gateway_payment_id := NULL;
  NEW.gateway_signature := NULL;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_guard_customer_payment_insert
BEFORE INSERT ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.guard_customer_payment_insert();

CREATE OR REPLACE FUNCTION public.guard_customer_payment_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN NEW;
END $$;
CREATE TRIGGER trg_guard_customer_payment_update
BEFORE UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.guard_customer_payment_update();

CREATE OR REPLACE FUNCTION public.protect_product_admin_fields()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN NEW;
END $$;
CREATE TRIGGER trg_protect_product_admin_fields
BEFORE UPDATE ON public.products
FOR EACH ROW EXECUTE FUNCTION public.protect_product_admin_fields();

CREATE OR REPLACE FUNCTION public.release_shubhcoins_for_order(p_order_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_customer uuid; v_status text; v_amount bigint; v_balance bigint;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT customer_id, payment_status INTO v_customer, v_status
  FROM public."Orders" WHERE id = p_order_id AND customer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF v_status = 'Paid' THEN RETURN false; END IF;
  SELECT amount INTO v_amount FROM public.shubhcoins_ledger
  WHERE customer_id = auth.uid() AND type = 'redeem' AND reference_id = p_order_id::text
  FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM public.shubhcoins_ledger WHERE customer_id = auth.uid() AND type = 'coin_release' AND reference_id = p_order_id::text) THEN
    RETURN false;
  END IF;
  UPDATE public.shubhcoins_wallets
  SET balance = balance + abs(v_amount), lifetime_spent = greatest(0, lifetime_spent - abs(v_amount)), updated_at = now()
  WHERE customer_id = auth.uid() RETURNING balance INTO v_balance;
  INSERT INTO public.shubhcoins_ledger(customer_id,amount,balance_after,type,reference_id,note)
  VALUES(auth.uid(),abs(v_amount),v_balance,'coin_release',p_order_id::text,'Test release');
  RETURN true;
END $$;

\ir ../migrations/20261009_secure_checkout_order_payment_flow.sql

DO $$
DECLARE
  v_customer uuid := '11111111-1111-4111-8111-111111111111';
  v_other uuid := '22222222-2222-4222-8222-222222222222';
  v_address uuid := '33333333-3333-4333-8333-333333333333';
  v_product uuid := '44444444-4444-4444-8444-444444444444';
  v_variant_product uuid := '55555555-5555-4555-8555-555555555555';
  v_variant uuid := '66666666-6666-4666-8666-666666666666';
  v_hidden uuid := '77777777-7777-4777-8777-777777777777';
  v_expensive uuid := '88888888-8888-4888-8888-888888888888';
  v_request uuid := '99999999-9999-4999-8999-999999999991';
  v_request_online uuid := '99999999-9999-4999-8999-999999999992';
  v_request_variant_cancel uuid := '99999999-9999-4999-8999-999999999993';
  v_request_hidden uuid := '99999999-9999-4999-8999-999999999994';
  v_request_coins uuid := '99999999-9999-4999-8999-999999999995';
  v_order uuid;
  v_again uuid;
  v_result record;
  v_message text;
  v_failed boolean;
  v_stock integer;
  v_balance bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', v_customer::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_customer::text,'role','authenticated')::text, false);

  INSERT INTO public.addresses VALUES(v_address,v_customer,'Test Customer','9999999999','House 1','Main Road','Laksar','Uttarakhand','247663');
  INSERT INTO public.products(id,name,price,mrp,stock,status,is_live) VALUES
    (v_product,'Basic test product',100,150,10,'Active',true),
    (v_variant_product,'Variant parent product',120,160,50,'Active',true),
    (v_hidden,'Hidden test product',200,250,5,'Active',false),
    (v_expensive,'High value test product',1000,1200,10,'Active',true);
  INSERT INTO public.product_variants(id,product_id,price,mrp,stock,status)
  VALUES(v_variant,v_variant_product,150,200,4,'Active');
  INSERT INTO public.shubhcoins_wallets(customer_id,balance,lifetime_earned,lifetime_spent)
  VALUES(v_customer,100,100,0);

  INSERT INTO public.cart(customer_id,product_id,quantity) VALUES(v_customer,v_product,2);
  SELECT * INTO v_result FROM public.create_customer_order_secure(v_customer,v_address,'cod','standard','',10,v_request);
  v_order := v_result.order_id;
  IF v_result.total_amount <> 230 OR v_result.coins_redeemed <> 10 OR v_result.payment_method <> 'cod' THEN
    RAISE EXCEPTION 'basic checkout result mismatch: %', row_to_json(v_result);
  END IF;
  IF (SELECT stock FROM public.products WHERE id=v_product) <> 8 THEN RAISE EXCEPTION 'product stock was not reserved'; END IF;
  IF (SELECT balance FROM public.shubhcoins_wallets WHERE customer_id=v_customer) <> 90 THEN RAISE EXCEPTION 'ShubhCoins were not redeemed'; END IF;
  IF (SELECT count(*) FROM public."Order_items" WHERE order_id=v_order AND variant_id IS NULL AND unit_price=100 AND quantity=2) <> 1 THEN
    RAISE EXCEPTION 'order item price/quantity mismatch';
  END IF;

  SELECT * INTO v_result FROM public.create_customer_order_secure(v_customer,v_address,'cod','standard','',10,v_request);
  v_again := v_result.order_id;
  IF v_again <> v_order THEN RAISE EXCEPTION 'idempotency did not return the original order'; END IF;
  IF (SELECT stock FROM public.products WHERE id=v_product) <> 8 THEN RAISE EXCEPTION 'idempotent retry reserved stock twice'; END IF;
  IF (SELECT balance FROM public.shubhcoins_wallets WHERE customer_id=v_customer) <> 90 THEN RAISE EXCEPTION 'idempotent retry redeemed coins twice'; END IF;

  PERFORM public.cancel_unpaid_order(v_order);
  IF (SELECT stock FROM public.products WHERE id=v_product) <> 10 THEN RAISE EXCEPTION 'cancel did not restore product stock'; END IF;
  IF (SELECT balance FROM public.shubhcoins_wallets WHERE customer_id=v_customer) <> 100 THEN RAISE EXCEPTION 'cancel did not release ShubhCoins'; END IF;
  IF EXISTS(SELECT 1 FROM public."Orders" WHERE id=v_order) THEN RAISE EXCEPTION 'unpaid order was not removed on cancel'; END IF;
  DELETE FROM public.cart WHERE customer_id=v_customer;

  INSERT INTO public.cart(customer_id,product_id,variant_id,quantity) VALUES(v_customer,v_variant_product,v_variant,2);
  SELECT * INTO v_result FROM public.create_customer_order_secure(v_customer,v_address,'upi','standard','',0,v_request_online);
  v_order := v_result.order_id;
  IF (SELECT stock FROM public.product_variants WHERE id=v_variant) <> 2 THEN RAISE EXCEPTION 'variant stock was not reserved'; END IF;
  IF (SELECT stock FROM public.products WHERE id=v_variant_product) <> 50 THEN RAISE EXCEPTION 'variant checkout incorrectly changed parent stock'; END IF;
  IF (SELECT count(*) FROM public."Order_items" WHERE order_id=v_order AND variant_id=v_variant AND unit_price=150 AND quantity=2) <> 1 THEN
    RAISE EXCEPTION 'variant id/price was not preserved in order item';
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_customer::text,'role','service_role')::text, false);
  PERFORM public.attach_razorpay_order_secure(v_order,v_customer,'rp_order_test_1','upi');
  v_failed := false;
  BEGIN
    PERFORM public.cancel_unpaid_order(v_order);
  EXCEPTION WHEN OTHERS THEN
    v_message := SQLERRM;
    v_failed := true;
  END;
  IF NOT v_failed OR v_message <> 'Gateway payment attempt must be reconciled before cancellation' THEN
    RAISE EXCEPTION 'unresolved gateway payment must not be deleted, got: %', v_message;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public."Orders" WHERE id=v_order) OR (SELECT stock FROM public.product_variants WHERE id=v_variant) <> 2 THEN
    RAISE EXCEPTION 'gateway-linked order/stock was changed by refused cancellation';
  END IF;
  PERFORM public.mark_razorpay_paid_secure(v_order,v_customer,'rp_order_test_1','pay_test_1','test-signature');
  IF (SELECT payment_status FROM public."Orders" WHERE id=v_order) <> 'Paid' THEN RAISE EXCEPTION 'secure paid RPC did not mark order paid'; END IF;
  IF (SELECT status FROM public.payments WHERE order_id=v_order) <> 'Paid' THEN RAISE EXCEPTION 'payment row was not marked paid'; END IF;
  IF (SELECT gateway_payment_id FROM public.payments WHERE order_id=v_order) <> 'pay_test_1' THEN RAISE EXCEPTION 'gateway payment id not stored'; END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_customer::text,'role','authenticated')::text, false);
  DELETE FROM public.cart WHERE customer_id=v_customer;
  INSERT INTO public.cart(customer_id,product_id,variant_id,quantity) VALUES(v_customer,v_variant_product,v_variant,1);
  SELECT * INTO v_result FROM public.create_customer_order_secure(v_customer,v_address,'cod','standard','',0,v_request_variant_cancel);
  v_order := v_result.order_id;
  IF (SELECT stock FROM public.product_variants WHERE id=v_variant) <> 1 THEN RAISE EXCEPTION 'variant stock not reserved for cancellation test'; END IF;
  PERFORM public.cancel_unpaid_order(v_order);
  IF (SELECT stock FROM public.product_variants WHERE id=v_variant) <> 2 THEN RAISE EXCEPTION 'variant stock not restored after cancellation'; END IF;

  DELETE FROM public.cart WHERE customer_id=v_customer;
  INSERT INTO public.cart(customer_id,product_id,quantity) VALUES(v_customer,v_hidden,1);
  v_failed := false;
  BEGIN
    SELECT * INTO v_result FROM public.create_customer_order_secure(v_customer,v_address,'cod','standard','',0,v_request_hidden);
  EXCEPTION WHEN OTHERS THEN
    v_message := SQLERRM;
    v_failed := true;
  END;
  IF NOT v_failed OR v_message NOT LIKE 'Product is no longer available%' THEN RAISE EXCEPTION 'hidden product should be rejected, got: %', v_message; END IF;
  IF (SELECT stock FROM public.products WHERE id=v_hidden) <> 5 THEN RAISE EXCEPTION 'hidden product stock changed after failed order'; END IF;

  DELETE FROM public.cart WHERE customer_id=v_customer;
  INSERT INTO public.cart(customer_id,product_id,quantity) VALUES(v_customer,v_expensive,1);
  v_failed := false;
  BEGIN
    SELECT * INTO v_result FROM public.create_customer_order_secure(v_customer,v_address,'cod','standard','',101,v_request_coins);
  EXCEPTION WHEN OTHERS THEN
    v_message := SQLERRM;
    v_failed := true;
  END;
  IF NOT v_failed OR v_message NOT LIKE 'Maximum 100 ShubhCoins%' THEN RAISE EXCEPTION 'over-limit ShubhCoins should be rejected, got: %', v_message; END IF;
  IF (SELECT stock FROM public.products WHERE id=v_expensive) <> 10 THEN RAISE EXCEPTION 'stock changed after coin validation failure'; END IF;
  IF (SELECT balance FROM public.shubhcoins_wallets WHERE customer_id=v_customer) <> 100 THEN RAISE EXCEPTION 'wallet changed after coin validation failure'; END IF;

  PERFORM set_config('request.jwt.claim.sub', v_other::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_other::text,'role','authenticated')::text, false);
  v_failed := false;
  BEGIN
    SELECT * INTO v_result FROM public.create_customer_order_secure(v_customer,v_address,'cod','standard','',0,gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN
    v_message := SQLERRM;
    v_failed := true;
  END;
  IF NOT v_failed OR v_message <> 'Unauthorized' THEN RAISE EXCEPTION 'cross-customer order creation should be rejected, got: %', v_message; END IF;

  RAISE NOTICE 'PASS: checkout migration tests completed';
END $$;

\echo 'PASS: checkout migration integration test completed'
