# ShubhMart Cline Rules

Read `AGENTS.md`, `MEMORY.md`, and `RULES.md` first.

## Approval gates
Stop and ask for explicit approval before production DB writes, SQL execution, migrations, RLS/grant/policy/trigger/RPC changes, Edge Function deployments, payment/OTP/credit activation, production deployment, PR merge, paid services, or external account changes.

## Safe implementation
- Audit before changes; inspect branch and working tree.
- Keep changes small and reversible; preserve existing behavior.
- Use isolated test data only; do not expose secrets or customer data.
- Verify with relevant tests and report exact results.
- Label unknowns UNVERIFIED or BLOCKED rather than assuming success.
