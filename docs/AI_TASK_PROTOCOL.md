# AI Task Protocol — ShubhMart

This protocol exists to reduce repeated instructions, repeated work, regressions, and false completion claims. It applies to ChatGPT, coding agents, human contributors, and future sessions.

## 1. Start every task from the real state
1. Read `AGENTS.md`, `MEMORY.md`, `RULES.md`, this file, and relevant security docs.
2. Inspect the current branch, HEAD, worktree/diff, open PR and latest checks. Do not assume an earlier conversation or memory describes the current repository state.
3. Read the actual implementation and tests before changing anything. Search for related code and prior fixes first.
4. Identify the user goal, acceptance criteria, affected paths, risks, approval boundary, and how success will be verified.
5. If essential information is missing, ask one focused question. Otherwise proceed with a safe read-only investigation rather than repeatedly asking for information already in the repo.

## 2. One task at a time
- Break broad requests into small, ordered tasks. State the current task and what is deliberately out of scope.
- Finish the current task end-to-end where safely possible: inspect → change → test → review diff → document → report.
- Do not silently expand scope, rewrite unrelated files, duplicate an existing feature, or redo a verified step without a reason.
- If blocked, explain the exact blocker and continue only with independent safe work. Never disguise a blocker as completion.
- Before retrying a failed operation, inspect its result and current state to avoid duplicate commits, requests, orders, or other side effects.

## 3. Preserve work and prevent regressions
- Prefer the smallest reversible change. Keep existing functionality and design unless the user explicitly asks to change it.
- Check the current diff before editing; do not overwrite uninspected work. Never reset, force-push, delete, or discard another contributor's changes without explicit approval.
- Add or update a focused regression test for every bug/security fix where feasible.
- Use isolated environments and synthetic data. Never use production as a test environment.
- Run the relevant tests and checks on the exact resulting commit when tools permit. If unavailable, say so and label the result UNVERIFIED/BLOCKED.
- A successful build is not proof of correct business logic, runtime security, payment integrity, or production deployment.

## 4. Approval gate — stop before consequential actions
Explicit user approval is required for production DB writes/SQL/migrations; schema, RLS, grants, policies, triggers, RPC or Edge Function changes/deployments; real payments, OTP or credit activation; production deploy/routing; PR merge/close; paid resources/billing; destructive operations; or changes to external accounts/services. Explain the exact change, target, impact, and rollback before asking. Silence or a broad goal is not approval for a specific high-impact action.

## 5. Keep one source of truth
- Canonical rules: `AGENTS.md` + `RULES.md`; durable project facts: `MEMORY.md`; security evidence: `docs/security/FINDINGS_REGISTER.md` and dated audit snapshots; process: this file.
- Before creating a new document, search for an existing source of truth. Update the existing document instead of making competing copies.
- Update docs/index/changelog when the change warrants it. Keep historical observations dated and label them as historical until revalidated.
- Never store secrets, tokens, private customer data, payment credentials, or raw sensitive logs.
- Do not treat chat history, an AI summary, or old test output as evidence of the current state.

## 6. Status must be evidence-based
Use:
- **PASS** — the stated check ran successfully on the named commit/environment and evidence was observed.
- **FAIL** — the check ran and failed.
- **BLOCKED** — a permission, dependency, unavailable service, or safety boundary prevented the check/action.
- **MISSING** — a required control/artifact/test is absent.
- **UNVERIFIED** — evidence is insufficient or the check was not run.
- **REVIEW** — investigation is ongoing.

For each result, record the command/check, commit or environment, observed outcome, and limitation. Do not claim live configuration, deployment, security, or fix status from source code alone.

## 7. Required task handoff
At the end of a task, provide a compact handoff that another AI or future session can continue without asking the user to repeat themselves:
- Goal and scope completed.
- Branch and exact HEAD/commit; PR link/status if relevant.
- Files changed and why.
- Checks actually run and their results.
- Status labels with evidence.
- Known blockers, risks, and what was not checked.
- Approval needed, if any.
- One recommended next step.
- If work is unfinished, update the relevant task/handoff record in the repository; do not claim that chat alone is persistent project state.

## 8. Final checklist
- [ ] Current state inspected; no assumptions from stale memory
- [ ] Scope and approval boundary respected
- [ ] Existing behavior preserved; diff reviewed
- [ ] Relevant tests/checks run or explicitly marked BLOCKED/UNVERIFIED
- [ ] Documentation/findings updated where needed
- [ ] Exact commit and next step included in handoff
