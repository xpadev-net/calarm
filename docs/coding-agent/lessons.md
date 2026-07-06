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

### 2026-07-06 - Orchestrator Must Review Before Merge
- tags: workflow/process, review, validation
- symptom: A worker PR merge was handled primarily from worker report, checks, hook evidence, and metadata inspection without explicitly calling out an orchestrator-owned review pass that could produce findings and return the PR to the worker.
- root cause: The merge gate evidence checklist was treated as sufficient unless checks failed, while the user expects the orchestrator to perform an active final review before merge and block on any in-scope findings.
- fix: Before merging any worker PR, perform and record an orchestrator-owned review of the PR diff against task acceptance, ownership boundaries, validation evidence, and runtime/deferred-risk wording.
- prevention: Merge checklist now includes an explicit "orchestrator review findings" decision: if findings exist, do not merge; send concrete follow-up to the worker and wait for a new head SHA, refreshed validation, and hook evidence.
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
