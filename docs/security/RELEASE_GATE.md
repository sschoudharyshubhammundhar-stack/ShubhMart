# ShubhMart Security Release Gate

Default decision: NO-GO until every applicable mandatory gate is evidenced. This checklist is not proof that any gate has passed.

## Scope and change safety
- [ ] PR has narrow scope, linked finding, reviewer, and no unrelated changes.
- [ ] No production database write, migration, function deployment, payment activation, or production deployment without explicit approval.
- [ ] Build artifact and preview correspond to the exact reviewed commit.
- [ ] Rollback path and data compatibility are documented.
- [ ] No secrets, personal data, or raw sensitive logs in diff/artifacts.

## Code quality and supply chain
- [ ] Syntax/type checks pass on exact head SHA.
- [ ] All repository tests pass; no test skipped without documented reason.
- [ ] Security regression tests pass, including negative cases.
- [ ] Dependency and secret scans complete; findings triaged.
- [ ] CI permissions are least privilege; third-party actions reviewed and pinned where practicable.
- [ ] Production deployment is gated to approved main and required checks; branch protection and environment approvals verified.

## Authorization and data isolation
- [ ] Every exposed table has documented row-level security and verified grants.
- [ ] Cross-customer, cross-seller, and non-admin access tests fail safely.
- [ ] Sensitive RPC permissions and SECURITY DEFINER search_path reviewed.
- [ ] Client cannot set owner, role, price, paid state, coin balance, or stock state.
- [ ] Service-role credentials remain server-only.
- [ ] Database evidence is current; if database is unavailable, gate remains BLOCKED.

## Checkout, payment, stock, coins
- [ ] Server computes final amount from trusted prices and validated promotions.
- [ ] Provider payment entity is fetched server-to-server and order/payment/amount/currency/captured status matched.
- [ ] State transition is atomic and idempotent; duplicate/replay requests do not duplicate effects.
- [ ] Product and variant stock reservation is atomic and concurrency-safe.
- [ ] Failure, cancel, expiry, refund, and retry lifecycle is specified and tested.
- [ ] ShubhCoins ledger debit/release is atomic, bounded, and exactly once.
- [ ] Multi-seller ownership/order/refund/settlement model is explicit if enabled.
- [ ] Isolated negative-path and concurrency tests pass; no real money involved.

## Front end and API
- [ ] Dynamic content sinks and URL sinks reviewed in correct output context.
- [ ] CORS origins match product requirements; wildcard not retained without justification.
- [ ] HTTP methods, payload size, malformed JSON, errors, and abuse/rate-limit controls reviewed.
- [ ] Mobile and desktop preview tested for login, cart, order history, and checkout.
- [ ] Fallback behavior verified when image/provider/API fails.

## Operational readiness
- [ ] Monitoring/logging does not expose credentials or unnecessary personal data.
- [ ] Incident contact and containment steps are available.
- [ ] Backup/recovery and rollback have a tested procedure appropriate to change.
- [ ] Post-deploy smoke test and monitoring window are defined.
- [ ] Independent review signs off on findings and residual risks.

## Decision rules
- Any unresolved High/Critical finding: NO-GO.
- Database/RLS/payment/inventory state unavailable or unverified: BLOCKED, not PASS.
- Preview build success alone never satisfies security or functional test gates.
- Merge and production deployment require separate authorization when the project owner has reserved that decision.
