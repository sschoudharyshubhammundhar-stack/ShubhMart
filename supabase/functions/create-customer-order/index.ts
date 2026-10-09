import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

const allowedOrigins = new Set([
  "https://shubhmart.sschoudharyshubhammundhar.workers.dev",
  "http://localhost:8787",
]);

function corsHeaders(req: Request) {
  const headers = new Headers({
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  });
  const origin = req.headers.get("Origin");
  if (origin && allowedOrigins.has(origin)) headers.set("Access-Control-Allow-Origin", origin);
  return headers;
}

function json(req: Request, body: unknown, status = 200) {
  const headers = corsHeaders(req);
  headers.set("Content-Type", "application/json");
  return new Response(JSON.stringify(body), { status, headers });
}

function safeOrderError(message: string) {
  const known = [
    "Unauthorized",
    "Checkout request id is required",
    "Invalid ShubhCoins amount",
    "Invalid payment method",
    "Invalid delivery method",
    "Address not found",
    "Cart empty",
    "Product is no longer available",
    "Product variant is no longer available",
    "Invalid cart quantity",
    "Insufficient stock",
    "Insufficient stock for selected variant",
    "Stock changed; please retry checkout",
    "Invalid product price",
    "Invalid order amount",
    "Minimum order amount for coupon not met",
    "Coupon invalid or expired",
    "ShubhCoins wallet not found",
    "ShubhCoins balance changed; please retry",
  ];
  return known.find((item) => message.includes(item)) ?? null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json(req, { error: "Unauthorized" }, 401);

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const token = authorization.slice("Bearer ".length);
    const { data: { user }, error: authError } = await userClient.auth.getUser(token);
    if (authError || !user) return json(req, { error: "Unauthorized" }, 401);

    const body = await req.json().catch(() => null);
    if (!body || typeof body !== "object") return json(req, { error: "Invalid request body" }, 400);

    const addressId = String(body.address_id ?? "");
    const requestId = String(body.request_id ?? "");
    const paymentMethod = String(body.payment_method ?? "cod").trim().toLowerCase();
    const deliveryMethod = String(body.delivery_method ?? "standard").trim().toLowerCase();
    const couponCode = String(body.coupon_code ?? "").trim().toUpperCase();
    const coinsValue = Number(body.shubhcoins ?? 0);

    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidPattern.test(addressId)) return json(req, { error: "Address is required" }, 400);
    if (!uuidPattern.test(requestId)) return json(req, { error: "Checkout request id is required" }, 400);
    if (!Number.isSafeInteger(coinsValue) || coinsValue < 0) return json(req, { error: "Invalid ShubhCoins amount" }, 400);
    if (!["cod", "razorpay", "upi", "card", "netbanking"].includes(paymentMethod)) {
      return json(req, { error: "Invalid payment method" }, 400);
    }
    if (!["standard", "fast", "express", "scheduled"].includes(deliveryMethod)) {
      return json(req, { error: "Invalid delivery method" }, 400);
    }

    const { data, error } = await userClient.rpc("create_customer_order_secure", {
      p_customer_id: user.id,
      p_address_id: addressId,
      p_payment_method: paymentMethod,
      p_delivery_method: deliveryMethod,
      p_coupon_code: couponCode,
      p_shubhcoins: coinsValue,
      p_request_id: requestId,
    });

    if (error) {
      const safe = safeOrderError(error.message ?? "");
      if (safe) return json(req, { error: safe }, 400);
      console.error("create_customer_order_secure failed", { code: error.code, message: error.message });
      return json(req, { error: "Order could not be created. Please review your cart and try again." }, 500);
    }

    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.order_id || !Number.isFinite(Number(row.total_amount)) || Number(row.total_amount) <= 0) {
      return json(req, { error: "Order could not be created. Please retry." }, 500);
    }

    return json(req, {
      success: true,
      order_id: row.order_id,
      amount: Number(row.total_amount),
      currency: "INR",
      coins_redeemed: Number(row.coins_redeemed ?? 0),
      coin_discount: Number(row.coin_discount ?? 0),
      payment_method: String(row.payment_method ?? ""),
      delivery_method: String(row.delivery_method ?? ""),
      address_id: String(row.address_id ?? ""),
      coupon_code: row.coupon_code ? String(row.coupon_code) : "",
    });
  } catch (error) {
    console.error("create-customer-order request failed", error instanceof Error ? error.message : "unknown error");
    return json(req, { error: "Order could not be created. Please try again." }, 500);
  }
});
