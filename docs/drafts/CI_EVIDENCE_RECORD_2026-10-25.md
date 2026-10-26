# CI Evidence Record — ShubhMart — 2026-10-25

This record corrects the earlier statement that no workflow run was visible for commit `7a05cdd3114225e38999c30ce8fc453c30c9d026`. The earlier helper query did not expose the push runs; the GitHub Actions runs API was then queried directly.

## Verified on review commit

Commit: `7a05cdd3114225e38999c30ce8fc453c30c9d026`

- PR Syntax Checks (push): run [40172763274](https://github.com/sschoudharyshubhammundhar-stack/ShubhMart/actions/runs/40172763274) — completed successfully.
- PR Syntax Checks (pull_request): run [40172765869](https://github.com/sschoudharyshubhammundhar-stack/ShubhMart/actions/runs/40172765869) — completed successfully.
  - JavaScript syntax validation: success.
  - Checkout security regression tests (`node --test tests/*.test.js`): success.
- Secret Scan (push): run [40172763295](https://github.com/sschoudharyshubhammundhar-stack/ShubhMart/actions/runs/40172763295) — completed successfully.
- Secret Scan (pull_request): run [40172765829](https://github.com/sschoudharyshubhammundhar-stack/ShubhMart/actions/runs/40172765829) — completed successfully.
- The repository commit status also reported a Netlify Deploy Preview for this commit. That preview is not a production deployment and is not checkout/database integration proof.

## Scope and limitations

These results establish that the configured source/static regression tests and configured secret scan passed for the reviewed commit. They do NOT prove:
- SQL candidate compiles or behaves correctly against the exact Supabase schema;
- RLS, grants, triggers or SECURITY DEFINER functions are correctly configured in the live database;
- stock, ShubhCoins, order and payment changes are atomic under real PostgreSQL concurrency;
- Razorpay payment entity verification and webhook/retry handling work end-to-end;
- GitHub branch protection or production environment approval rules are configured;
- the live Supabase Edge Functions or Cloudflare Worker match this branch's candidate source.

## Next safe validation

1. Obtain an isolated, disposable Supabase/PostgreSQL test environment with synthetic data.
2. Capture its schema, function definitions, triggers, indexes and grants read-only before applying any candidate there.
3. Run candidate SQL and concurrency/idempotency/rollback tests in that isolated environment only.
4. Use Razorpay test mode or provider mocks; never use live payments as a test.
5. Review branch protection and deployment environment settings separately. The GitHub API call for branch protection returned 403 (permission unavailable), so this is UNVERIFIED, not evidence that protection is absent.
6. Keep production deployment, live SQL, merges and payment activation blocked until explicit approval and evidence-backed sign-off.

No production database writes, deployments, secret reads, branch protection changes, or PR merges were performed to produce this record.
