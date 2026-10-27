# ShubhMart Project Rules

This file is the human-readable, cross-tool summary of repository rules. `AGENTS.md` is the primary agent instruction file; `MEMORY.md` is durable project context. If guidance conflicts, follow the stricter safety boundary and ask for clarification.

## Non-negotiable boundaries
- Audit first. Verify the current branch, working tree, relevant code, deployment target, and existing behavior before proposing changes.
- Do not make production database writes, run SQL, apply migrations, alter RLS/grants/policies/triggers/RPCs, deploy Edge Functions, change payment settings, enable real OTP/credit/payment flows, deploy production, merge a PR, create paid resources, or change external services without explicit user approval for that exact action.
- Do not delete/rebuild the project or replace working features to simplify implementation.
- Use isolated test data and non-production environments for tests. Never use real customer/payment data in fixtures or logs.
- Never expose secrets, tokens, service-role keys, private customer data, or sensitive environment values.
- Do not claim a control is secure merely because a unit test or build passes.

## Required workflow
1. Read `AGENTS.md`, `MEMORY.md`, and the relevant security documents.
2. Confirm branch and current state; inspect relevant code and configuration read-only first.
3. State scope, risks, expected files, and whether any action crosses an approval boundary.
4. Prefer the smallest reversible change. Preserve existing behavior and keep secrets out of source control.
5. Run relevant tests/build/type checks when available; report commands and actual results.
6. Update documentation and tests where appropriate.
7. Report PASS / FAIL / BLOCKED / MISSING / UNVERIFIED with evidence, remaining risks, and rollback notes.

## Security priorities
Authentication and authorization, IDOR, Supabase RLS/grants, secrets and privacy, input validation, XSS/SQLi/CSRF/CORS/session controls, abuse limits, payment-provider verification and replay resistance, idempotent checkout, inventory/variant concurrency, points/coins lifecycle, and CI/deployment supply chain.

## Evidence and honesty
Distinguish source review from runtime verification. Do not describe an untested exploit as confirmed, or an unverified control as passing. Record blockers when a safe verification path is unavailable.
