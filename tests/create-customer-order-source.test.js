const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const sourcePath = path.join(__dirname, "../supabase/functions/create-customer-order/index.ts");
const source = fs.readFileSync(sourcePath, "utf8");
const sqlCandidatePath = path.join(__dirname, "../docs/drafts/CHECKOUT_VARIANT_STOCK_RESERVATION_CANDIDATE.sql");
const sqlCandidate = fs.readFileSync(sqlCandidatePath, "utf8");


test("checkout verifies the bearer token before using its user id", () => {
  assert.match(source, /admin\.auth\.getUser\(authorization\.slice\(7\)\)/);
  assert.match(source, /if\s*\(userError\s*\|\|\s*!user\)/);
  assert.match(source, /p_customer_id:\s*user\.id/);
});

test("order RPC uses the server-only client only after verifying the bearer token", () => {
  assert.match(source, /admin\.auth\.getUser\(authorization\.slice\(7\)\)/);
  assert.match(source, /const \{ data, error \} = await admin\.rpc\(["']create_order_from_cart_with_coins["']/);
  assert.match(source, /server-side after verifying the caller's bearer token above/);
  assert.doesNotMatch(source, /customer\.rpc\(["']create_order_from_cart_with_coins["']/);
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

test("checkout rejects unsafe, fractional, negative, and non-finite ShubhCoins input", () => {
  assert.match(source, /const rawCoins = body\?\.shubhcoins \?\? 0/);
  assert.match(source, /Number\.isSafeInteger\(requestedCoins\) \|\| requestedCoins < 0/);
  assert.match(source, /Invalid ShubhCoins amount/);
  assert.match(source, /const coins = requestedCoins/);
  assert.doesNotMatch(source, /Math\.floor\(requestedCoins\)/);
});

test("ShubhCoins accepts only JSON integers or canonical digit strings; rejects coercible types", () => {
  assert.match(source, /typeof rawCoins === "number"/);
  assert.match(source, /typeof rawCoins === "string" && \/\^\(0\|\[1-9\]\\d\*\)\$\//);
  assert.match(source, /Do not coerce booleans, arrays, objects, empty strings, whitespace/);
  assert.match(source, /else\s*\{\s*return json\(\{ error: "Invalid ShubhCoins amount" \}, 400\);\s*\}/);
  assert.doesNotMatch(source, /typeof rawCoins === "number" \? rawCoins : Number\(rawCoins\)/);
});

test("draft SQL candidate supports the trusted server role without weakening customer ownership", () => {
  assert.match(sqlCandidate, /coalesce\(auth\.role\(\), ''\) <> 'service_role'/);
  assert.match(sqlCandidate, /auth\.uid\(\) <> p_customer_id/);
  assert.match(sqlCandidate, /Do not grant this RPC directly to anon\/public/);
  assert.match(sqlCandidate, /stock_reserved/);
});


test("variant stock candidate rejects hidden products and pins an empty search path", () => {
  assert.match(sqlCandidate, /v_product\.is_live IS NOT TRUE/);
  assert.match(sqlCandidate, /SET search_path = ''/);
});

test("variant stock candidate decrements only the selected inventory with a stock guard", () => {
  assert.match(sqlCandidate, /UPDATE public\.product_variants[\s\S]*?stock = stock - v_item\.quantity[\s\S]*?stock >= v_item\.quantity/);
  assert.match(sqlCandidate, /UPDATE public\.products[\s\S]*?stock = stock - v_item\.quantity[\s\S]*?stock >= v_item\.quantity/);
  assert.match(sqlCandidate, /variant_id/);
});

test("checkout candidate rejects nullable product status and invalid database inputs", () => {
  assert.match(sqlCandidate, /status IS DISTINCT FROM 'Active'/);
  assert.match(sqlCandidate, /lower\(coalesce\(p_payment_method, ''\)\) NOT IN/);
  assert.match(sqlCandidate, /IF p_shubhcoins < 0 THEN/);
});
