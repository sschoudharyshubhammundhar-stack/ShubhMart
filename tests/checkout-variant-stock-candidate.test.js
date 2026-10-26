const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const candidatePath = path.join(__dirname, "../docs/drafts/CHECKOUT_VARIANT_STOCK_RESERVATION_CANDIDATE.sql");
const runbookPath = path.join(__dirname, "../docs/drafts/CHECKOUT_ISOLATED_TEST_RUNBOOK.md");
const auditPath = path.join(__dirname, "../docs/drafts/CHECKOUT_INVENTORY_MUTATION_AUDIT_2026-10-25.md");
const sql = fs.readFileSync(candidatePath, "utf8");
const runbook = fs.readFileSync(runbookPath, "utf8");
const audit = fs.readFileSync(auditPath, "utf8");

test("variant stock candidate remains explicitly non-production and not idempotency-complete", () => {
  assert.match(sql, /DRAFT ONLY/i);
  assert.match(sql, /No live SQL has been executed/i);
  assert.match(sql, /DOES NOT implement database-backed idempotency/i);
  assert.match(sql, /Do not apply until separately reviewed/i);
});

test("locked runbook requires parent and selected variant stock to be reserved atomically", () => {
  assert.match(runbook, /variant line reserves quantity Q from both `products\.stock` and the selected `product_variants\.stock`, atomically/i);
  assert.match(runbook, /Both guarded decrements must succeed or the entire transaction rolls back/i);
  assert.match(runbook, /Persist the exact product, variant, quantity and counters reserved in durable reservation evidence/i);
});

test("candidate is explicitly detected as incompatible with locked parent-plus-variant inventory contract", () => {
  assert.match(sql, /UPDATE public\.product_variants[\s\S]*?stock = stock - v_item\.quantity[\s\S]*?stock >= v_item\.quantity/);
  assert.match(sql, /Variant owns its inventory: do not also decrement parent product stock/i);
  assert.match(audit, /Candidate SQL must not be applied as-is/i);
  assert.match(audit, /BLOCKED — do not apply the stock candidate/i);
});

test("candidate retains a guarded parent-only decrement for non-variant items", () => {
  assert.match(sql, /UPDATE public\.products[\s\S]*?stock = stock - v_item\.quantity[\s\S]*?stock >= v_item\.quantity/);
  assert.match(sql, /CREATE OR REPLACE FUNCTION public\.create_order_from_cart_with_coins/);
});

test("candidate is blocked pending end-to-end cancellation/restoration and idempotency proof", () => {
  assert.match(audit, /Every cancellation, failed\/unpaid cleanup, and other restoration path must restore each recorded counter exactly once/i);
  assert.match(audit, /do not apply/i);
  assert.match(runbook, /Idempotency is not yet implemented in the live RPC/i);
});
