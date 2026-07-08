# Plan: Wake Alarm MVP Wave 13 - UI Harmonization and Accessibility

- status: in_progress
- generated: 2026-07-05
- last_updated: 2026-07-08
- work_type: review

## Goal

- MVP UI全体の文言、導線、レイアウト、禁止操作の不在、アクセシビリティを横断確認し、リリース前のUI品質を揃える。

## Definition of Done

- 作成、詳細、編集、削除、スキップ、設定、鳴動の文言が一貫している。
- 鳴動画面に禁止導線がない。
- モバイル幅でテキストがボタンやカードからはみ出さない。
- UIレビュー結果が`docs/qa/ui-review.md`に記録されている。

## Scope / Non-goals

- Scope:
  - `lib/features/week_calendar/**`
  - `lib/features/wake_plan/ui/**`
  - `lib/features/alarm_ringing/**`
  - `lib/features/settings/**`
  - `docs/qa/ui-review.md`
- Non-goals:
  - 新機能追加。
  - 大規模デザインリブランド。

## Context (workspace)

- Related files/areas:
  - Wave 10 create flow.
  - Wave 11 edit/ringing/health.
  - Wave 12 repeat/skip.
- Existing patterns or references:
  - `requirements.md` の誤操作防止と画面要件。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: Accessibility minimumとしてsemantic labelsまで必須にするか。
- Q2: Tablet viewportをMVP必須にするか、advisoryにするか。
- Q3: 日本語文言の敬体/常体や用語表記をどこまで統一するか。

## Assumptions

- A1: MVP UIはモバイルfirstで検証する。
- A2: 禁止導線の不在はvisual/e2eだけでなくコードレビューでも確認する。
- A3: MVP UI文言は日本語固定で開始する。

## Tasks

