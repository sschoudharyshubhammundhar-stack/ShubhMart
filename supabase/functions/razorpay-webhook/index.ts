import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
const serviceRoleKey = secretKeys["default"] as string | undefined;
const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function constantTimeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}

async function hmacHex(secret: string, message: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(signed)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!serviceRoleKey || !webhookSecret) {
    console.error("Razorpay webhook is not configured");
    return json({ error: "Webhook is not configured" }, 503);
  }

  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (contentLength > 1_000_000) return json({ error: "Payload too large" }, 413);

  try {
    const rawBody = await req.text();
    if (rawBody.length > 1_000_000) return json({ error: "Payload too large" }, 413);
    const receivedSignature = req.headers.get("x-razorpay-signature") ?? "";
    if (!receivedSignature) return json({ error: "Missing webhook signature" }, 401);

    const expectedSignature = await hmacHex(webhookSecret, rawBody);
    if (!constantTimeEqual(expectedSignature, receivedSignature.toLowerCase())) {
      return json({ error: "Invalid webhook signature" }, 401);
    }

    let event: any;
    try {
      event = JSON.parse(rawBody);
    } catch {
      return json({ error: "Invalid JSON payload" }, 400);
    }

    // Acknowledge unrelated events; this endpoint only reconciles captured payments.
    if (event?.event !== "payment.captured") return json({ received: true, ignored: true });

    const gatewayPayment = event?.payload?.payment?.entity;
    const paymentId = String(gatewayPayment?.id ?? "");
    const gatewayOrderId = String(gatewayPayment?.order_id ?? "");
    const amountPaise = Number(gatewayPayment?.amount);
    const currency = String(gatewayPayment?.currency ?? "").toUpperCase();
    const status = String(gatewayPayment?.status ?? "").toLowerCase();

    if (!paymentId || !gatewayOrderId || !Number.isSafeInteger(amountPaise) || amountPaise <= 0
        || currency !== "INR" || status !== "captured" || gatewayPayment?.captured !== true) {
      console.error("Captured-payment webhook payload failed validation");
      return json({ received: true, ignored: true, needs_review: true });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: payment, error: paymentError } = await admin
      .from("payments")
      .select("order_id,customer_id,amount,currency,status,gateway_order_id,gateway_payment_id")
      .eq("gateway_order_id", gatewayOrderId)
      .maybeSingle();
    if (paymentError) {
      console.error("Webhook payment lookup failed", { code: paymentError.code, message: paymentError.message });
      return json({ error: "Temporary payment lookup failure" }, 500);
    }
    if (!payment) {
      // No ShubhMart payment row is associated with this gateway order; do not mutate unrelated orders.
      return json({ received: true, ignored: true });
    }

    const { data: order, error: orderError } = await admin
      .from("Orders")
      .select("id,customer_id,total_amount,currency,payment_status,payment_transaction_id,order_status")
      .eq("id", payment.order_id)
      .eq("customer_id", payment.customer_id)
      .maybeSingle();
    if (orderError) {
      console.error("Webhook order lookup failed", { code: orderError.code, message: orderError.message });
      return json({ error: "Temporary order lookup failure" }, 500);
    }
    if (!order) return json({ received: true, ignored: true, needs_review: true });

    const expectedPaise = Math.round(Number(order.total_amount) * 100);
    if (!Number.isSafeInteger(expectedPaise) || expectedPaise <= 0
        || expectedPaise !== amountPaise
        || Math.round(Number(payment.amount) * 100) !== amountPaise
        || String(order.currency ?? "INR").toUpperCase() !== "INR"
        || String(payment.currency ?? "INR").toUpperCase() !== "INR") {
      console.error("Captured-payment webhook amount/currency mismatch", { orderId: order.id, paymentId });
      return json({ received: true, ignored: true, needs_review: true });
    }

    if (String(order.payment_status ?? "").toLowerCase() === "paid") {
      if (order.payment_transaction_id === paymentId && payment.gateway_payment_id === paymentId) {
        return json({ received: true, already_processed: true });
      }
      console.error("Webhook received a different captured payment for an already-paid order", { orderId: order.id, paymentId });
      return json({ received: true, needs_review: true });
    }

    const { error: markError } = await admin.rpc("mark_razorpay_paid_secure", {
      p_order_id: order.id,
      p_customer_id: payment.customer_id,
      p_razorpay_order_id: gatewayOrderId,
      p_payment_id: paymentId,
      p_signature: receivedSignature,
    });
    if (markError) {
      console.error("Webhook could not finalize captured payment", { code: markError.code, message: markError.message, orderId: order.id });
      return json({ error: "Payment captured; order reconciliation will retry" }, 500);
    }

    return json({ received: true, processed: true });
  } catch (error) {
    console.error("Razorpay webhook handler failed", error instanceof Error ? error.message : "unknown error");
    return json({ error: "Webhook processing failed" }, 500);
  }
});
