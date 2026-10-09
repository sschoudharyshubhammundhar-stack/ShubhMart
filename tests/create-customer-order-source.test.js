const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const sourcePath = path.join(__dirname, "../supabase/functions/create-customer-order/index.ts");
const source = fs.readFileSync(sourcePath, "utf8");

test("checkout verifies the bearer token before using its user id", () => {
  assert.match(source, /admin\.auth\.getUser\(authorization\.slice\(7\)\)/);
  assert.match(source, /if\s*\(userError\s*\|\|\s*!user\)/);
  assert.match(source, /p_customer_id:\s*user\.id/);
});

test("order RPC preserves the verified customer's JWT context", () => {
  assert.match(source, /global:\s*\{\s*headers:\s*\{\s*Authorization:\s*authorization\s*\}\s*\}/);
  assert.match(source, /customer\.rpc\(["']create_order_from_cart_with_coins["']/);
  assert.doesNotMatch(source, /admin\.rpc\(["']create_order_from_cart_with_coins["']/);
});
