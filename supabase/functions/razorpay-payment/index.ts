import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
const serviceRoleKey = secretKeys["default"] as string | undefined;
const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

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

function constantTimeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}

async function razorpay(path: string, init: RequestInit = {}) {
  if (!razorpayKeyId || !razorpayKeySecret) throw new Error("Payment gateway is not configured");
  const authorization = "Basic " + btoa(razorpayKeyId + ":" + razorpayKeySecret);
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json");
  headers.set("Authorization", authorization);
  const response = await fetch("https://api.razorpay.com/v1" + path, { ...init, headers });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error("Payment gateway request failed");
  return data;
}

function cents(amount: unknown) {
  const value = Number(amount);
  if (!Number.isFinite(value) || value <= 0) throw new Error("Invalid order amount");
  const result = Math.round(value * 100);
  if (!Number.isSafeInteger(result) || result <= 0) throw new Error("Invalid order amount");
  return result;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json(req, { error: "Unauthorized" }, 401);
    if (!serviceRoleKey) return json(req, { error: "Payment service is temporarily unavailable" }, 503);

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const token = authorization.slice("Bearer ".length);
    const { data: { user }, error: authError } = await userClient.auth.getUser(token);
    if (authError || !user) return json(req, { error: "Unauthorized" }, 401);

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const body = await req.json().catch(() => null);
    if (!body || typeof body !== "object") return json(req, { error: "Invalid request body" }, 400);

    if (body.action === "create_order") {
      const orderId = String(body.order_id ?? "");
      if (!orderId) return json(req, { error: "Invalid order" }, 400);

      const { data: order, error: orderError } = await userClient
        .from("Orders")
        .select("id,total_amount,customer_id,payment_method,payment_status,order_status,currency")
        .eq("id", orderId)
        .eq("customer_id", user.id)
        .maybeSingle();
      if (orderError || !order) return json(req, { error: "Order not found" }, 404);

      const method = String(order.payment_method ?? "").toLowerCase();
      if (!["razorpay", "upi", "card", "netbanking"].includes(method)) {
        return json(req, { error: "This order does not use online payment" }, 400);
      }
      if (String(order.payment_status ?? "").toLowerCase() === "paid") {
        return json(req, { error: "Order is already paid" }, 409);
      }
      if (["cancelled", "delivered", "returned", "refunded"].includes(String(order.order_status ?? "").toLowerCase())) {
        return json(req, { error: "Order is not payable" }, 409);
      }
      if (String(order.currency ?? "INR").toUpperCase() !== "INR") {
        return json(req, { error: "Unsupported order currency" }, 400);
      }
      const amountPaise = cents(order.total_amount);

      const { data: payment, error: paymentError } = await userClient
        .from("payments")
        .select("id,amount,currency,method,status,gateway_order_id")
        .eq("order_id", orderId)
        .eq("customer_id", user.id)
        .maybeSingle();
      if (paymentError || !payment) return json(req, { error: "Payment record not found" }, 404);
      if (Math.round(Number(payment.amount) * 100) !== amountPaise) {
        return json(req, { error: "Payment amount mismatch" }, 409);
      }
      if (String(payment.status ?? "").toLowerCase() !== "pending") {
        return json(req, { error: "Payment is not pending" }, 409);
      }

      if (payment.gateway_order_id) {
        const existing = await razorpay("/orders/" + encodeURIComponent(payment.gateway_order_id));
        if (Number(existing.amount) !== amountPaise || String(existing.currency).toUpperCase() !== "INR") {
          return json(req, { error: "Existing payment order does not match this order" }, 409);
        }
        return json(req, {
          key_id: razorpayKeyId,
          razorpay_order_id: existing.id,
          amount: amountPaise,
          currency: "INR",
        });
      }

      const gatewayOrder = await razorpay("/orders", {
        method: "POST",
        body: JSON.stringify({
          amount: amountPaise,
          currency: "INR",
          receipt: "shubhmart_" + String(order.id).slice(0, 20),
          notes: { shubhmart_order_id: String(order.id), customer_id: user.id },
        }),
      });

      const { error: attachError } = await adminClient.rpc("attach_razorpay_order_secure", {
        p_order_id: order.id,
        p_customer_id: user.id,
        p_gateway_order_id: gatewayOrder.id,
        p_method: method,
      });
      if (attachError) {
        console.error("attach_razorpay_order_secure failed", { code: attachError.code, message: attachError.message });
        return json(req, { error: "Could not prepare payment. Please retry." }, 409);
      }

      return json(req, {
        key_id: razorpayKeyId,
        razorpay_order_id: gatewayOrder.id,
        amount: amountPaise,
        currency: "INR",
      });
    }

    if (body.action === "verify_payment") {
      const orderId = String(body.order_id ?? "");
      const gatewayOrderId = String(body.razorpay_order_id ?? "");
      const paymentId = String(body.razorpay_payment_id ?? "");
      const signature = String(body.razorpay_signature ?? "");
      if (!orderId || !gatewayOrderId || !paymentId || !signature) {
        return json(req, { error: "Missing payment verification fields" }, 400);
      }
      if (!razorpayKeySecret) return json(req, { error: "Payment service is temporarily unavailable" }, 503);

      const { data: order, error: orderError } = await userClient
        .from("Orders")
        .select("id,total_amount,customer_id,payment_status,order_status,payment_transaction_id,currency")
        .eq("id", orderId)
        .eq("customer_id", user.id)
        .maybeSingle();
      if (orderError || !order) return json(req, { error: "Order not found" }, 404);

      const { data: payment, error: paymentError } = await userClient
        .from("payments")
        .select("id,amount,currency,status,gateway_order_id,gateway_payment_id")
        .eq("order_id", orderId)
        .eq("customer_id", user.id)
        .maybeSingle();
      if (paymentError || !payment) return json(req, { error: "Payment record not found" }, 404);

      if (String(order.payment_status ?? "").toLowerCase() === "paid") {
        if (order.payment_transaction_id === paymentId && payment.gateway_payment_id === paymentId) {
          return json(req, { success: true, status: "Paid" });
        }
        return json(req, { error: "Order already paid with a different payment" }, 409);
      }
      if (String(payment.gateway_order_id ?? "") !== gatewayOrderId) {
        return json(req, { error: "Payment gateway order mismatch" }, 400);
      }
      if (String(payment.status ?? "").toLowerCase() !== "pending"
          || ["cancelled", "returned", "refunded"].includes(String(order.order_status ?? "").toLowerCase())) {
        return json(req, { error: "Order is not payable" }, 409);
      }
      if (String(order.currency ?? "INR").toUpperCase() !== "INR"
          || Math.round(Number(payment.amount) * 100) !== cents(order.total_amount)) {
        return json(req, { error: "Payment amount mismatch" }, 409);
      }

      const key = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(razorpayKeySecret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
      );
      const signed = await crypto.subtle.sign(
        "HMAC",
        key,
        new TextEncoder().encode(gatewayOrderId + "|" + paymentId),
      );
      const expected = Array.from(new Uint8Array(signed)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
      if (!constantTimeEqual(expected, signature.toLowerCase())) {
        return json(req, { error: "Invalid payment signature" }, 400);
      }

      let gatewayPayment = await razorpay("/payments/" + encodeURIComponent(paymentId));
      if (String(gatewayPayment.order_id ?? "") !== gatewayOrderId
          || Number(gatewayPayment.amount) !== cents(order.total_amount)
          || String(gatewayPayment.currency ?? "").toUpperCase() !== "INR") {
        return json(req, { error: "Gateway payment details do not match this order" }, 400);
      }

      if (String(gatewayPayment.status ?? "").toLowerCase() === "authorized") {
        gatewayPayment = await razorpay("/payments/" + encodeURIComponent(paymentId) + "/capture", {
          method: "POST",
          body: JSON.stringify({ amount: cents(order.total_amount), currency: "INR" }),
        });
      }
      if (String(gatewayPayment.status ?? "").toLowerCase() !== "captured" && gatewayPayment.captured !== true) {
        return json(req, { error: "Payment is not captured yet. Please contact support before retrying." }, 409);
      }

      const { error: markError } = await adminClient.rpc("mark_razorpay_paid_secure", {
        p_order_id: order.id,
        p_customer_id: user.id,
        p_razorpay_order_id: gatewayOrderId,
        p_payment_id: paymentId,
        p_signature: signature,
      });
      if (markError) {
        console.error("mark_razorpay_paid_secure failed", { code: markError.code, message: markError.message });
        return json(req, { error: "Payment was verified but order confirmation needs support review." }, 500);
      }
      return json(req, { success: true, status: "Paid" });
    }

    return json(req, { error: "Unknown action" }, 400);
  } catch (error) {
    console.error("razorpay-payment request failed", error instanceof Error ? error.message : "unknown error");
    return json(req, { error: "Payment could not be completed. Please retry or contact support." }, 500);
  }
});
