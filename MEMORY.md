# ShubhMart Project Memory

Last reviewed: 2026-10-27. This is durable project context, not a claim that every item is current; verify live state before acting.

## Project identity
- Project: ShubhMart, a multi-vendor retail/wholesale marketplace with PWA/Android direction.
- Repository: `sschoudharyshubhammundhar-stack/ShubhMart`.
- Production Cloudflare Worker recorded in project context: `https://shubhmart.sschoudharyshubhammundhar.workers.dev`.
- Supabase project reference: `yauveaexbpokhytqijae`; Free tier only.
- Netlify `shubh-mart.netlify.app` was paused due free limits; do not introduce a Netlify dependency.

## Non-negotiable operating constraints
- Audit first; prefer read-only inspection and evidence before edits.
- Never perform production SQL writes, schema migrations, destructive database changes, RLS/grant/policy/trigger/RPC changes, Edge Function deploys, payment activation, production deploys, merges, paid-resource creation, or external account changes without explicit user approval.
- Do not delete/rebuild the project from scratch or replace working features without approval.
- Keep work on a dedicated non-production branch; small, reviewable changes; tests and rollback notes.
- Do not use production as a test environment. Use synthetic data and isolated test systems only.
- Never put credentials, API keys, service-role secrets, customer PII, payment credentials, or sensitive raw logs in files or commits.
- Never promise “hacker-proof”. State evidence, uncertainty, limitations, and residual risk.
- Use status labels consistently: PASS, FAIL, BLOCKED, MISSING, UNVERIFIED; use REVIEW for an open investigation.

## Security-first priorities
1. Authentication, authorization, IDOR, role separation, Supabase RLS/grants.
2. Secrets, data exposure, storage access, logging and privacy.
3. XSS/HTML injection, SQL injection, CSRF, CORS, sessions, rate limits and abuse controls.
4. Payment provider verification, webhook authenticity/replay, order binding, amount/currency/captured state.
5. Atomic checkout/idempotency; stock reservation for product + variant; coin debit/release; cancellation/expiry/refund and late-payment races.
6. Dependency and GitHub Actions supply-chain controls; Cloudflare preview/production separation.
7. Mobile/browser accessibility, responsiveness, regression and recovery testing.

## Known audit context — revalidate before relying on it
- PR #66 `security/h01-safe-image-url` is intended as draft-only; verify its live status and head SHA before each decision.
- HTTPS image URL checks were added for known dynamic sinks; source-level tests and a preview build do not prove complete browser/runtime security.
- Prior read-only audit reported live `razorpay-payment` v4 did not independently fetch/validate the provider payment entity before marking Paid; the live `create-customer-order` v4 coerced ShubhCoins input. Candidate fixes must not be assumed deployed.
- Checkout idempotency, parent+variant stock reserve/release, coin lifecycle, payment/order state transitions, RPC grants and trigger behavior require isolated tests and current database evidence.
- Supabase table/schema/security inspection previously timed out or was unavailable. RLS, grants, triggers, RPCs and transaction invariants must remain BLOCKED/UNVERIFIED until verified.
- No live checkout should be declared safe while critical findings remain open.

## Source-of-truth order
1. Current repository code at the exact branch/commit under review.
2. Current CI results tied to that exact commit.
3. Read-only live provider/database evidence, with timestamp and exact environment.
4. Dated audit notes under `docs/drafts/` and findings under `docs/security/`.
5. This memory file is orientation only; it never overrides current evidence.

## Required working style
- Before editing, identify the target branch, current commit, existing implementation, risks and rollback.
- Report what changed, exact paths/commit, tests actually run, and tests not run.
- Do not silently change scope. Ask for approval before prohibited production actions.
- Keep customer-facing copy in simple Hindi where appropriate; be precise and do not claim unverified success.

## Key documentation
See `AGENTS.md` for repository-wide instructions and `docs/security/README.md` for the security handbook. Keep this file short, dated, factual, and free of secrets.