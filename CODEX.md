# Codex / Coding Agent Guidance

Read `AGENTS.md` and `MEMORY.md` before starting; consult `docs/security/README.md` for security work. These are project-specific guardrails, not permission to take production actions.

Use read-only audit first and make the smallest reviewable change on a non-production branch. No production writes/migrations, security policy/grant/RPC/trigger changes, Edge Function deployment, live payment activation, production deploy, merge, paid service, or destructive change without explicit user approval. Use isolated synthetic test environments. Run and report only checks actually observed on the exact commit. Do not declare payment, inventory, RLS or checkout safe without evidence. Update tests, rollback notes, findings and docs together.