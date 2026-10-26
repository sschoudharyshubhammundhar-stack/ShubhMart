const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const draftPath = path.join(__dirname, "../docs/drafts/CHECKOUT_IDEMPOTENCY_IMPLEMENTATION_DRAFT.md");
const draft = fs.readFileSync(draftPath, "utf8");

test("idempotency remains explicitly a draft, not active protection", () => {
  assert.match(draft, /Status: design artifact only/i);
  assert.match(draft, /not a migration/i);
  assert.match(draft, /has not been run against PostgreSQL/i);
});

test("idempotency contract requires same-key replay and changed-request conflict", () => {
  assert.match(draft, /Same customer \+ same key \+ same fingerprint: return the original order/i);
  assert.match(draft, /Same customer \+ same key \+ different fingerprint: reject/i);
  assert.match(draft, /Unique constraint on \(customer_id, idempotency_key\)/i);
});

test("idempotency record and checkout side effects must share one transaction", () => {
  assert.match(draft, /same database transaction/i);
  assert.match(draft, /An Edge Function that calls an order-creation RPC and then writes an idempotency row in a separate request is not atomic/i);
  assert.match(draft, /Concurrent calls using the same key must serialize via a unique constraint and row lock/i);
});

test("request fingerprint is server-calculated and customer identity is authenticated", () => {
  assert.match(draft, /Edge Function derives the customer ID from the verified access token/i);
  assert.match(draft, /It calculates a request fingerprint from server-validated values/i);
  assert.match(draft, /Never trust a client-supplied fingerprint/i);
});

test("test matrix covers concurrency, coins, changed carts and rollback", () => {
  assert.match(draft, /concurrent retry/i);
  assert.match(draft, /one coin redemption/i);
  assert.match(draft, /Transaction failure after stock decrement/i);
  assert.match(draft, /cart changed by another tab/i);
});
