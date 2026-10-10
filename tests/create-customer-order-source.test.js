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

test("checkout exposes only allowlisted business errors from the database", () => {
  assert.match(source, /const safeCheckoutError = \(message: string\)/);
  assert.match(source, /safeCheckoutError\(error\.message\)/);
  assert.match(source, /Unable to create order\. Please review your cart and try again\./);
  assert.doesNotMatch(source, /json\(\{\s*error:\s*error\.message\s*\},\s*400\)/);
  assert.doesNotMatch(source, /error instanceof Error \? error\.message/);
});

test("checkout rejects unsupported methods and unauthenticated requests", () => {
  assert.match(source, /req\.method !== "POST"[^\n]*405/);
  assert.match(source, /!authorization\?\.startsWith\("Bearer "\) \|\| !apiKey/);
  assert.match(source, /if\s*\(userError\s*\|\|\s*!user\) return json\(\{ error: "Unauthorized" \}, 401\)/);
});

test("checkout preserves the safe address-required validation message", () => {
  assert.match(source, /"Address is required"/);
  assert.match(source, /safeCheckoutError\(error\.message\)/);
});

test("checkout rejects invalid ShubhCoins input instead of forwarding NaN", () => {
  assert.match(source, /const rawCoins = body\?\.shubhcoins \?\? 0/);
  assert.match(source, /Number\.isFinite\(requestedCoins\) \|\| requestedCoins < 0/);
  assert.match(source, /Invalid ShubhCoins amount/);
  assert.match(source, /const coins = Math\.floor\(requestedCoins\)/);
});
