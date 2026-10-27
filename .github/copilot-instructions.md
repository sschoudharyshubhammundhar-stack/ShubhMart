# GitHub Copilot Instructions — ShubhMart

Read `/AGENTS.md`, `/MEMORY.md`, and `/docs/security/README.md` before substantial changes.

- Preserve existing features; inspect before editing.
- Do not perform production DB writes/migrations, RLS/grant/policy/trigger/RPC changes, Edge Function deployment, payment activation, production deployment, PR merge, paid-resource creation, or destructive edits without explicit user approval.
- Treat all client input and provider callbacks as untrusted; enforce server/database authorization.
- Use atomic idempotent checkout/payment/inventory/coin operations; verify provider payment details server-to-server.
- Never put secrets or customer data in source, tests, docs or logs.
- Use isolated synthetic data for mutation and payment tests.
- Report exact branch/commit, observed tests and results, skipped checks, remaining risks and rollback plan.
- Keep `MEMORY.md`, `AGENTS.md`, security docs, findings register and changelog consistent.