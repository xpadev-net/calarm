# Plan: Wake Alarm MVP Wave 9 - Calendar Rendering and Settings Defaults

- status: in progress
- generated: 2026-07-05
- last_updated: 2026-07-07
- work_type: code

## Goal

- WakePlanブロック描画と新規作成デフォルト設定を実装し、作成フローのUI入力基盤を整える。

## Definition of Done

- WakePlanが`targetAt - startOffset`から`targetAt`までのブロックとして表示できる。
- 設定画面で新規作成時のデフォルト値を変更できる。

## Scope / Non-goals

- Scope:
  - `lib/features/week_calendar/**`
  - `test/features/week_calendar/**`
  - `lib/features/settings/**`
  - `lib/features/wake_plan/domain/**`
  - `lib/features/wake_plan/data/**`
  - `test/features/settings/**`
- Non-goals:
  - 作成BottomSheet完成。
  - 編集/削除flow。

## Context (workspace)

- Related files/areas:
  - Wave 8 week calendar core and repository.
- Existing patterns or references:
  - `requirements.md` の画面要件9.1、9.5。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: ブロックの重なり表示はMVPで警告のみか、視覚的に横並びまで行うか。
- Q2: 設定変更の即時保存か、保存ボタン式か。
- Q3: MVP後に独自音源を追加する場合のasset/native連携方針。

## Assumptions

- A1: MVPでは細かいOccurrence時刻を全件表示せず、時間帯・間隔・回数を表示する。
- A2: 初期値は60分前、5分間隔、繰り返しなし、バイブON、デフォルト音。
- A3: MVPのアラーム音はOS/defaultのみとし、独自音源はMVP外にする。

## Tasks

### Task_1: Wake Plan Block Rendering
- type: impl
- owns:
  - lib/features/week_calendar/**
  - test/features/week_calendar/**
- depends_on: []
- description: |
  Original Task_16. Wake Planを `targetAt - startOffset` から `targetAt` までのブロックとして週カレンダー上に描画する。
- acceptance:
  - ブロックに起床目標時刻、時間帯、間隔、合計回数を表示できる。
  - 起床目標時刻側が視覚的に分かる。
  - 日跨ぎブロックを表示できる。
  - 複数Wake Planの重なりを最低限読めるように表示できる。
  - ブロックタップから詳細表示へ遷移できるイベントがある。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/week_calendar"
  - kind: e2e
    required: true
    owner: reviewer
    detail: "E2E / Visual Validation SpecのWake Planブロック表示を確認する"

### Task_2: Settings Defaults
- type: impl
- owns:
  - lib/features/settings/**
  - lib/features/wake_plan/domain/**
  - lib/features/wake_plan/data/**
  - test/features/settings/**
- depends_on: []
- description: |
  Original Task_21. 新規作成時のデフォルト値を設定画面から変更できるようにする。
- acceptance:
  - デフォルト起床ウィンドウ、間隔、OS/default音、バイブ、曜日繰り返し初期値を変更できる。
  - 設定変更後の作成シートに新しいデフォルトが反映される。
  - 初期値は60分前、5分間隔、繰り返しなし、バイブON、デフォルト音。
  - 最小間隔や最大ウィンドウなどの制約をUIで守る。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/settings test/features/wake_plan"
  - kind: e2e
    required: true
    owner: reviewer
    detail: "E2E / Visual Validation Specのデフォルト設定反映を確認する"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1, Task_2]

## E2E / Visual Validation Spec

- provider: playwright-cli for Flutter web smoke where applicable.
- artifact_root: `.playwright-cli/`
- flows:
  - Render week calendar with one WakePlan block.
  - Verify block label, time span, target side emphasis, overlap readability.
  - Change settings defaults and verify subsequent create flow receives new defaults when Wave 10 exists.
- viewports:
  - Mobile compact: 390x844.
  - Mobile large: 430x932.
- evidence_requirements:
  - Screenshots of block rendering and settings defaults.

## Rollback / Safety

- Settings defaults must preserve valid values; invalid stored values should fall back safely.

## Handoff To Next Wave

- Wave 10 uses block rendering events and settings defaults for create sheet.

## Progress Log (append-only)

- 2026-07-07 Wave 9 delegated to Codex thread workers.
  - Task_1 Wake Plan Block Rendering pending worktree: `local:9ee43d45-6a5b-4682-8952-c23a2288de48`; branch `codex/wave-09-block-rendering`.
  - Task_2 Settings Defaults pending worktree: `local:8ea7ab6d-16b3-4fde-b902-5270b3138322`; branch `codex/wave-09-settings-defaults`.
  - Correction: earlier multi-agent subagent workers were stopped before completion because the user requires task workers to run as Codex threads/worktrees, not subagents.
  - Validation gate: each worker must return a merge-ready PR with required tests, analyzer, diff check, self-review, independent review, and `rtk gh-review-hook <PR>` exit 0 before orchestrator review/merge.
  - Note: Wave 9 settings defaults expose create-flow consumption for Wave 10; full create sheet reflection is gated in Wave 10.
- 2026-07-07 Task_1 PR #19 parent merge gate returned to worker for revision.
  - Parent validation: `rtk flutter test test/features/week_calendar`, `rtk flutter analyze`, and `rtk git diff --check` passed in the Task_1 worktree.
  - Blocker: compact mobile overlap review found `_WakePlanBlock` minimum-width clamping can exceed lane/day bounds with 3+ simultaneous overlapping Wake Plans, violating the overlap-readability acceptance.
  - Status: worker thread `019f3c69-4922-7da2-a08a-c36f5b60a68e` resumed with a narrow fix request; PR #19 not merged.
- 2026-07-07 Task_1 PR #19 merged.
  - Merge commit: `bcb6cbf2198c7bdfab0451f694df10cdaa0b69fd`.
  - Worker head: `3e18d0e0ca4894255cf14b5251eec2d03db7d204`; worker thread `019f3c69-4922-7da2-a08a-c36f5b60a68e` archived after merge.
  - Worker fix: compact WakePlan block widths are lane-bounded and covered by a 390x844 three-overlap widget regression.
  - Orchestrator gate: inspected PR metadata/diff/current head, ran deep-review common/UI/tests pass with no blocker found, ran `rtk gh-review-hook 19` exit 0, and reran `rtk flutter test test/features/week_calendar`, `rtk flutter analyze`, and `rtk git diff --check` in the Task_1 worktree.
  - E2E/visual note: no seeded runnable week-calendar route/harness was available for browser screenshots; compact geometry is covered by widget assertions. Runtime device validation remains outside Wave 9.
- 2026-07-07 Task_2 worker thread `019f3c69-81a4-7a72-bed9-6c2fbb67d5c2` remains active on PR #20 follow-up.
  - Current state observed: worker fixed `gh-review-hook` findings, branch is ahead locally, and final validation/push/hook loop is still in progress.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Pair rendering and defaults before create flow.
  - Trigger / new insight: Create flow needs both visual output and default input values.
  - Plan delta (what changed): Wave 9 prepares UI substrate before Wave 10.
  - Tradeoffs considered: Settings could be later, but early implementation prevents hard-coded defaults in create flow.
  - User approval: pending.

- 2026-07-05 Decision: Keep MVP alarm sound to OS/default only.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 9 now treats custom alarm sounds as out of MVP scope and keeps settings on OS/default sound.
  - Tradeoffs considered: Custom sounds add native asset and review complexity; default sound keeps the MVP focused on scheduling reliability.
  - User approval: yes.

## Notes

- Risks:
  - Dense block labels may overflow on compact mobile width.
