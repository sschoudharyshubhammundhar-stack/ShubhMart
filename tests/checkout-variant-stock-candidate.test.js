const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const candidatePath = path.join(__dirname, "../docs/drafts/CHECKOUT_VARIANT_STOCK_RESERVATION_CANDIDATE.sql");
const sql = fs.readFileSync(candidatePath, "utf8");

test("variant stock candidate is explicitly non-production and not idempotency-complete", () => {
  assert.match(sql, /DRAFT ONLY/i);
  assert.match(sql, /No live SQL has been executed/i);
  assert.match(sql, /DOES NOT implement database-backed idempotency/i);
  assert.match(sql, /Do not apply until separately reviewed/i);
});

test("variant carts validate ownership/status and reserve variant inventory only", () => {
  assert.match(sql, /WHERE id = v_item\.variant_id[\s\S]*?AND product_id = v_item\.product_id[\s\S]*?AND status = 'Active'/);
  assert.match(sql, /UPDATE public\.product_variants[\s\S]*?stock = stock - v_item\.quantity[\s\S]*?stock >= v_item\.quantity/);
  assert.match(sql, /Variant owns its inventory: do not also decrement parent product stock/i);
  assert.match(sql, /variant_id, quantity, unit_price, total_price/);
});

test("non-variant stock decrement is guarded and order reservation flag is atomic", () => {
  assert.match(sql, /UPDATE public\.products[\s\S]*?stock = stock - v_item\.quantity[\s\S]*?stock >= v_item\.quantity/);
  assert.match(sql, /stock_reserved[\s\S]*?true/i);
  assert.match(sql, /CREATE OR REPLACE FUNCTION public\.create_order_from_cart_with_coins/);
});

test("candidate keeps stock/order/payment/coin work in one function transaction", () => {
  assert.match(sql, /INSERT INTO public\."Orders"/);
  assert.match(sql, /INSERT INTO public\.payments/);
  assert.match(sql, /INSERT INTO public\.shubhcoins_ledger/);
});
