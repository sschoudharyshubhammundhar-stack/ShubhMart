const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");

const html = readFileSync("index.html", "utf8");

test("safeImageUrl rejects non-HTTPS URLs and URLs with embedded credentials", () => {
  assert.ok(html.includes("function safeImageUrl(value,fallback="));
  assert.ok(html.includes("url.protocol!=='https:'"));
  assert.ok(html.includes("url.username||url.password"));
});

test("all known customer product image locations use safeImageUrl", () => {
  const required = [
    "safeImageUrl(p.image_url,'https://placehold.co/40')",
    "safeImageUrl(p.image_url,'https://placehold.co/500x400?text=Wholesale')",
    "safeImageUrl(p.image_url,'https://placehold.co/600x500?text=ShubhMart')",
    "safeImageUrl(p.image_url,'https://placehold.co/500x400?text=ShubhMart')",
    "safeImageUrl(variant?.image_url||x.products?.image_url,'https://placehold.co/100x80')",
    "safeImageUrl(w.products?.image_url,'https://placehold.co/100x80')",
    "safeImageUrl(i.variant?.image_url||i.products?.image_url,'https://placehold.co/70x60')",
    "safeImageUrl(p.image_url,'assets/shubhmart-logo.png?v=20260925')"
  ];
  for (const value of required) assert.ok(html.includes(value), "Missing safe image URL handling: " + value);
});
