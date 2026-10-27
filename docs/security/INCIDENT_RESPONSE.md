# ShubhMart Incident Response Runbook

Purpose: contain and investigate suspected account, data, payment, inventory, or deployment incidents without causing additional damage.

## 1. Triage
Record UTC time, reporter, environment, affected service, first known event, symptoms, request/trace IDs, and business impact. Preserve sanitized evidence. Do not include passwords, access tokens, API secrets, payment credentials, or unnecessary customer personal data.

Severity:
- SEV-1: confirmed secret compromise, unauthorized privileged access, broad customer-data exposure, fraudulent Paid transitions, or active destructive attack.
- SEV-2: suspected cross-account access, payment/order inconsistency, stock/coin corruption, or sustained service abuse.
- SEV-3: isolated suspicious behavior with no confirmed impact.
- SEV-4: low-risk defect or false positive.

## 2. Immediate containment
1. Notify the authorized project owner and relevant provider security contact.
2. Preserve logs and timestamps before changing state, where safe.
3. If a credential is confirmed exposed, revoke/rotate it through the provider's approved process; never paste it into a ticket or chat.
4. If payment integrity is in doubt, pause new payment acceptance only through an explicitly authorized procedure. Do not manually mark orders Paid or issue refunds without reconciliation.
5. If data exposure is suspected, restrict the affected access path only with owner approval and verify customer-facing impact.
6. Do not delete logs, orders, evidence, or database records as cleanup.

## 3. Investigate
- Build a UTC timeline from GitHub commits/deployments, Cloudflare build logs, Supabase function/database logs, provider payment records, and application events.
- Identify first affected commit/version and last known-good version.
- Classify the issue as confirmed, suspected, or unverified.
- Check whether server/provider secrets were present in client artifacts, logs, repository history, or CI output.
- For payment incidents, reconcile provider order/payment IDs, amount, currency, capture status, and internal order state.
- For stock/coin incidents, compare ledger history and determine whether duplicate retries or concurrent requests occurred.
- Use synthetic data for reproductions; avoid probing real customers' records.

## 4. Recovery
- Propose a minimal, reviewed fix on a branch.
- Require tests reproducing the failure and verifying negative cases.
- Use approved rollback/deployment procedure; do not run ad hoc SQL or mutate production data without explicit approval.
- Reconcile payment, inventory, and coin ledgers through a documented, authorized process.
- Verify recovery with health checks and scoped smoke tests.

## 5. Communication and follow-up
- Maintain one incident record with severity, impact, timeline, actions, evidence links, decisions, owner, and residual risk.
- Notify affected users/providers when required by applicable law or provider terms; obtain appropriate advice.
- Run a blameless post-incident review and add regression tests.
- Close only when containment, recovery, impact assessment, and follow-up ownership are documented.

## 6. Do not
- Claim no data was accessed merely because no obvious log exists.
- Share raw secrets, full customer data, or sensitive logs in public issues.
- Run destructive tests against production.
- Disable security controls to restore service quickly without a documented, approved risk decision.
