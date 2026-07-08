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
  - Next action: monitor replacement worker startup, then record its assigned thread/worktree once available.

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
