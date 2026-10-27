# ShubhMart Security Findings Register

Status: active register; findings are not closed until evidence is independently verified.
Last reconciled: 2026-10-27. Sources include the read-only security snapshot and draft checkout audit; re-fetch live evidence before release.

| ID | Severity | Finding | Status | Required next evidence/action |
|---|---|---|---|---|
| H-02 | High | Live Razorpay verification does not independently fetch and validate the provider payment entity before Paid | FAIL — source-level gap; exploitability not tested | Candidate on non-production branch; verify payment ID, linked provider order, internal order/customer binding, exact amount in paise, INR currency and captured status; atomic idempotent transition; isolated negative tests |
| H-03 | Medium | Live ShubhCoins input is coercively normalized instead of strictly validated | FAIL — source-level gap | Strict schema plus database-side balance/discount/total enforcement; malformed-input tests |
| H-04 | High | RLS, grants, RPCs, triggers, stock/coin invariants could not be inspected because Supabase inspection timed out/hibernated | BLOCKED / UNVERIFIED | Repeat read-only schema, policies, grants, RPC and trigger inspection when responsive; no SQL changes until verified |
| H-05 | Medium | Wildcard CORS on authenticated Edge Function endpoints needs product-origin review | REVIEW | Inventory required origins; test OPTIONS/POST and authenticated flows; CORS is not authorization |
| H-06 | Medium | Some provider/database error details may be returned to clients | REVIEW | Generic client errors; sanitized server-side diagnostics; test no secrets/PII in logs or responses |
| H-07 | Low / verify | AI fallback uses client-provided product list | REVIEW — impact not confirmed | Keep output advisory; server-validate product IDs and visibility before any authoritative action |
| H-08 | Critical | Durable checkout idempotency and replay response are not demonstrated consistently across callers | BLOCKED / UNVERIFIED | Define customer-bound durable key, unique constraint and atomic replay behavior; test identical/conflicting retries and concurrent calls in isolated DB |
| H-09 | Critical | Parent-product and variant stock reservation/restoration are not reconciled end-to-end | FAIL / BLOCKED — candidate does not satisfy locked parent-plus-variant contract | Atomic reserve/release invariant; cancellation, expiry, failed/late payment and concurrency tests in isolated DB |
| H-10 | Critical | Coin debit/release, payment state and order lifecycle may diverge on retries/failure | BLOCKED / UNVERIFIED | One documented transaction/state machine; ledger uniqueness; failure/cancel/expiry/refund/replay tests |
| H-11 | High | Payment-order attachment RPC grant/caller compatibility may fail after provider order creation | UNVERIFIED | Inspect live EXECUTE grants and caller role; isolated test provider-order success + DB persistence failure and recovery |
| H-12 | High | Paid-state trigger/RPC behavior under service-role context is not runtime verified | UNVERIFIED | Inspect trigger/RPC/auth.uid()/admin checks and grants read-only; isolated integration test |
| H-13 | High | Multi-seller order ownership, refunds, settlement and row access semantics are unresolved | MISSING / UNVERIFIED | Document parent/child order model and seller attribution; test seller isolation, refunds, returns and settlement permissions |
| H-14 | Medium | Branch protection, required checks, environment approvals, and Cloudflare token scope are not fully verified | UNVERIFIED | Obtain settings evidence; permission-denied results remain UNVERIFIED, not PASS |
| H-15 | Medium | Browser/runtime hostile URL and complete DOM XSS coverage is not evidenced | BLOCKED / UNVERIFIED | Audit every dynamic sink and test hostile input on desktop/mobile preview with synthetic data |
| H-16 | Medium | Data retention, deletion, storage access, and logging inventory is not yet populated from live systems | MISSING | Complete DATA_INVENTORY_AND_PRIVACY.md from actual schema/storage/provider/log paths and verify controls |
| IMG-01 | Low / scoped | HTTPS image URL validation added for known sinks | PARTIAL — source tests only | Browser/runtime tests for hostile schemes, malformed URLs, credentials, fallback and all dynamic sinks |

## Status definitions
- **PASS:** exact control tested on a recorded commit/environment and evidence retained.
- **FAIL:** evidence shows the control is missing or fails.
- **BLOCKED:** required test cannot safely or technically be run yet.
- **MISSING:** required control or evidence has not been created.
- **UNVERIFIED:** insufficient evidence to conclude pass or fail.
- **REVIEW:** concern requiring investigation; not yet a confirmed vulnerability.

## Required fields for every new finding
ID, discovery date/time (UTC), severity and rationale, component, evidence/commit/version, observed behavior, expected behavior, impact, exploitability confidence, affected data/roles, remediation owner, fix commit, regression tests, rollback, residual risk, verification evidence, and closure reviewer.

## Safety and closure rules
Do not put secrets, customer data, payment credentials, or raw sensitive logs here. Never close a finding solely because code changed or a preview build succeeded. Database/payment/inventory findings remain open until isolated tests and relevant database permissions/transaction semantics are verified. Critical unresolved findings mean checkout is NO-GO; do not enable live payments.