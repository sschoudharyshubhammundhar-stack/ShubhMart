const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const customerSource = fs.readFileSync('customer/customer-app.js', 'utf8');
const reconciliationSource = fs.readFileSync(
  'supabase/functions/reconcile-shubhcoins-payment/index.ts',
  'utf8',
);

/*
 * Release-blocking source-level guard. These checks are not a substitute for
 * isolated DB concurrency tests or a verified provider terminal-close protocol.
 */

test('customer browser never invokes the privileged coin-release RPC directly', () => {
  assert.doesNotMatch(
    customerSource,
    /\.rpc\(\s*["']release_shubhcoins_for_order["']/,
  );
});

test('payment callbacks request server reconciliation and never claim coins were released', () => {
  assert.match(customerSource, /requestPaymentReconciliation\(orderId\)/);
  assert.match(customerSource, /sb\.functions\.invoke\(["']reconcile-shubhcoins-payment["']/);
  assert.doesNotMatch(customerSource, /Coins release kar diye gaye/);
  assert.doesNotMatch(customerSource, /releaseShubhCoinsForOrder\s*\(/);
});

test('reconciliation endpoint authenticates caller and checks order ownership', () => {
  assert.match(reconciliationSource, /caller\.auth\.getUser\(\)/);
  assert.match(reconciliationSource, /\.eq\("customer_id", user\.id\)/);
  assert.match(reconciliationSource, /Same response for missing and non-owned order/);
});

test('provider errors, malformed results and indeterminate states fail closed', () => {
  assert.match(reconciliationSource, /PROVIDER_LOOKUP_FAILED/);
  assert.match(reconciliationSource, /status: "indeterminate", coins: "unchanged"/);
  assert.match(reconciliationSource, /Provider timeouts, malformed responses, and unexpected exceptions never release coins/);
});

test('reconciliation inspects provider payment pages and validates order, amount and currency', () => {
  assert.match(reconciliationSource, /\/orders\/\$\{encodeURIComponent\(gatewayOrderId\)\}\/payments\?count=100&skip=\$\{skip\}/);
  assert.match(reconciliationSource, /payment\.order_id !== gatewayOrderId/);
  assert.match(reconciliationSource, /Number\(payment\.amount\) !== expectedPaise/);
  assert.match(reconciliationSource, /payment\.currency !== "INR"/);
  assert.match(reconciliationSource, /skip < \(reportedCount \?\? 0\)/);
});

test('even failed listed attempts do not trigger coin release without terminal closure proof', () => {
  assert.match(reconciliationSource, /Deliberately do not release coins just because listed attempts failed/);
  assert.match(reconciliationSource, /terminal_attempts_seen_but_release_blocked/);
  assert.match(reconciliationSource, /coins: "unchanged"/);
});

test('reconciliation never calls a wallet-credit or release RPC', () => {
  assert.doesNotMatch(reconciliationSource, /\.rpc\(\s*["'][^"']*(release|credit)[^"']*["']/i);
});
