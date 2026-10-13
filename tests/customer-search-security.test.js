const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('customer/customer-app.js', 'utf8');
const match = source.match(/function safeSearchTerm\(value\)\{[^\n]+\}/);

test('product search input is normalized before building PostgREST OR filters', () => {
  assert.ok(match, 'safeSearchTerm helper must exist');
  assert.match(source, /const q=safeSearchTerm\(document\.getElementById\("search"\)\?\.value\)/);
  const safeSearchTerm = vm.runInNewContext(`(${match[0]})`);
  assert.equal(safeSearchTerm('  lipstick  '), 'lipstick');
  assert.equal(safeSearchTerm("kid's,lipstick"), 'kid s lipstick');
  assert.equal(safeSearchTerm('x,y).or(id.not.is.null),z'), 'x y or id not is null z');
  assert.equal(safeSearchTerm('%_!*:"\\\\'), '');
  assert.equal(safeSearchTerm('a'.repeat(200)).length, 80);
});
