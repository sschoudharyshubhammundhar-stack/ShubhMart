# ShubhMart Security Findings Register

Status: active register; findings are not closed until evidence is independently verified.
Last reconciled: 2026-10-27.

| ID | Severity | Finding | Status | Required next evidence/action |
|---|---|---|---|---|
| H-02 | High | Razorpay payment verification does not independently fetch and validate the provider payment entity before Paid | FAIL — source-level gap; exploitability not tested | On a non-production branch, validate provider payment ID, linked order ID, amount in paise, INR currency, captured status, customer/order binding, and atomic idempotent transition; test in isolated environment |
| H-03 | Medium | Client-supplied ShubhCoins input is coercively normalized instead of strictly validated | FAIL — source-level gap | Strict schema and DB-side balance/discount/total checks; negative and malformed-input tests |
| H-04 | High | RLS, grants, RPCs, triggers, stock and coin invariants could not be inspected because Supabase inspection timed out | BLOCKED / UNVERIFIED | Repeat read-only database inspection when responsive; no SQL changes until verified |
| H-05 | Medium | Wildcard CORS on authenticated Edge Function endpoints requires product-origin review | REVIEW | Inventory required origins; test OPTIONS/POST and authenticated flows; CORS is not authorization |
| H-06 | Medium | Some provider/database errors may be exposed to clients | REVIEW | Return generic client errors; retain sanitized server-side diagnostics |
| H-07 | Low / verify | AI fallback uses client-provided product list | REVIEW — impact not confirmed | Ensure suggestions are non-authoritative; server-validate any product IDs before actions |
| IMG-01 | Low / scoped | HTTPS image URL validation added for known sinks | PARTIAL — source tests only | Browser/runtime tests for hostile schemes, malformed URLs, credentials, fallback and all dynamic sinks |

## Status definitions
- **PASS:** exact control tested on a recorded commit/environment and evidence retained.
- **FAIL:** evidence shows the control is missing or fails.
- **BLOCKED:** a required test cannot safely or technically be run yet.
- **MISSING:** required control or evidence has not been created.
- **UNVERIFIED:** insufficient evidence to conclude either pass or fail.
- **REVIEW:** concern requiring investigation; not yet a confirmed vulnerability.

## Required fields for every new finding
ID, discovery date/time (UTC), severity and rationale, component, evidence/commit/version, observed behavior, expected behavior, impact, exploitability confidence, affected data/roles, remediation owner, fix commit, regression tests, rollback, residual risk, verification evidence, and closure reviewer.

## Safety and closure rules
Do not put secrets, customer data, payment credentials, or raw sensitive logs here. Never close a finding solely because code changed or a preview build succeeded. Database/payment/inventory findings remain open until isolated tests and relevant database permissions/transaction semantics are verified.