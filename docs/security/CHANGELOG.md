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