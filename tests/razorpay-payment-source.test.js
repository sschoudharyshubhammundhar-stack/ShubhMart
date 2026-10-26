import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const edge = readFileSync("supabase/functions/razorpay-payment/index.ts", "utf8");
const migration = readFileSync(
  "docs/drafts/20261012_secure_razorpay_payment_transition_candidate.sql",
  "utf8",
);

test("Razorpay function authenticates the caller and scopes order lookup to that customer", () => {
  assert.match(edge, /customer\.auth\.getUser\(\)/);
  assert.match(edge, /\.eq\("customer_id", user\.id\)/);
});

test("Razorpay payment verification checks HMAC and provider payment facts before marking paid", () => {
  assert.match(edge, /crypto\.subtle\.sign/);
  assert.match(edge, /\/payments\/\$\{encodeURIComponent\(String\(paymentId\)\)\}/);
  assert.match(edge, /payment\?\.order_id !== razorpayOrderId/);
  assert.match(edge, /Number\(payment\?\.amount\) !== expectedAmount/);
  assert.match(edge, /payment\?\.currency !== "INR"/);
  assert.match(edge, /payment\?\.status !== "captured" \|\| payment\?\.captured !== true/);
  assert.ok(edge.indexOf("const payment = await razorpay") < edge.indexOf('admin.rpc("mark_razorpay_paid_secure"'));
});

test("Razorpay attachment uses the customer-scoped RPC, with a narrow grant in the draft migration", () => {
  assert.match(edge, /customer\.rpc\("attach_razorpay_order"/);
  assert.match(migration, /auth\.uid\(\)/);
  assert.match(migration, /where order_id = p_order_id\s+and customer_id = auth\.uid\(\)/);
  assert.match(migration, /grant execute on function public\.attach_razorpay_order\(uuid, text, text\) to authenticated, service_role/i);
  assert.match(migration, /if not found then\s+raise exception 'Payment record not found or changed during verification'/);
});

test("paid transition draft is retry-safe for the same payment and rejects a different payment", () => {
  assert.match(migration, /if v_order_payment_status = 'Paid' then[\s\S]*?if v_order_payment_id = p_payment_id[\s\S]*?return;[\s\S]*?Order already paid with a different payment/);
  assert.match(migration, /Payment already linked to another order/);
  assert.match(migration, /grant execute on function public\.mark_razorpay_paid_secure\(uuid, uuid, text, text, text\) to service_role/i);
});


test("Razorpay order creation rejects invalid, zero-paise, and unsafe integer amounts", () => {
  assert.match(edge, /const orderAmountPaise = Math\.round\(storedAmount \* 100\)/);
  assert.match(edge, /const requestedAmountPaise = Math\.round\(amount \* 100\)/);
  assert.match(edge, /!Number\.isSafeInteger\(orderAmountPaise\) \|\| orderAmountPaise <= 0/);
  assert.match(edge, /!Number\.isSafeInteger\(requestedAmountPaise\) \|\| requestedAmountPaise <= 0/);
  assert.match(edge, /Math\.abs\(storedPaiseValue - orderAmountPaise\) > 1e-7/);
  assert.match(edge, /Math\.abs\(requestedPaiseValue - requestedAmountPaise\) > 1e-7/);
  assert.match(edge, /amount: orderAmountPaise/);
  assert.doesNotMatch(edge, /amount: Math\.round\(amount \* 100\)/);
});

test("candidate code and migration are not described as deployed", () => {
  assert.match(migration, /DRAFT MIGRATION CANDIDATE/);
  assert.match(edge, /authenticated EXECUTE grant must be installed through the reviewed/);
});

test("payment update trigger candidate permits only service-role server updates before customer checks", () => {
  assert.match(migration, /create or replace function public\.guard_customer_payment_update\(\)[\s\S]*?if auth\.role\(\) = 'service_role' then\s+return new;/);
  assert.match(migration, /if auth\.uid\(\) is null or old\.customer_id is distinct from auth\.uid\(\) then\s+raise exception 'Payment update denied'/);
});

test("paid transition resolves the exact Razorpay attempt, not the latest row", () => {
  assert.match(migration, /select id, gateway_order_id, gateway_payment_id[\s\S]*?where order_id = p_order_id[\s\S]*?and customer_id = p_customer_id[\s\S]*?and gateway_order_id = p_razorpay_order_id[\s\S]*?for update/);
  assert.doesNotMatch(migration, /where order_id = p_order_id\s+and customer_id = p_customer_id\s+order by updated_at desc nulls last, id desc\s+limit 1\s+for update/);
  assert.match(migration, /update public\.payments[\s\S]*?where id = v_payment_row_id[\s\S]*?and gateway_order_id = p_razorpay_order_id/);
  assert.match(migration, /v_payment_row_id uuid/);
});
