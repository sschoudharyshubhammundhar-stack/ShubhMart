# ShubhMart Security Test Matrix

Status: test specification, not a report of all tests executed. Run only against local/isolated test infrastructure with synthetic data.

| ID | Area | Test | Expected result | Evidence |
|---|---|---|---|---|
| IMG-01 | Image URL | Valid HTTPS URL | Accepted | Source regression tests only |
| IMG-02 | Image URL | HTTP, unsafe scheme, malformed URL | Rejected/fallback | Runtime UNVERIFIED |
| IMG-03 | Image URL | Embedded URL credentials | Rejected/fallback | Helper source reviewed |
| UI-01 | HTML output | Product name containing markup | Rendered as text; no execution | UNVERIFIED |
| UI-02 | HTML output | Error message containing markup | Rendered as text | UNVERIFIED |
| AUTH-01 | Authentication | Missing, invalid, expired token | 401/403; no mutation | JWT config observed; paths UNVERIFIED |
| AUTH-02 | Object access | Customer A requests customer B order/address/cart | Denied; no data leak | UNVERIFIED |
| AUTH-03 | Seller access | Seller A mutates seller B product/order | Denied | UNVERIFIED |
| AUTH-04 | Admin access | Customer attempts admin action | Denied server-side | UNVERIFIED |
| DB-01 | Row security | CRUD tests on every exposed table | Only intended access succeeds | BLOCKED |
| DB-02 | RPC permissions | Unauthorized role invokes sensitive RPC | Denied | BLOCKED |
| PAY-01 | Payment | Invalid signature | No Paid state | UNVERIFIED |
| PAY-02 | Payment | Provider order/payment/amount/currency mismatch | No Paid state | Independent provider check absent in active source |
| PAY-03 | Payment | Failed or authorized-not-captured payment | No Paid state | UNVERIFIED |
| PAY-04 | Replay | Same verification request repeated | Idempotent; no duplicate effects | UNVERIFIED |
| PAY-05 | Concurrency | Two verification calls simultaneously | One transition only | UNVERIFIED |
| ORD-01 | Coins input | Negative, fractional, boolean, object, exponent, unsafe integer | Reject with 4xx | Active coercion gap |
| ORD-02 | Idempotency | Same checkout key retried | Same order/result; no duplicate debit | UNVERIFIED |
| INV-01 | Inventory | Two customers buy last unit simultaneously | At most one succeeds | UNVERIFIED |
| INV-02 | Variants | Product and variant stock change | Atomic, consistent update | UNVERIFIED |
| INV-03 | Recovery | Payment failure/cancel/expiry | Reserved stock restored once | UNVERIFIED |
| COIN-01 | Coin ledger | Insufficient balance or repeated debit | Reject or debit once | UNVERIFIED |
| API-01 | HTTP method | Unsupported method | 405; no mutation | Function-specific check needed |
| API-02 | Abuse | Oversized/malformed payload and repeated calls | Bounded errors and rate limits | UNVERIFIED |
| API-03 | CORS | Untrusted browser origin | Only intended origins allowed where needed | Wildcard observed; policy unresolved |
| SEC-01 | Secrets | Scan source, history, build artifacts | No server/provider secret exposure | Full scan UNVERIFIED |
| DEP-01 | Dependencies | Lockfiles and known advisories | No unaccepted critical/high findings | UNVERIFIED |
| CI-01 | Deployment | PR cannot deploy production; approved main only | Enforced by workflow/settings | Protections UNVERIFIED |
| REC-01 | Recovery | Rollback/restore rehearsal with synthetic data | Documented recovery succeeds | UNVERIFIED |

## Test report template
Record UTC time, commit SHA, environment, tool/version, test ID, sanitized command, expected result, observed result, artifact link, PASS/FAIL/BLOCKED, and reviewer. Never attach secrets or customer data.

## Safety
Do not run destructive, high-volume, payment, or authorization tests against production. Use synthetic records and isolated environments.
