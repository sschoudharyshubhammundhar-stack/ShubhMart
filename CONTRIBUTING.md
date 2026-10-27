# Contributing to ShubhMart

## Before contributing
1. Read `AGENTS.md`, `MEMORY.md`, `RULES.md`, and the relevant documents in `docs/security/`.
2. Confirm the branch and inspect the current implementation before changing it.
3. Identify the intended behavior, risk, affected modules, and tests.

## Change standards
- Keep changes scoped, reviewable, and reversible.
- Preserve working functionality and mobile responsiveness.
- Never commit secrets, real customer data, payment credentials, or private logs.
- Use isolated synthetic data for testing.
- Do not make production database/security-policy changes, deploy, merge, enable real payment/OTP/credit flows, or incur costs without explicit approval.

## Validation
Run the relevant tests, lint, type checks, and build where available. State which checks were run and their actual results. A passing build does not establish authorization correctness, payment safety, or runtime security.

## Pull request description
Include:
- What changed and why
- Files/modules affected
- Tests and results
- Security/privacy implications
- Known gaps and rollback approach
- Any action requiring user approval

Use PASS / FAIL / BLOCKED / MISSING / UNVERIFIED accurately.
