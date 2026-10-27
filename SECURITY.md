# Security Policy — ShubhMart

## Scope and safe handling
Security work must be authorized and preferably performed through read-only inspection or isolated test environments. Do not probe third-party systems, production customer accounts, or payment systems without explicit authorization. Do not place credentials, personal data, or exploitable sensitive details in public issues.

## Reporting a concern
Please report security concerns privately to the repository owner/maintainer using a private channel available to them. Include:
- A concise description and affected component
- Impact and prerequisites
- Reproduction steps using synthetic data, if safe
- Evidence with secrets and personal data removed
- Suggested mitigation, if known

Do not publish access tokens, service-role keys, payment secrets, customer information, or a working exploit against live users.

## Response expectations
Reports should be triaged for severity, reproducibility, affected versions, and safe remediation. Until verified, findings must be labelled as suspected or unverified rather than confirmed. This file does not promise a specific response time or bug-bounty reward.

## Project safety boundary
No production SQL/migrations, RLS/grant/policy/trigger/RPC changes, Edge Function deployment, payment activation, production deployment, or PR merge without explicit approval.
