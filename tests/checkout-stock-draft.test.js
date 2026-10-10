const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const draftPath = path.join(__dirname, "../docs/drafts/CHECKOUT_STOCK_RESERVATION_PATCH_DRAFT.sql");
const draft = fs.readFileSync(draftPath, "utf8");

test("stock reservation SQL remains explicitly a draft, not production migration", () => {
  assert.match(draft, /DRAFT ONLY/i);
  assert.match(draft, /No live SQL has been executed/i);
  assert.match(draft, /not a complete CREATE OR REPLACE FUNCTION/i);
});

test("draft describes a guarded decrement and positive quantity validation", () => {
  assert.match(draft, /stock\s*>=\s*v_item\.quantity/);
  assert.match(draft, /v_item\.quantity\s*<=\s*0/);
  assert.match(draft, /IF NOT FOUND THEN\s+RAISE EXCEPTION 'Insufficient stock'/);
});

test("draft ties stock_reserved to an atomic stock decrement", () => {
  assert.match(draft, /stock_reserved/i);
  assert.match(draft, /same transaction/i);
  assert.match(draft, /Do not set stock_reserved TRUE without the matching decrement/i);
});
