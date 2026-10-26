# ShubhMart CI/CD Security Review — 2026-10-25

Status: **READ-ONLY WORKFLOW REVIEW — PRODUCTION RELEASE GATE REQUIRED**
Reviewed branch: `fix/secure-checkout-edge-function`

## Safety boundary

Inspected workflow files and source through GitHub read-only retrieval. No workflow was executed, no deployment was triggered, no secrets were read, and no repository settings were changed.

## Finding CI-01 — Manual production deployment path needs guardrails

**Severity: HIGH pending repository/environment configuration verification.**

Evidence:
- `.github/workflows/cloudflare-deploy.yml` triggers on pushes to `main` and on `workflow_dispatch`.
- The workflow invokes `cloudflare/wrangler-action@v4` with the repository's Cloudflare token/account secrets.
- No GitHub Actions `environment:` protection is declared in the inspected workflow.
- The workflow does not visibly run the checkout regression suite, SQL tests, dependency audit, or a build/typecheck before deployment.

Risk:
- A manual workflow dispatch from a non-protected ref may allow code from that ref to be deployed, depending on GitHub repository settings and how dispatch is initiated.
- Syntax-valid JavaScript can still contain authorization bugs, unsafe database calls, payment-state errors, or UI/runtime regressions.
- Without environment-level required reviewers and deployment branch restrictions, workflow-dispatch permission may be too close to production deployment authority.

Qualification: this is a workflow-source finding, not proof that an unauthorized person can deploy. Repository rulesets, branch protection, environment settings, token scope and actual GitHub permissions remain **UNVERIFIED**.

## Finding CI-02 — Deployment validation covers JavaScript, not the Supabase TypeScript functions

**Severity: HIGH / validation coverage gap.**

The deploy workflow's syntax loop searches for `*.js` and runs `node --check`. The inspected Supabase Edge Function sources are `*.ts`, so they are not checked by that loop. This does not prove those files are invalid; it proves the deployment workflow does not validate them through this step.

**Required remediation:** add pinned Deno formatting/lint/type checks and function tests for every changed Edge Function. Keep provider interactions mocked or in test mode.

## Finding CI-03 — Checkout regression tests are not a required step in the inspected deploy workflow

**Severity: HIGH / release gate gap.**

The separate `.github/workflows/shubhmart-pr-checks.yml` runs JavaScript syntax checks and `node --test tests/*.test.js`. The inspected Cloudflare deploy workflow does not invoke those checkout regression tests or explicitly depend on their successful completion. Whether branch protection independently requires those checks is **UNVERIFIED**.

**Required remediation:** configure a fail-closed release gate that requires the exact commit's complete checks before deployment. Verify branch protection and required status checks through authorized settings access.

## Finding CI-04 — Static tests are not database or provider integration proof

**Severity: HIGH / test coverage gap.**

Checkout regression tests use source matching/regular expressions. They can catch accidental code-pattern regressions but cannot execute PostgreSQL transactions, RLS policies, trigger logic, concurrency races, Razorpay API behavior or real Edge Runtime semantics.

**Required remediation:** run the documented P0 matrix against a disposable PostgreSQL/Supabase fixture with synthetic data, then run Deno tests and Razorpay sandbox/mock tests. Capture logs and before/after state snapshots. Never use live checkout as a test.

## Finding CI-05 — Production deployment is not coupled to Supabase checkout readiness

**Severity: HIGH / release gate gap.**

The inspected Cloudflare workflow deploys the Worker only. It does not verify that live Supabase functions match repository candidate source, or that database migrations, grants, RLS and payment state transitions have been tested. A Cloudflare deploy preview or JavaScript syntax pass cannot prove checkout safety.

**Required remediation:** maintain a release manifest recording the exact Worker commit, Supabase function version/hash, schema/migration state, test evidence and reviewer sign-off. Use a staged rollout and rollback procedure. Do not automatically deploy database/payment changes as part of this audit.

## Required remediation before production deployment

1. Verify branch protection/rulesets for `main`; require reviewed PRs and required status checks.
2. Configure a protected GitHub Actions production environment with required reviewers and deployment branch restrictions (only approved `main`).
3. Separate preview and production deploy workflows; require explicit protected-environment approval for production.
4. Run JavaScript tests, Deno/type checks, dependency/secret scanning and relevant checkout regression tests before deployment. Do not treat source-pattern checks as runtime/database tests.
5. Pin third-party Actions to reviewed immutable commit SHAs where practical; keep permissions least-privilege.
6. Ensure the Cloudflare token is scoped to only required account/Worker resources; verify scope without exposing token contents.
7. Add post-deployment smoke checks and rollback procedures that do not perform real payments or mutate customer data.
8. Confirm the workflow cannot deploy unreviewed refs through manual dispatch; test this only in a non-production environment.
9. Ensure the deployed commit and the tested commit are exactly the same.

## Required validation

- [ ] Read branch protection/rulesets and confirm required PR review/status checks.
- [ ] Read production environment protection and allowed deployment refs.
- [ ] Verify Cloudflare API token scope without exposing token contents.
- [ ] Confirm exact dispatch behavior with a harmless non-production test.
- [ ] Confirm the workflow's tested commit is the same commit intended for deployment.
- [ ] Run Deno checks for Supabase TypeScript functions.
- [ ] Run isolated SQL transaction, RLS/grant, inventory, ShubhCoins, idempotency and payment tests.
- [ ] Verify rollback/recovery path.

## Related live payment blocker

The live deployed `razorpay-payment` v4 source differs from the checked-in candidate and does not independently fetch the Razorpay payment entity before marking the order paid. This remains a release blocker regardless of CI status. The candidate includes provider-side checks but is not deployed and is not release-ready until its RPC/grants, idempotency and isolated tests are complete.

## Current verdict

**BLOCKED / UNVERIFIED.** The inspected deploy workflow checks JavaScript syntax and then deploys Cloudflare; it does not itself run the full checkout security suite or type-check the Supabase TypeScript functions. Branch protection, environment approvals and token scope remain **UNVERIFIED**. Do not trigger production deployment as part of this review. No production deployment, database write, secret read or settings change was performed.
