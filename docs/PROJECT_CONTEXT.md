# ShubhMart Project Context

For durable project-specific context, start with the root `MEMORY.md`. For mandatory behavior and approval boundaries, read `AGENTS.md` and `RULES.md`.

## Current architecture and environment
Treat details in memory and prior audit snapshots as historical until rechecked. Verify the current Git branch, PR head, Cloudflare Worker configuration, Supabase schema/policies, and hosting status before relying on them. The intended deployment uses Cloudflare and Supabase Free; do not introduce a Netlify dependency or paid resources without explicit approval.

## Safety constraints
- Audit first and use read-only inspection by default.
- No production DB writes, SQL/migrations, security-policy changes, deployed function changes, payment activation, production deploy, merge, or external account changes without explicit approval.
- Keep real payments, OTP, and ShubhCredit disabled unless explicitly authorized.
- Preserve existing functionality; use synthetic fixtures in isolated tests.
- Report uncertainty honestly and attach evidence.

## Source-of-truth order
1. Current repository source and configuration for what code exists.
2. Current branch/PR state for what is proposed.
3. Current read-only platform inspection for live configuration.
4. Dated audit snapshots for historical findings only.
5. `MEMORY.md` for continuity, not as proof of live state.

See `docs/security/README.md` for the security documentation index.
