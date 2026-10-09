import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const url = Deno.env.get("SUPABASE_URL")!;
const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")!);
const secret = keys["default"];
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

// Preserve actionable checkout validation messages, but do not return arbitrary
// Postgres/PostgREST errors (which can reveal schema and implementation details).
const safeCheckoutError = (message: string) => {
  const knownPrefixes = [
    "Unauthorized",
    "Invalid payment method",
    "Invalid delivery method",
    "Address not found",
    "Cart empty",
    "Invalid product price",
    "Insufficient stock",
    "Product is no longer active",
    "Invalid order amount",
    "ShubhCoins wallet not found",
    "Maximum ",
  ];
  return knownPrefixes.some((prefix) => message.startsWith(prefix))
    ? message
    : "Unable to create order. Please review your cart and try again.";
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = req.headers.get("Authorization");
    const apiKey = req.headers.get("apikey");
    if (!authorization?.startsWith("Bearer ") || !apiKey) {
      return json({ error: "Unauthorized" }, 401);
    }

    // Verify the bearer token server-side before trusting the user identity.
    const admin = createClient(url, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: userError } =
      await admin.auth.getUser(authorization.slice(7));
    if (userError || !user) return json({ error: "Unauthorized" }, 401);

    const body = await req.json();
    const addressId = body?.address_id;
    const method = String(body?.payment_method || "razorpay").toLowerCase();
    const delivery = String(body?.delivery_method || "standard").toLowerCase();
    const coupon = String(body?.coupon_code || "").trim().toUpperCase();
    const coins = Math.max(0, Math.floor(Number(body?.shubhcoins || 0)));

    if (!addressId || typeof addressId !== "string") {
      return json({ error: "Address is required" }, 400);
    }

    // Important: preserve the verified customer's JWT for auth.uid() inside
    // create_order_from_cart_with_coins. A service-role RPC call has no customer
    // auth.uid() and will fail the database function's ownership check.
    const customer = createClient(url, apiKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await customer.rpc("create_order_from_cart_with_coins", {
      p_customer_id: user.id,
      p_address_id: addressId,
      p_payment_method: method,
      p_delivery_method: delivery,
      p_coupon_code: coupon,
      p_shubhcoins: coins,
    });

    if (error) return json({ error: safeCheckoutError(error.message) }, 400);
    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.order_id) return json({ error: "Order creation failed" }, 500);

    return json({
      success: true,
      order_id: row.order_id,
      amount: Number(row.total_amount),
      currency: "INR",
      coins_redeemed: Number(row.coins_redeemed || 0),
      coin_discount: Number(row.coin_discount || 0),
    });
  } catch (error) {
    return json({ error: "Server error. Please try again later." }, 500);
  }
});
