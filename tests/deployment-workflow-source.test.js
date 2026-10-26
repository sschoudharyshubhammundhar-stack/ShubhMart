const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const workflowPath = path.join(__dirname, "../.github/workflows/cloudflare-deploy.yml");
const workflow = fs.readFileSync(workflowPath, "utf8");

const prWorkflowPath = path.join(__dirname, "../.github/workflows/shubhmart-pr-checks.yml");
const prWorkflow = fs.readFileSync(prWorkflowPath, "utf8");

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

test("manual dispatch from a non-main ref cannot deploy the production Worker", () => {
  assert.match(workflow, /deploy:\s*\n[\s\S]*?needs:\s*pre-deploy-checks[\s\S]*?if:\s*github\.ref\s*==\s*['"]refs\/heads\/main['"]/);
});

test("Cloudflare deploy action is not placed in the pre-deploy checks job", () => {
  const gate = workflow.split(/\n  deploy:\n/)[0];
  assert.doesNotMatch(gate, /cloudflare\/wrangler-action/);
  assert.match(workflow, /cloudflare\/wrangler-action@v4/);
});

test("the workflow does not apply database migrations or deploy Supabase Edge Functions", () => {
  assert.doesNotMatch(workflow, /supabase db push|supabase migration up|supabase functions deploy/i);
});

test("PR validation workflow has no deployment or Supabase migration capability", () => {
  assert.match(prWorkflow, /pull_request:/);
  assert.match(prWorkflow, /permissions:\s*\n\s+contents: read/);
  assert.doesNotMatch(prWorkflow, /cloudflare\/wrangler-action|CLOUDFLARE_API_TOKEN|CLOUDFLARE_ACCOUNT_ID/);
  assert.doesNotMatch(prWorkflow, /supabase db push|supabase migration up|supabase functions deploy/i);
});

test("PR validation workflow does not grant repository write permissions", () => {
  assert.doesNotMatch(prWorkflow, /contents:\s*write|pull-requests:\s*write|actions:\s*write|id-token:\s*write/);
});
