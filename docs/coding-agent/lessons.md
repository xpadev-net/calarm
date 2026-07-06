# Lessons Log (Coding Agent)

Purpose:
- capture recurring mistakes and the prevention mechanism
- enable "read once, don't repeat" improvements

## How to use
- Append a new entry after any user correction or significant miss.
- Keep entries short and actionable.
- Promote repeated/high-severity lessons into repo rules, harness migration candidates, troubleshooting notes, or accepted residual-risk records.

## Tags (recommended)
- planning
- validation
- delegation
- review
- ui-e2e
- tooling
- ci
- scope-owns

## Entries

### 2026-07-06 - Create Missing Owned Paths
- tags: workflow/process, scope-owns, assumptions/interpretation
- symptom: A worker stopped as blocked because delegated owned files did not exist on the base branch.
- root cause: The task ownership contract was interpreted as requiring preexisting files instead of allowing new file creation inside owned paths.
- fix: Continue implementation by creating the missing service and test files under the delegated owned paths.
- prevention: Before reporting blocked on a missing path, check whether the active task owns that path and whether the requested implementation naturally includes creating it; only block if creation would exceed ownership or a required dependency is missing.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Keep Failed Native Alarm IDs Discoverable
- tags: review, validation, state-transitions
- symptom: Review found that failed schedule/cancel paths could persist platform-backed occurrences as terminal failures, making native alarm IDs invisible to later retry cancellation queries.
- root cause: Failure status was treated as a terminal app state even when a native platform alarm identity still existed and needed lifecycle cleanup.
- fix: Keep platform-backed failed schedule/cancel rows in cancellable scheduled/ringing states, avoid soft delete on cancel failure, and add regression tests for retry-discoverability.
- prevention: In native alarm lifecycle work, any persisted `platformAlarmId` must remain reachable by the repository path used for future cancellation until the service has observed a successful cancel.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Orchestrator Must Review Before Merge
- tags: workflow/process, review, validation
- symptom: A worker PR merge was handled primarily from worker report, checks, hook evidence, and metadata inspection without explicitly calling out an orchestrator-owned review pass that could produce findings and return the PR to the worker.
- root cause: The merge gate evidence checklist was treated as sufficient unless checks failed, while the user expects the orchestrator to perform an active final review before merge and block on any in-scope findings.
- fix: Before merging any worker PR, perform and record an orchestrator-owned review of the PR diff against task acceptance, ownership boundaries, validation evidence, and runtime/deferred-risk wording.
- prevention: Merge checklist now includes an explicit "orchestrator review findings" decision: if findings exist, do not merge; send concrete follow-up to the worker and wait for a new head SHA, refreshed validation, and hook evidence.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Close Completed Wave Plans and Review Wave Codebase
- tags: workflow/process, planning, review, validation
- symptom: Completed wave plan files remained under `docs/coding-agent/plans/active/`, and Wave 8 lacked an explicit whole-codebase review-and-fix closeout after the scheduling/native/calendar implementation wave.
- root cause: Wave merge bookkeeping focused on task PR state and ledger evidence, but plan lifecycle movement and wave-level integrated review were not encoded as mandatory closeout steps.
- fix: Move completed wave plans to `docs/coding-agent/plans/completed/`, update parent links, and add a Wave 8 whole-codebase review/fix loop after implementation and native smoke tasks.
- prevention: Before declaring a wave complete, verify its plan file has moved out of `active/`; for Wave 8 and similar integration-heavy waves, require an orchestrator/reviewer codebase-wide review loop with follow-up fixes until no in-scope findings remain.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Push Orchestrator Ledger Commits Promptly
- tags: workflow/process, delegation
- symptom: Orchestrator ledger updates were committed locally, but the operating default did not explicitly require prompt push after local commits.
- root cause: The task-pr orchestration loop records ledger evidence, but local commit/push hygiene for parent-thread ledger-only changes was not encoded as a durable habit.
- fix: Treat orchestrator-owned ledger diffs as commit-and-push work whenever the user asks for persistent parent-thread bookkeeping.
- prevention: Before ending an orchestrator turn with committed ledger changes, check `git status --short --branch`; if the branch is ahead and there is no active reason to hold the commit locally, push it and report the commit/push state.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Add Baseline CI Before Specialized CI
- tags: ci, validation, planning
- symptom: Near-device simulator/emulator CI planning existed before ordinary PR CI was explicitly planned.
- root cause: The plan focused on deferred native runtime risk and did not separately encode baseline formatting, analyzer/lint, and unit-test automation.
- fix: Added a Wave 7 baseline GitHub Actions CI task and release-readiness checks, while keeping Wave 8 native smoke CI separate.
- prevention: When adding specialized CI, first confirm whether ordinary baseline CI exists and add or preserve format, lint/analyzer, and unit-test checks as an independent validation path.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.
