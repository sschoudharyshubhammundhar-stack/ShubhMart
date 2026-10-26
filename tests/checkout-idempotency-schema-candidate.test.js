const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const sqlPath = path.join(__dirname, "../docs/drafts/CHECKOUT_IDEMPOTENCY_SCHEMA_CANDIDATE.sql");
const sql = fs.readFileSync(sqlPath, "utf8");

test("idempotency schema candidate is explicitly draft-only and not executable by itself", () => {
  assert.match(sql, /DRAFT ONLY/i);
  assert.match(sql, /DO NOT RUN AGAINST PRODUCTION/i);
  assert.match(sql, /does NOT prevent duplicate orders until the checkout RPC is changed/i);
  assert.match(sql, /No SQL in this file has been executed/i);
});

test("idempotency key is unique per authenticated customer", () => {
  assert.match(sql, /customer_id uuid NOT NULL REFERENCES auth\.users\(id\)/);
  assert.match(sql, /idempotency_key uuid NOT NULL/);
  assert.match(sql, /UNIQUE \(customer_id, idempotency_key\)/);
});

test("candidate captures fingerprint and constrained lifecycle", () => {
  assert.match(sql, /request_fingerprint text NOT NULL/);
  assert.match(sql, /CHECK \(state IN \('processing', 'completed'\)\)/);
  assert.match(sql, /checkout_idempotency_completion_consistent/);
});

test("candidate denies browser roles access to private records", () => {
  assert.match(sql, /REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated/);
  assert.match(sql, /REVOKE ALL ON TABLE private\.checkout_idempotency FROM PUBLIC, anon, authenticated/);
});

test("draft calls out atomic RPC integration and remaining delete semantics review", () => {
  assert.match(sql, /atomically with order, inventory, payment and coin effects/i);
  assert.match(sql, /Update the single order-creation RPC/i);
  assert.match(sql, /Review order deletion semantics/i);
  assert.match(sql, /cancellation, unpaid cleanup, duplicate gateway callbacks/i);
});
