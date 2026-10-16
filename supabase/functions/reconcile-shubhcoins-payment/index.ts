import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")!);
const serviceKey = secretKeys["default"];
const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

type ProviderPayment = {
  id?: string;
  order_id?: string;
  amount?: number;
  currency?: string;
  status?: string;
  captured?: boolean;
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

async function providerGet(path: string) {
  if (!razorpayKeyId || !razorpayKeySecret) throw new Error("PROVIDER_NOT_CONFIGURED");
  const response = await fetch(`https://api.razorpay.com/v1${path}`, {
    method: "GET",
    headers: {
      Authorization: `Basic ${btoa(`${razorpayKeyId}:${razorpayKeySecret}`)}`,
      Accept: "application/json",
    },
  });
  if (!response.ok) throw new Error("PROVIDER_LOOKUP_FAILED");
  return await response.json();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: authError } = await caller.auth.getUser();
    if (authError || !user) return json({ error: "Unauthorized" }, 401);

    const body = await req.json().catch(() => null);
    const orderId = body?.order_id;
    if (typeof orderId !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(orderId)) {
      return json({ error: "Invalid order" }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: order, error: orderError } = await admin
      .from("Orders")
      .select("id,customer_id,total_amount,payment_status,currency")
      .eq("id", orderId)
      .eq("customer_id", user.id)
      .maybeSingle();

    // Same response for missing and non-owned order avoids an order-ID oracle.
    if (orderError || !order) return json({ error: "Order not found" }, 404);
    if (String(order.payment_status).toLowerCase() === "paid") {
      return json({ status: "paid", coins: "unchanged", message: "Payment is recorded. Wallet state was not changed." });
    }

    const { data: attempts, error: attemptsError } = await admin
      .from("payments")
      .select("id,gateway,gateway_order_id,gateway_payment_id,amount,currency,status")
      .eq("order_id", order.id)
      .eq("customer_id", user.id);

    if (attemptsError || !attempts?.length) {
      return json({ status: "indeterminate", coins: "unchanged", message: "Payment needs secure reconciliation." }, 202);
    }

    const expectedPaise = Math.round(Number(order.total_amount) * 100);
    if (!Number.isSafeInteger(expectedPaise) || expectedPaise <= 0) {
      return json({ status: "indeterminate", coins: "unchanged", message: "Payment needs secure reconciliation." }, 202);
    }

    const gatewayOrderIds = [...new Set(
      attempts
        .filter((attempt) => String(attempt.gateway || "").toLowerCase() === "razorpay")
        .map((attempt) => attempt.gateway_order_id)
        .filter((id): id is string => typeof id === "string" && id.length > 0),
    )];

    if (!gatewayOrderIds.length) {
      return json({ status: "indeterminate", coins: "unchanged", message: "Payment needs secure reconciliation." }, 202);
    }

    let sawCaptured = false;
    let sawUncertain = false;
    let inspected = 0;

    // Fail closed: inspect every known Razorpay order and exhaust provider pagination.
    // The bounded page count prevents unbounded provider/API work; exceeding it is indeterminate.
    for (const gatewayOrderId of gatewayOrderIds) {
      let skip = 0;
      let pageCount = 0;
      let reportedCount: number | null = null;
      do {
        const page = await providerGet(
          `/orders/${encodeURIComponent(gatewayOrderId)}/payments?count=100&skip=${skip}`,
        );
        if (!Array.isArray(page?.items) || !Number.isFinite(Number(page?.count))) {
          return json({ status: "indeterminate", coins: "unchanged", message: "Payment needs secure reconciliation." }, 202);
        }
        reportedCount = Number(page.count);
        const items = page.items as ProviderPayment[];
        if (items.length > 100 || (items.length === 0 && skip < reportedCount)) {
          return json({ status: "indeterminate", coins: "unchanged", message: "Payment needs secure reconciliation." }, 202);
        }

        for (const payment of items) {
          inspected++;
          if (payment.order_id !== gatewayOrderId ||
              !payment.id ||
              Number(payment.amount) !== expectedPaise ||
              payment.currency !== "INR") {
            return json({ status: "indeterminate", coins: "unchanged", message: "Payment needs secure reconciliation." }, 202);
          }
          if (payment.status === "captured" && payment.captured === true) sawCaptured = true;
          else if (payment.status !== "failed" && payment.status !== "refunded") sawUncertain = true;
        }

        skip += items.length;
        pageCount++;
        if (pageCount > 10 && skip < reportedCount) {
          return json({ status: "indeterminate", coins: "unchanged", message: "Payment needs secure reconciliation." }, 202);
        }
        if (items.length === 0) break;
      } while (skip < (reportedCount ?? 0));
    }

    if (sawCaptured) {
      return json({ status: "captured_needs_confirmation", coins: "unchanged", inspected, message: "A captured payment was found. Order confirmation is being checked; do not pay again yet." }, 202);
    }
    if (sawUncertain || inspected === 0) {
      return json({ status: "indeterminate", coins: "unchanged", inspected, message: "Payment status is not final. Coins remain reserved while the payment is checked." }, 202);
    }

    // Deliberately do not release coins just because listed attempts failed.
    // Razorpay can still have a payable order or a later attempt not yet represented
    // in local DB. A verified terminal-close protocol is required before release.
    return json({ status: "terminal_attempts_seen_but_release_blocked", coins: "unchanged", inspected, message: "Payment attempts were checked, but coins were not released because terminal closure is not proven." }, 202);
  } catch {
    // Provider timeouts, malformed responses, and unexpected exceptions never release coins.
    return json({ status: "indeterminate", coins: "unchanged", message: "Payment status could not be confirmed. Please do not retry payment until it is checked." }, 202);
  }
});
