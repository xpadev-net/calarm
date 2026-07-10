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

### 2026-07-08 - Treat Debug Leads As Hypotheses

- tags: validation/verification, assumptions/interpretation, ci, delegation
- symptom: A follow-up task for a Baseline CI failure was initially worded as a timezone/date-assumption investigation after the user suggested timezone was worth checking.
- root cause: The orchestration prompt turned a plausible debugging lead into overly narrow framing before evidence established the root cause.
- fix: Reword the active plan and automation so timezone/current-date behavior is only one candidate cause alongside repeat/skip logic, clock seeding, CI environment, and calendar-date conversion.
- prevention: When a user suggests a possible root cause for a failing check, preserve it as a hypothesis unless they explicitly say it is the confirmed cause; worker prompts should require evidence before narrowing the fix.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-08 - Launch Implementation Workers With Requested Model

- tags: delegation, workflow/process, assumptions/interpretation
- symptom: A retry implementation worker was launched without explicitly setting the user's requested model/reasoning defaults.
- root cause: The orchestration retry focused on recovering from repeated worker startup failures and reused default thread settings instead of carrying forward the user preference for implementation-worker model selection.
- fix: Treat implementation-worker creation and implementation-bearing follow-up prompts as requiring `gpt-5.5` with medium reasoning unless the user says otherwise.
- prevention: Before creating or steering a Codex thread/worktree worker that may implement product code, check the active plan/user preferences for model/reasoning and pass them explicitly to `create_thread` or `send_message_to_thread`.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-07 - Use Codex Threads for Plan Workers

- tags: delegation, workflow/process, scope-owns
- symptom: Parent-plan execution delegated Wave 9 implementation to multi-agent subagents, but the user required workers to run as Codex threads instead.
- root cause: The orchestration request said worker, and the runtime had subagent tooling available, so delegation defaulted to subagents instead of preserving the task-pr-orchestrator thread/worktree model.
- fix: Shut down the subagents and switch future parent-plan implementation delegation to Codex thread/worktree workers.
- prevention: For this repository's parent implementation plan, treat "worker" as a Codex thread/worktree worker by default; use multi-agent subagents only for bounded review/research sidecars when explicitly requested or when they do not replace task workers.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

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

### 2026-07-06 - Run Worker Hook After Review

- tags: workflow/process, review, validation
- symptom: Worker instructions could be read as allowing `gh-review-hook` evidence before final worker self-review or independent review completion.
- root cause: The PR lifecycle required hook exit 0, but did not always spell out the ordering that review fixes must be complete before the worker worktree reruns the hook.
- fix: Make worker validation require a final `rtk gh-review-hook <PR_NUMBER>` run from the worker worktree after self-review, independent review, and any review-driven fixes are complete.
- prevention: For merge-ready worker reports, require the reported hook evidence to be from the final reviewed head SHA; if review findings produced follow-up commits, the worker must rerun the hook before handoff.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-08 - Prove Acceptance Before No-Diff Stop

- tags: validation/verification, assumptions/interpretation, workflow/process
- symptom: A worker stopped with a no-diff conclusion even though Task_3 user-facing settings health checks and test-alarm UI were not implemented on `master`.
- root cause: Existing platform contract and QA checklist rows were mistaken for full acceptance coverage without re-reading the concrete UI path and proving each acceptance item in the running app surface.
- fix: Resume the task, inspect the settings presentation path, and implement missing user-facing health warnings and test-alarm flow.
- prevention: Before ending a delegated implementation task as already satisfied, map every acceptance bullet to concrete files/tests/UI behavior; absence of that proof means continue investigation instead of stopping.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-08 - Keep Follow-Up Refresh Failures Separate

- tags: review, validation, state-transitions
- symptom: Merge-gate review found a settings test-alarm success could be overwritten as a native scheduling failure when the follow-up capability refresh threw.
- root cause: The controller wrapped the scheduling side effect and a non-authoritative refresh in the same `try` block, so a later read failure changed the meaning of an already-created native alarm.
- fix: Make the native scheduling result authoritative, catch capability refresh failures separately, and retain the previous capability when refresh fails.
- prevention: For native side effects followed by status refreshes, tests must cover "side effect succeeds, refresh fails" and assert the user-visible result still reflects the side effect.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-08 - Disable Overlapping Health Actions

- tags: review, validation, state-transitions, ui
- symptom: Review found the settings "Check again" action stayed enabled while a test alarm was being scheduled, allowing overlapping refreshes to write stale alarm-health state.
- root cause: The UI only checked Riverpod loading state and did not model controller-level in-flight actions as one shared busy state.
- fix: Add explicit busy flags for refresh, permission, and test-alarm scheduling; disable readiness actions while any health action is in flight; preserve the latest controller state when async operations complete.
- prevention: For controller actions that share state, tests and UI review must verify overlapping action paths cannot overwrite newer user-visible results.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-08 - Return Non-Merge-Ready PRs To Workers

- tags: workflow/process, validation/verification, delegation, review
- symptom: The orchestrator held PR #26 at a user-decision point after determining it was not merge-ready because parent-owned `gh-review-hook` had not exited 0.
- root cause: A missing merge-gate artifact was treated as an external exception decision before first returning the non-merge-ready state to the owning worker for another bounded attempt or a precise blocker report.
- fix: Send the PR back to the owning Codex thread/worktree worker with concrete missing evidence and require either a refreshed merge-ready report or an exact blocker; keep parent-thread product code untouched.
- prevention: Before asking the user to approve a hook/validation exception, check whether an active owning worker can still address or precisely classify the missing merge-readiness evidence. If yes, send it back to the worker instead of pausing on user decision.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-10 - Prove Worker Liveness Beyond TUI Animation

- tags: workflow/process, validation/verification, delegation, tooling/environment
- symptom: The orchestrator reported two resumed workers as active after observing only the Codex TUI `Working` animation; both worker turns later stopped, and one completed report was not consumed.
- root cause: A transient terminal-rendering signal and surviving wrapper process were treated as authoritative worker liveness instead of checking new thread events, repository/PR progress, and a completed worker report.
- fix: Reconcile each worker from session event logs and current PR state, merge Task_1 from its completed report, and restart only workers that genuinely require more work.
- prevention: Before reporting a worker as active, require at least one post-resume durable signal: a new session event describing concrete work, a new branch/PR head, a running validation command, or an explicit active status from the thread API. TUI animation and process existence alone never prove progress; completion reports must be consumed before attempting another resume.
- promotion: Harness migration candidate concept: add a durable-liveness evidence gate to worker startup stability checks; staged as a repo-local lesson because this task does not authorize bundled harness edits.

### 2026-07-10 - Consume Worker Completion Before Ending Orchestration Turn

- tags: workflow/process, validation/verification, delegation
- symptom: After adding a durable startup-liveness check, the orchestrator still ended the turn while both workers later produced merge-ready completion reports that were not consumed until the user reported them stopped again.
- root cause: Startup stability was treated as sufficient closeout evidence; there was no turn-closing reconciliation of new `task_complete` events and PR heads before reporting workers as merely active.
- fix: Read both worker histories, consume their merge-ready reports, run orchestrator gates, merge PRs #40 and #39, and archive both sessions in the same turn.
- prevention: Before ending an orchestration turn that launched or resumed short bounded workers, perform one completion reconciliation after the expected validation window; if a worker has completed, process its report rather than describing it as active. For longer work, require a heartbeat/automation instead of relying on an orphaned TUI process.
- promotion: Staged as `HMC-20260710-orchestration-worker-completion-reconciliation` in `docs/coding-agent/skill-candidates.md` because the failure repeated and generalizes across repositories.