### Task_1: UI Harmonization and Accessibility Pass
- type: review
- owns:
  - lib/features/week_calendar/**
  - lib/features/wake_plan/ui/**
  - lib/features/alarm_ringing/**
  - lib/features/settings/**
  - docs/qa/ui-review.md
- depends_on: []
- description: |
  Original Task_23. MVP UI全体の文言、導線、レイアウト、禁止操作の不在、アクセシビリティを横断確認する。
- acceptance:
  - 作成、詳細、編集、削除、スキップ、設定、鳴動の文言が一貫している。
  - 鳴動画面に禁止導線がない。
  - モバイル幅でテキストがボタンやカードからはみ出さない。
  - 重要操作には確認または明確な導線がある。
  - UIレビュー結果がdocs/qa/ui-review.mdに記録されている。
- validation:
  - kind: e2e
    required: true
    owner: reviewer
    detail: "E2E / Visual Validation Specの全UI主要画面をモバイル幅で確認する"
  - kind: review
    required: true
    owner: reviewer
    detail: "UI文言、禁止導線、アクセシビリティ、レスポンシブ崩れをレビューする"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]

## E2E / Visual Validation Spec

- provider: playwright-cli for Flutter web smoke where applicable; native screenshots for alarm UI if required.
- artifact_root:
  - `.playwright-cli/`
  - `docs/qa/artifacts/`
- flows:
  - Week calendar empty and populated states.
  - Create, detail, edit, delete, repeat, skip, settings, health warning, alarm ringing.
  - Verify no "起きた", "残り全部停止", "スヌーズ" equivalent appears in ringing UI.
- viewports:
  - Mobile compact: 390x844.
  - Mobile large: 430x932.
  - Tablet: 768x1024 if supported.
- evidence_requirements:
  - Screenshot set and `docs/qa/ui-review.md` findings table.

## Rollback / Safety

- UI polish must not weaken scheduling/cancel semantics.
- If copy changes affect tests, update tests in the same task.

## Handoff To Next Wave

- Wave 14 uses `docs/qa/ui-review.md` as final QA input.

## Progress Log (append-only)

- 2026-07-08 Wave 13 Task_1 UI Harmonization and Accessibility delegated.
  - Task_1 worker thread: `019f3e25-dea8-7630-807f-affd93553d9a`; pending worktree `local:b6c002f7-75e2-48d4-a401-f664e95d7e86`; worktree `/Users/xpadev/.codex/worktrees/ff55/calarm`; branch `codex/wave-13-ui-harmonization`.
  - Worker type: Codex thread/worktree, not multi-agent subagent.
  - Startup note: initial turn hit `systemError` before producing work; orchestrator sent a resume instruction to continue from the current worktree/branch and report before any future stop.
  - Merge gate: worker must provide UI review evidence in `docs/qa/ui-review.md`, feasible visual/E2E evidence or exact blocker evidence, targeted tests for any UI changes, analyzer/diff checks, deep-review self-review, independent review, and `rtk gh-review-hook <PR>` exit 0 before orchestrator review/merge.

- 2026-07-08 Wave 13 initial worker stopped and replacement queued.
  - Stopped worker: thread `019f3e25-dea8-7630-807f-affd93553d9a`; pending worktree `local:b6c002f7-75e2-48d4-a401-f664e95d7e86`; worktree `/Users/xpadev/.codex/worktrees/ff55/calarm`; branch `codex/wave-13-ui-harmonization`.
  - Reason: initial turn hit `systemError`, and a resume instruction also completed without worker output while thread status remained `systemError`; orchestrator archived the stopped thread.
  - Replacement worker pending worktree: `local:8b181244-c3f8-41e1-a893-38d042926f31`; branch `codex/wave-13-ui-harmonization-2`.
  - Worker type: Codex thread/worktree, not multi-agent subagent.
  - Next action: monitor replacement worker startup, then record its assigned thread/worktree once available.

- 2026-07-08 Wave 13 replacement worker assigned but stopped at startup.
  - Replacement worker thread: `019f3e28-0eb3-7583-a813-d6c70f95aa47`; pending worktree `local:8b181244-c3f8-41e1-a893-38d042926f31`; worktree `/Users/xpadev/.codex/worktrees/8237/calarm`; branch `codex/wave-13-ui-harmonization-2`.
  - Worker type: Codex thread/worktree, not multi-agent subagent.
  - Startup note: initial turn completed without worker output and thread status is `systemError`; orchestrator sent a resume instruction to continue from the current worktree/branch and report before any future stop.
  - Resume result: resume instruction also completed without worker output while thread status remained `systemError`; orchestrator archived the stopped replacement.

- 2026-07-08 Wave 13 second replacement queued.
  - Replacement worker pending worktree: `local:5ca92c33-2b7a-4ef7-8b11-17ae795e3ce0`; branch `codex/wave-13-ui-harmonization-3`.
  - Worker type: Codex thread/worktree, not multi-agent subagent.
  - Assigned worker thread: `019f3e2d-53c7-7b63-aa30-5920147b9772`; worktree `/Users/xpadev/.codex/worktrees/2045/calarm`.
  - Startup note: initial turn completed without worker output and thread status is `systemError`; orchestrator sent a resume instruction to continue from the current worktree/branch and report before any future stop.
  - Resume result: resume instruction also completed without worker output while thread status remained `systemError`; orchestrator archived the stopped second replacement.

- 2026-07-08 Wave 13 third replacement queued.
  - Replacement worker pending worktree: `local:74dd1674-c985-4ce5-ab0e-01b721647e18`; branch `codex/wave-13-ui-harmonization-4`.
  - Worker type: Codex thread/worktree, not multi-agent subagent.
  - Startup note: created with a plain prompt rather than a delegation wrapper after repeated pre-output `systemError` failures.
  - Assigned worker thread: `019f3e2f-d144-74a0-8ac8-d6bde8e7f190`; worktree `/Users/xpadev/.codex/worktrees/1607/calarm`.
  - Startup note: initial turn completed without worker output and thread status is `systemError`; orchestrator sent a resume instruction to continue from the current worktree/branch and report before any future stop.
  - Resume result: resume instruction also completed without worker output while thread status remained `systemError`; orchestrator archived the stopped third replacement.
  - Current blocker: Wave 13 Task_1 cannot currently be advanced through Codex thread/worktree workers because four consecutive Wave 13 worker attempts reached `systemError` before any task execution output.
  - Next action: ask for an external decision on whether to retry later, use a different worker setup/model, or allow a different execution path for Wave 13.

- 2026-07-08 Wave 13 retry requested by user and queued.
  - User decision: retry Codex thread/worktree worker startup after the repeated pre-output `systemError` blocker.
  - Replacement worker pending worktree: `local:7877c74a-708b-4753-b7d1-b679f6c455bd`; branch `codex/wave-13-ui-harmonization-5`.
  - Worker type: Codex thread/worktree, not multi-agent subagent.
  - Assigned worker thread: `019f3f71-8e64-7443-bdd1-99682338df0f`; worktree `/Users/xpadev/.codex/worktrees/6a83/calarm`.
  - Worker status: recovered from prior startup failures and produced a focused UI consistency diff, but stopped before merge-ready because `flutter`, `fvm`, `gh`, and `gh-review-hook` are unavailable in the worker environment. Worker-reported feasible validation: `git diff --check` passed.
  - Current branch diff reported by worker: `lib/features/wake_plan/ui/wake_plan_detail_sheet.dart`, `test/features/wake_plan/ui/wake_plan_detail_sheet_test.dart`, and new `docs/qa/ui-review.md`.
  - User correction: future implementation worker starts and implementation-bearing follow-ups must use `gpt-5.5` with medium reasoning unless the user says otherwise.
  - Branch state: worker committed and pushed `bad462bba3bcd6cba00cebdaf7fcc936c550f017` (`Add Wave 13 UI review evidence`) to `origin/codex/wave-13-ui-harmonization-5`.
  - Files in pushed worker commit: `docs/qa/ui-review.md`, `lib/features/wake_plan/ui/wake_plan_detail_sheet.dart`, `test/features/wake_plan/ui/wake_plan_detail_sheet_test.dart`.
  - PR state: no PR opened by worker because `gh` is unavailable; GitHub PR creation URL reported as `https://github.com/xpadev-net/calarm/pull/new/codex/wave-13-ui-harmonization-5`.
  - Current blocker: Wave 13 cannot enter orchestrator merge gate in the current worker/parent environments because `flutter`, `fvm`, `gh`, and `gh-review-hook` are unavailable; targeted Flutter tests, `flutter analyze`, PR creation, independent review, and `gh-review-hook` remain incomplete. This is not merge-ready.
  - Next action: run the remaining validation/PR/review-hook steps from an environment with Flutter and GitHub tooling, or have the user provide/open the PR for orchestrator review in a tooling-enabled environment.

- 2026-07-08 Wave 13 branch worker reopened with requested model.
  - User decision: archived/stopped worker thread was closed by the user; reopen the Wave 13 branch worker with `gpt-5.5` and medium reasoning.
  - Replacement worker pending worktree: `local:4032c0dd-ec0c-4f77-8781-4528cb7788c7`; starting branch `codex/wave-13-ui-harmonization-5`; expected head `bad462bba3bcd6cba00cebdaf7fcc936c550f017`.
  - Worker type: Codex thread/worktree, not multi-agent subagent.
  - Assigned worker thread: `019f3fec-a705-75b2-8844-9fdaaf822952`; worktree `/Users/xpadev/.codex/worktrees/312f/calarm`.
  - Worker report: PR #26 opened at `https://github.com/xpadev-net/calarm/pull/26` on branch `codex/wave-13-ui-harmonization-5`; head `89062e68ceb1d15dbeac8cc045d644dfd310f444`; merge state `CLEAN`; review decision `APPROVED`; worker did not merge.
  - Worker validation evidence: `git diff --check origin/master...HEAD` passed; `git diff --check` passed; remote Baseline CI "Format, analyze, and test" passed at head `89062e68ceb1d15dbeac8cc045d644dfd310f444`; Socket Security checks passed; CodeRabbit status passed; Greptile Review check passed; worker `gh-review-hook 26` exited 0.
  - Worker blocker evidence: local Flutter validation remains blocked because `/Users/xpadev/fvm/versions/3.35.7/bin/flutter` uses Dart `3.9.2`, while `pubspec.yaml` requires Dart `^3.12.2`; E2E/visual validation is blocked by the absence of a runnable Flutter web/Playwright route/harness; real-device iOS 26+/Android API 36 runtime validation remains user-deferred/unapproved.
  - Orchestrator merge-gate inspection: PR metadata/diff inspected; changed files are `docs/qa/ui-review.md`, `lib/features/wake_plan/ui/wake_plan_detail_sheet.dart`, and `test/features/wake_plan/ui/wake_plan_detail_sheet_test.dart`; worker worktree is clean and tracking origin; local diff hygiene passed; orchestrator deep-review found no in-scope code findings.
  - Orchestrator hook result: first `gh-review-hook 26` attempt in the parent worktree was rejected by local uncommitted ledger changes; rerun in the clean worker worktree confirmed all CI/AI checks success but failed after waiting for Greptile PR description review with GitHub API 401; a second clean-worker rerun confirmed all CI/AI checks success and remained stuck for more than 10 minutes waiting for Greptile PR description review even though the Greptile check-run was already success, then was interrupted to avoid an indefinite wait.
  - Current status: blocked at orchestrator merge gate solely on parent-owned `gh-review-hook 26` exit-0 evidence. The PR itself is clean with green remote checks and worker hook success, but the explicit parent merge gate has not passed.
  - Next action: either rerun parent `gh-review-hook 26` after Greptile description review/API behavior recovers, or get an explicit user/orchestrator approval to merge PR #26 with a recorded hook exception based on green remote checks, worker hook success, and orchestrator deep-review.

- 2026-07-08 Wave 13 PR #26 parent hook retry still blocked.
  - Orchestrator retry: ran parent-owned `gh-review-hook 26` from clean worker worktree `/Users/xpadev/.codex/worktrees/312f/calarm`.
  - Current PR verification: head remained `89062e68ceb1d15dbeac8cc045d644dfd310f444`; merge state returned to `CLEAN`; remote Baseline CI, Greptile Review, Socket Security checks, and CodeRabbit remained successful.
  - Hook result: the retry again confirmed all CI/AI checks success but stayed in `[Greptile] waiting for PR description review update` for several minutes despite the Greptile check-run being success; orchestrator interrupted it to avoid an indefinite wait.
  - Current status: blocked pending external decision. Either wait and rerun the parent hook later, or approve a recorded hook exception for PR #26.

- 2026-07-08 Wave 13 PR #26 returned to worker after user correction.
  - User correction: if a PR is not merge-ready, return it to the owning worker instead of holding it at the parent for a merge exception decision.
  - Action: sent follow-up to worker thread `019f3fec-a705-75b2-8844-9fdaaf822952` with model `gpt-5.5` and medium reasoning.
  - Worker instruction: continue from branch `codex/wave-13-ui-harmonization-5` at head `89062e68ceb1d15dbeac8cc045d644dfd310f444`, resolve the missing merge-readiness evidence if possible, rerun `gh-review-hook 26`, and report either `merge_ready` with exact evidence or `blocked` with the single external decision needed. Do not claim merge-ready while required merge-gate evidence is missing.
  - Current status: waiting for worker follow-up.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Add a dedicated UI harmonization gate before final QA.
  - Trigger / new insight: Feature waves can produce inconsistent text and layout even when individually correct.
  - Plan delta (what changed): Wave 13 becomes the cross-feature UI review.
  - Tradeoffs considered: Adds one review step, but reduces final QA churn.
  - User approval: pending.

## Notes

- Risks:
  - Native AlarmKit UI may not be fully controllable from Flutter.
