# Instructions for AI Coding Agents — ShubhMart

These instructions apply to all agents and contributors working in this repository. Read `MEMORY.md`, `RULES.md`, `docs/AI_TASK_PROTOCOL.md`, and `docs/security/README.md` before making changes. Follow the task protocol to avoid repeated work, regressions, and incomplete handoffs.

## Mandatory preflight
1. Identify the current branch and exact HEAD commit; confirm the intended target branch.
2. Read the relevant source, tests, workflows, and existing audit documents before editing.
3. Determine whether the requested operation touches production, databases, secrets, payments, deployments, user data, or external accounts.
4. If an action is prohibited below or its impact is unclear, stop and ask for explicit approval.

## Never do without explicit user approval
- Merge or close a PR, push directly to production/main, deploy production, or change production routing.
- Run production SQL writes, migrations, destructive statements, or modify schema, policies, grants, RLS, triggers, RPCs, or Edge Functions.
- Activate live payments, change payment-provider settings, create paid resources, or alter billing.
- Delete/recreate project infrastructure, overwrite large files wholesale, or remove existing features.
- Expose, rotate, copy, or place secrets in repository files, chat, logs, tests, or artifacts.

## Security and implementation rules
- Treat all client input, URLs, database content, AI output, webhooks and provider callbacks as untrusted.
- Enforce authorization server-side and at the database boundary; hiding a UI control is not authorization.
- Payment success requires trusted server-to-server provider verification bound to the internal order, provider order/payment IDs, exact amount, currency, and captured/settled state as applicable.
- Make checkout, payment transitions, inventory reservations/releases and loyalty-ledger operations atomic and idempotent. Verify parent product and variant stock together.
- Never trust client-calculated price, discount, stock, role, seller ownership, payment status, coin balance or refund state.
- Avoid leaking provider/database errors, tokens, PII or secrets in responses and logs.
- Validate output for the destination context; safe URL checks alone do not prevent all XSS.
- Review CORS, CSRF, session handling, rate limiting, replay, IDOR, concurrency, and multi-seller boundaries.
- Use synthetic test data and an isolated environment for mutation, payment and concurrency tests.

## Change discipline
- Prefer the smallest safe patch. Preserve working behavior and maintain backward compatibility where possible.
- Do not claim a test passed unless it was actually run on the stated commit/environment and its result was observed.
- Run relevant tests, syntax/type checks, lint/build and secret/dependency checks where available. State all skipped checks.
- Every security fix needs a regression test, impact analysis, rollback notes, and evidence tied to the exact commit.
- Keep docs, findings register, changelog and index synchronized.
- Do not mark a finding fixed from a code diff or successful preview build alone.

## Status and reporting
Use PASS, FAIL, BLOCKED, MISSING, UNVERIFIED; use REVIEW for investigations. If a tool or permission fails, record the exact limitation; do not infer safety or absence.

## Completion checklist
- [ ] Scope and branch confirmed
- [ ] Existing code and related tests inspected
- [ ] No prohibited action performed
- [ ] Minimal diff reviewed
- [ ] Regression and relevant automated checks run
- [ ] Exact commit and test results recorded
- [ ] Security docs/index/findings updated if applicable
- [ ] Remaining risks, blocked checks and rollback documented

See `MEMORY.md` for current project context and `docs/security/RELEASE_GATE.md` before any release decision.