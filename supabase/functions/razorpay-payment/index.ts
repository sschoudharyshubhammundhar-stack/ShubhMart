import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")!);
const supabaseSecretKey = secretKeys["default"];
const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

async function razorpay(path: string, init: RequestInit = {}) {
  if (!razorpayKeyId || !razorpayKeySecret) {
    throw new Error("Razorpay keys are not configured");
  }
  const auth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
  const response = await fetch(`https://api.razorpay.com/v1${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Basic ${auth}`,
      ...(init.headers || {}),
    },
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    // Do not return provider error payloads or credentials to the browser.
    throw new Error("Razorpay request failed");
  }
  return data;
}

function secureHexEqual(actual: string, expected: string): boolean {
  if (!/^[0-9a-f]{64}$/i.test(actual) || !/^[0-9a-f]{64}$/i.test(expected)) return false;
  const a = new TextEncoder().encode(actual.toLowerCase());
  const b = new TextEncoder().encode(expected.toLowerCase());
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

    const customer = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: userError } = await customer.auth.getUser();
    if (userError || !user) return json({ error: "Unauthorized" }, 401);

    const body = await req.json();

    if (body?.action === "create_order") {
      const orderId = body.order_id;
      const amount = Number(body.amount);
      if (!orderId || !Number.isFinite(amount) || amount <= 0) {
        return json({ error: "Invalid order" }, 400);
      }

      const { data: order, error: orderError } = await customer
        .from("Orders")
        .select("id,total_amount,customer_id,payment_method,payment_status")
        .eq("id", orderId)
        .eq("customer_id", user.id)
        .single();
      if (orderError || !order) return json({ error: "Order not found" }, 404);
      if (order.payment_status === "Paid") return json({ error: "Order is already paid" }, 409);
      if (Math.round(Number(order.total_amount) * 100) !== Math.round(amount * 100)) {
        return json({ error: "Amount mismatch" }, 400);
      }

      const created = await razorpay("/orders", {
        method: "POST",
        body: JSON.stringify({
          amount: Math.round(amount * 100),
          currency: "INR",
          receipt: `shubhmart_${String(order.id).slice(0, 20)}`,
          notes: { shubhmart_order_id: String(order.id), customer_id: user.id },
        }),
      });

      // The database RPC validates auth.uid() and customer ownership.
      // Its authenticated EXECUTE grant must be installed through the reviewed
      // migration candidate before this customer-scoped call can succeed.
      const { error: attachError } = await customer.rpc("attach_razorpay_order", {
        p_order_id: order.id,
        p_gateway_order_id: created.id,
        p_method: order.payment_method || "razorpay",
      });
      if (attachError) {
        // A provider order may already exist. Log only identifiers, never secrets.
        console.error("Razorpay order attachment failed", {
          orderId: order.id,
          gatewayOrderId: created.id,
          code: attachError.code,
        });
        return json({ error: "Payment setup could not be completed. Please retry or contact support." }, 502);
      }
      return json({
        key_id: razorpayKeyId,
        razorpay_order_id: created.id,
        amount: created.amount,
        currency: created.currency,
      });
    }

    if (body?.action === "verify_payment") {
      const orderId = body.order_id;
      const razorpayOrderId = body.razorpay_order_id;
      const paymentId = body.razorpay_payment_id;
      const signature = body.razorpay_signature;
      if (!orderId || !razorpayOrderId || !paymentId || !signature) {
        return json({ error: "Missing payment fields" }, 400);
      }

      const { data: order, error: orderError } = await customer
        .from("Orders")
        .select("id,customer_id,total_amount,payment_status")
        .eq("id", orderId)
        .eq("customer_id", user.id)
        .single();
      if (orderError || !order) return json({ error: "Order not found" }, 404);

      const expectedKey = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(razorpayKeySecret || ""),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
      );
      const signatureBytes = await crypto.subtle.sign(
        "HMAC",
        expectedKey,
        new TextEncoder().encode(`${razorpayOrderId}|${paymentId}`),
      );
      const expectedSignature = Array.from(new Uint8Array(signatureBytes))
        .map((value) => value.toString(16).padStart(2, "0"))
        .join("");
      if (!secureHexEqual(String(signature), expectedSignature)) {
        return json({ error: "Invalid payment signature" }, 400);
      }

      // Signature alone proves the signed pair, not that the provider payment
      // is captured for the expected amount/currency. Confirm the provider record.
      const payment = await razorpay(`/payments/${encodeURIComponent(String(paymentId))}`);
      const expectedAmount = Math.round(Number(order.total_amount) * 100);
      if (
        payment?.id !== paymentId ||
        payment?.order_id !== razorpayOrderId ||
        Number(payment?.amount) !== expectedAmount ||
        payment?.currency !== "INR"
      ) {
        return json({ error: "Payment details do not match this order" }, 400);
      }
      if (payment?.status !== "captured" || payment?.captured !== true) {
        return json({ error: "Payment is not captured yet. Please retry shortly." }, 409);
      }

      const admin = createClient(supabaseUrl, supabaseSecretKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { error: markError } = await admin.rpc("mark_razorpay_paid_secure", {
        p_order_id: order.id,
        p_customer_id: user.id,
        p_razorpay_order_id: razorpayOrderId,
        p_payment_id: paymentId,
        p_signature: signature,
      });
      if (markError) {
        console.error("Razorpay paid-state update failed", {
          orderId: order.id,
          paymentId,
          code: markError.code,
        });
        return json({ error: "Payment was verified but order confirmation needs reconciliation." }, 502);
      }
      return json({ success: true, status: "Paid" });
    }

    return json({ error: "Unknown action" }, 400);
  } catch {
    return json({ error: "Payment request could not be completed. Please retry or contact support." }, 500);
  }
});
