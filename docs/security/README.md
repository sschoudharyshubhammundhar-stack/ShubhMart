# ShubhMart Security Documentation

Purpose: the security handbook and evidence index for ShubhMart. Update this index whenever a document is added, renamed, or retired.

## Operating rules
- Never describe any system as absolutely hacker-proof. State evidence and remaining uncertainty.
- Use PASS, FAIL, BLOCKED, MISSING, or UNVERIFIED for each control; REVIEW means investigation is pending.
- Read-only audit first. No production SQL/write, schema migration, RLS/grant/policy/trigger/RPC change, Edge Function deploy, payment activation, production deploy, merge, or paid resource creation without explicit authorization.
- Preserve working features. Use a non-production branch, narrow diff, tests, rollback notes, and review.
- Never put secrets, access tokens, customer PII, payment credentials, or raw sensitive logs in documentation.
- A preview build is not a test result; passing source tests do not prove runtime security.

## Persistent AI/project context files
- Repository memory — [../../MEMORY.md](../../MEMORY.md)
- Universal agent rules — [../../AGENTS.md](../../AGENTS.md)
- Claude guidance — [../../CLAUDE.md](../../CLAUDE.md)
- Gemini guidance — [../../GEMINI.md](../../GEMINI.md)
- Codex guidance — [../../CODEX.md](../../CODEX.md)
- GitHub Copilot guidance — [../../.github/copilot-instructions.md](../../.github/copilot-instructions.md)
- Cursor rules — [../../.cursor/rules/shubhmart.mdc](../../.cursor/rules/shubhmart.mdc)

`AGENTS.md` and `MEMORY.md` are the canonical references. Tool-specific files repeat the core guardrails for agents that do not automatically read the canonical files.

- Cross-tool project rules — [../../RULES.md](../../RULES.md)
- Project context — [../PROJECT_CONTEXT.md](../PROJECT_CONTEXT.md)
- AI-assisted workflow — [../AI_WORKFLOW.md](../AI_WORKFLOW.md)
- Canonical AI task protocol and handoff — [../AI_TASK_PROTOCOL.md](../AI_TASK_PROTOCOL.md)
- Contribution workflow — [../../CONTRIBUTING.md](../../CONTRIBUTING.md)
- Security reporting policy — [../../SECURITY.md](../../SECURITY.md)
- Legacy Cursor rules entrypoint — [../../.cursorrules](../../.cursorrules)
- Windsurf rules — [../../.windsurfrules](../../.windsurfrules)
- Cline rules — [../../.clinerules/01-shubhmart.md](../../.clinerules/01-shubhmart.md)
- GitHub Copilot path-scoped instructions — [../../.github/instructions/shubhmart.instructions.md](../../.github/instructions/shubhmart.instructions.md)

## Security documents
- Threat model — [THREAT_MODEL.md](THREAT_MODEL.md)
- Findings register — [FINDINGS_REGISTER.md](FINDINGS_REGISTER.md)
- Security test matrix — [SECURITY_TEST_MATRIX.md](SECURITY_TEST_MATRIX.md)
- Authorization matrix — [AUTHORIZATION_MATRIX.md](AUTHORIZATION_MATRIX.md)
- Data inventory and privacy controls — [DATA_INVENTORY_AND_PRIVACY.md](DATA_INVENTORY_AND_PRIVACY.md)
- Checkout and payment state machine — [CHECKOUT_STATE_MACHINE.md](CHECKOUT_STATE_MACHINE.md)
- CI/CD and supply-chain review — [CI_SUPPLY_CHAIN.md](CI_SUPPLY_CHAIN.md)
- Release gate — [RELEASE_GATE.md](RELEASE_GATE.md)
- Incident response — [INCIDENT_RESPONSE.md](INCIDENT_RESPONSE.md)
- Read-only audit runbook — [AUDIT_RUNBOOK.md](AUDIT_RUNBOOK.md)
- Documentation changelog — [CHANGELOG.md](CHANGELOG.md)
- Dated audit evidence — [../drafts/SECURITY_AUDIT_SNAPSHOT_2026-10-27.md](../drafts/SECURITY_AUDIT_SNAPSHOT_2026-10-27.md)

## Current evidence snapshot (2026-10-27; revalidate before relying on it)
- PR #66 on `security/h01-safe-image-url` was open, draft, and unmerged at the time of the snapshot.
- The image URL regression workflow for commit `76ae2ca` reported 2 source-level tests passed and 0 failed. This does not prove browser behavior or all XSS cases.
- Cloudflare preview build for `8f4fa7c` succeeded; it was not a production deployment.
- Supabase table/migration calls timed out and Security Advisor was unavailable. RLS, grants, triggers, RPCs, checkout and inventory invariants remain BLOCKED/UNVERIFIED.
- Active Edge Functions observed: `razorpay-payment` v4, `create-customer-order` v4, and `shubhmart-ai` v1, all with `verify_jwt=true`. JWT verification alone does not prove business authorization.
- The snapshot records source-level payment verification and ShubhCoins input-validation gaps requiring remediation and isolated testing.

## Update and closure protocol
For every finding, record ID, severity, affected component, evidence and timestamp, impact, exploitability confidence, owner, remediation commit, tests, rollback plan, residual risk, and final verification. Do not mark fixed until relevant tests and deployment state are independently verified. When a system is unavailable, record BLOCKED/UNVERIFIED rather than assuming safety.