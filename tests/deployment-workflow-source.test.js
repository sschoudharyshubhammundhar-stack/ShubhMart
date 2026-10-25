const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const workflowPath = path.join(__dirname, "../.github/workflows/cloudflare-deploy.yml");
const workflow = fs.readFileSync(workflowPath, "utf8");

test("Cloudflare deployment is a separate job that depends on pre-deploy checks", () => {
  assert.match(workflow, /pre-deploy-checks:/);
  assert.match(workflow, /deploy:[\s\S]*?needs:\s*pre-deploy-checks/);
});

test("pre-deploy gate runs checkout regression tests and type-checks both checkout Edge Functions", () => {
  const gate = workflow.split(/\n  deploy:\n/)[0];
  assert.match(gate, /node --test tests\/\*\.test\.js/);
  assert.match(gate, /deno check supabase\/functions\/create-customer-order\/index\.ts/);
  assert.match(gate, /deno check supabase\/functions\/razorpay-payment\/index\.ts/);
});

test("deployment workflow grants only repository read permission to its GitHub token", () => {
  assert.match(workflow, /permissions:\s*\n\s+contents: read/);
  assert.doesNotMatch(workflow, /contents:\s*write/);
  assert.doesNotMatch(workflow, /pull-requests:\s*write/);
});

test("Cloudflare deploy action is not placed in the pre-deploy checks job", () => {
  const gate = workflow.split(/\n  deploy:\n/)[0];
  assert.doesNotMatch(gate, /cloudflare\/wrangler-action/);
  assert.match(workflow, /cloudflare\/wrangler-action@v4/);
});

test("the workflow does not apply database migrations or deploy Supabase Edge Functions", () => {
  assert.doesNotMatch(workflow, /supabase db push|supabase migration up|supabase functions deploy/i);
});
