# ShubhMart CI/CD and Supply-Chain Security

Status: review checklist. Current workflow and repository settings must be inspected; this file does not assert they are already secure.

## GitHub Actions
- Set workflow and job permissions to the minimum required; default to read-only where possible.
- Pin third-party actions to reviewed full commit SHAs where practicable; review updates and transitive dependencies.
- Do not expose secrets to untrusted fork pull requests or execute untrusted PR code in privileged workflows.
- Avoid `pull_request_target` checkout/execution patterns that run attacker-controlled code with write permissions or secrets.
- Protect artifacts and logs; do not print secrets or dump complete environments.
- Use lockfiles and deterministic package-manager commands; review install scripts and dependency changes.
- Run lint, tests, typecheck, build, secret scan, dependency audit, and security regression tests on the exact PR head.
- Record commit SHA, workflow run, job results, artifact provenance, and preview URL.

## Preview and production separation
- Preview must use isolated credentials/data and must not point at production mutation endpoints by default.
- Production deploy must be restricted to approved branch, reviewed commit, successful required checks, and explicit environment approval where supported.
- Verify branch protection/rulesets and deployment permissions through actual repository settings. If permission is denied, record UNVERIFIED.
- Keep preview and production secrets separate; never use production service-role credentials in previews or CI tests.
- Verify rollback target and whether deployment changes database compatibility before release.

## Cloudflare
- Review Wrangler config, routes, assets binding, environment-specific variables/secrets, preview behavior, build outputs, and deployment triggers.
- Confirm the preview URL corresponds to the exact reviewed commit and is not treated as production.
- Restrict who can deploy and rotate exposed credentials through the provider if compromise is suspected.
- Review response headers, caching rules, redirects, CORS, and accidental static publication of `.env`, SQL dumps, test data, or repository metadata.

## Required evidence
Exact workflow files and commit SHA, permission block, trigger analysis, action pinning review, secret/dependency scan results, branch protection/ruleset evidence, environment approvals, preview/prod credential separation, and rollback test. Do not mark PASS from a green build alone.