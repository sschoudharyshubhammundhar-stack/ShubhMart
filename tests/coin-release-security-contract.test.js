const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const customerSource = fs.readFileSync('customer/customer-app.js', 'utf8');

/*
 * SECURITY RELEASE GATE — intentionally expected to fail on the current branch.
 * The live DB release_shubhcoins_for_order routine is a SECURITY DEFINER RPC
 * callable by authenticated users and does not reconcile authoritative gateway
 * state. Do not weaken these assertions to make CI green; implement the
 * server-side reconciliation flow and update these tests only with equivalent
 * stronger invariants.
 */

test('customer browser must never invoke the privileged coin-release RPC directly', () => {
  assert.doesNotMatch(
    customerSource,
    /\.rpc\(\s*["']release_shubhcoins_for_order["']/,
    'browser must not call release_shubhcoins_for_order directly',
  );
});

test('Razorpay dismissal/failure callbacks must not themselves release ShubhCoins', () => {
  const paymentFlow = customerSource.match(/const options\s*=\s*\{[\s\S]*?rzp\.open\(\);/);
  assert.ok(paymentFlow, 'Razorpay checkout flow should be identifiable for review');
  assert.doesNotMatch(
    paymentFlow[0],
    /releaseShubhCoinsForOrder\s*\(/,
    'payment modal dismissal, failure, and verification error must request reconciliation, not credit coins',
  );
});

test('coin recovery helper must not convert a browser-observed error into a financial decision', () => {
  const helper = customerSource.match(/async function releaseShubhCoinsForOrder\([\s\S]*?\n/);
  assert.ok(helper, 'legacy coin recovery helper should be identified before removal/replacement');
  assert.doesNotMatch(
    helper[0],
    /sb\.rpc\(/,
    'the browser may request trusted reconciliation, but cannot execute the release RPC',
  );
});
