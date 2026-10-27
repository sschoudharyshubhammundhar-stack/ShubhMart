# ShubhMart Security Documentation

Purpose: one durable security handbook for ShubhMart. Keep this index updated whenever a security document is added, renamed, or retired.

## Operating rules
- Never describe any system as absolutely hacker-proof. State evidence and remaining uncertainty.
- Use PASS, FAIL, BLOCKED, MISSING, or UNVERIFIED for each control.
- Read-only audit first. No production SQL/write, schema migration, RLS/grant/policy/trigger/RPC change, Edge Function deploy, payment activation, production deploy, merge, or paid resource creation without explicit authorization.
- Preserve working features. Make changes on a non-production branch, with a narrow diff, tests, rollback notes, and review.
- Never place secrets, access tokens, customer PII, payment credentials, or raw sensitive logs in these documents.
- A preview build is not a test result; a passing source test is not proof of runtime security.

## Documents
- Threat model — THREAT_MODEL.md
- Findings register — FINDINGS_REGISTER.md
- Security test matrix — SECURITY_TEST_MATRIX.md
- Release gate — RELEASE_GATE.md
- Incident response — INCIDENT_RESPONSE.md
- Audit runbook — AUDIT_RUNBOOK.md
- Change log — CHANGELOG.md

## Current verified snapshot (2026-10-27)
- PR #66 on security/h01-safe-image-url is open, draft, and not merged.
- The image URL regression workflow ran for commit 76ae2ca; job safe-image-url-test completed successfully. Audit snapshot reports 2 tests passed, 0 failed. These are source-level checks only.
- Cloudflare preview build for 8f4fa7c succeeded; it was not a production deployment.
- Supabase project API reports ACTIVE_HEALTHY, but database table/migration calls timed out and Security Advisor was unavailable due hibernation. DB/RLS/grants/triggers/RPC state remains UNVERIFIED.
- Active Edge Functions observed: razorpay-payment v4 (verify_jwt=true), create-customer-order v4 (verify_jwt=true), shubhmart-ai v1 (verify_jwt=true). JWT verification alone does not prove business authorization.

## Update protocol
For every finding, record ID, severity, affected component, evidence and timestamp, impact, exploitability status, owner, remediation commit, tests, rollback plan, residual risk, and final status. Do not mark fixed until the relevant test and deployment state are independently verified.
