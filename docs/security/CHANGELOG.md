# Security Documentation Changelog

Record material changes to this security documentation and audit state. This file is not a substitute for Git commit history.

## 2026-10-27
- Added security handbook index, threat model, test matrix, release gate, audit runbook, and incident response runbook.
- Added findings register based on the read-only snapshot dated 2026-10-27.
- Recorded known limitations: Supabase read-only inspection timed out; RLS/grants/RPCs/triggers and checkout invariants remain BLOCKED/UNVERIFIED.
- Confirmed the image URL source regression checks and Cloudflare preview build are limited evidence, not end-to-end security certification.
- PR #66 remains draft/open/unmerged; no production changes were performed.

## Maintenance rule
Append a dated entry whenever a security document or finding status changes. Include the relevant commit/PR and evidence links where available. Never rewrite historical entries to imply that an unperformed test passed.
## 2026-10-27 — expanded coverage
- Added authorization matrix, data inventory/privacy controls, checkout/payment state-machine contract, and CI/CD supply-chain checklist.
- Expanded findings register with critical checkout idempotency, inventory/variant, coin lifecycle, RPC compatibility, multi-seller, browser XSS, and governance evidence gaps.
- Updated handbook index and links. These are specifications and audit records, not proof that controls are implemented or tests have passed.
- Reaffirmed NO-GO for live checkout until critical findings are resolved and isolated end-to-end evidence exists.
