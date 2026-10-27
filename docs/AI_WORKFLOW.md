# AI-Assisted Development Workflow

## Required preflight
- Follow the detailed, canonical [AI Task Protocol](AI_TASK_PROTOCOL.md) to prevent repeated work, regressions, and incomplete handoffs.
- Read `AGENTS.md`, `MEMORY.md`, `RULES.md`, and relevant security documents.
- Confirm branch, current HEAD, PR status, and worktree context.
- Inspect current source/configuration before proposing edits.
- Classify each planned action as read-only, local/reversible, or externally impactful.

## Approval-required actions
Stop before production database writes, SQL execution, schema/migration or RLS/grant/policy/trigger/RPC changes, Edge Function deployment, real payment/OTP/credit activation, production deploy, PR merge, paid resources, or changes to external accounts/services. Explain the exact action and wait for explicit approval.

## Implementation
- Prefer small, reversible diffs.
- Preserve existing user-facing features and layouts.
- Avoid secrets and real personal/payment data.
- Use isolated test environments and synthetic fixtures.
- Add tests for security boundaries and regression-prone behavior.
- Do not use a successful build as a substitute for end-to-end or provider-side verification.

## Final report
List changed files, exact tests/checks and results, risks, unresolved blockers, rollback plan, and whether any action remains unapproved. Use PASS / FAIL / BLOCKED / MISSING / UNVERIFIED.
