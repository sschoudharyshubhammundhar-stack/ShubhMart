# ShubhMart CI/CD Security Review — 2026-10-25

Status: source-level review only. No workflow was executed, no deployment was triggered, and no repository settings were changed.

Reviewed branch: `fix/secure-checkout-edge-function`

## Finding CI-01 — Manual production deployment path needs guardrails

Severity: HIGH pending repository/environment configuration verification.

Evidence:
- `.github/workflows/cloudflare-deploy.yml` triggers on pushes to `main` and on `workflow_dispatch`.
- The workflow runs JavaScript syntax checks and then invokes `cloudflare/wrangler-action@v4` with the repository's Cloudflare token/account secrets.
- No GitHub Actions `environment:` protection is declared in the inspected workflow.
- The workflow does not visibly run the checkout regression suite, SQL tests, dependency audit, or a build/typecheck before the deployment step.

Risk:
- A manual workflow dispatch from a non-protected ref may allow code from that ref to be deployed, depending on GitHub repository settings and how the dispatch is initiated.
- Syntax-valid JavaScript can still contain authorization bugs, unsafe database calls, payment-state errors, or UI/runtime regressions.
- Without environment-level required reviewers and deployment branch restrictions, possession of workflow-dispatch permission may be too close to production deployment authority.

Important qualification:
- This is a workflow-source finding, not proof that an unauthorized person can deploy. Repository rulesets, branch protection, environment settings, token scope, and actual GitHub permissions were not verified in this review.

## Required remediation before production deployment

1. Verify branch protection/rulesets for `main`; require reviewed PRs and required status checks.
2. Configure a protected GitHub Actions environment for production with required reviewers and deployment branch restrictions (allow only the approved default branch).
3. Separate preview and production deploy workflows; make production deployment require an explicit protected environment approval.
4. Run the required static/security checks and relevant checkout regression suite before any deploy step. Do not treat regex/source checks as runtime/database tests.
5. Pin third-party Actions to reviewed immutable commit SHAs where practical; keep permissions least-privilege.
6. Ensure the Cloudflare token is scoped to only the required account/Worker resources; periodically rotate it and never print it in logs.
7. Add a post-deployment smoke check and rollback procedure that does not perform real payments or mutate customer data.
8. Confirm the workflow cannot deploy unreviewed refs through manual dispatch; test this in a non-production environment.

## Required validation

- [ ] Read branch protection/rulesets and confirm required PR review/status checks.
- [ ] Read production environment protection and allowed deployment refs.
- [ ] Verify Cloudflare API token scope without exposing token contents.
- [ ] Confirm exact dispatch behavior with a harmless non-production test.
- [ ] Confirm the workflow's tested commit is the same commit intended for deployment.
- [ ] Verify rollback/recovery path.

## Current verdict

**BLOCKED / UNVERIFIED.** Do not trigger production deployment as part of this review. No production deployment, database write, secret read, or settings change was performed.
