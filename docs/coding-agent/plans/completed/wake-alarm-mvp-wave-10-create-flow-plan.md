# Plan: Wake Alarm MVP Wave 10 - Create Wake Plan Flow

- status: completed
- generated: 2026-07-05
- last_updated: 2026-07-07
- work_type: code

## Goal

- 週カレンダーのタップから作成BottomSheetを開き、プレビュー、保存、ブロック表示、native予約までの作成フローを完成させる。

## Definition of Done

- タップした日付・時刻を起床目標時刻としてWakePlanを作成できる。
- 60分前/5分間隔のプレビューと今回残り回数が表示できる。
- 保存後にカレンダーへWakePlanブロックが表示され、schedule結果が反映される。

## Scope / Non-goals

- Scope:
  - `lib/features/wake_plan/ui/create_wake_plan_sheet.dart`
  - `lib/features/week_calendar/**`
  - `test/features/wake_plan/ui/**`
- Non-goals:
  - 詳細/編集/削除。
  - 繰り返しskip UIの完成。

## Context (workspace)

- Related files/areas:
  - Wave 8 scheduling service and calendar core.
  - Wave 9 settings defaults and block rendering.
- Existing patterns or references:
  - `requirements.md` の7.1、7.2、9.2、12.1。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: inline warningの具体的な文言をどこまで統一するか。
- Q2: 詳細設定折りたたみの初期展開状態をユーザー操作後に記憶するか。
- Q3: 重複時間帯warningをどの閾値で出すか。

## Assumptions

- A1: 作成時の主入力は起床目標時刻、日付/繰り返し、window、interval、音、バイブ。
- A2: MVPでは初期値をシンプルにし、自由入力よりpreset中心にする。
- A3: タップ位置から定まる起床目標日時が過去の場合は作成不可にする。
- A4: エラー表示はinline warningを基本とし、操作結果の短い通知はsnackbar、破壊的確認だけdialogを使う。
- A5: 作成Sheetは基本項目を表示し、音/バイブなどの詳細設定は折りたたみにする。
- A6: 重複時間帯はinline warningを常時表示し、保存時の追加dialogは出さない。

## Tasks

### Task_1: Create Wake Plan Flow
- type: impl
- owns:
  - lib/features/wake_plan/ui/create_wake_plan_sheet.dart
  - lib/features/week_calendar/**
  - test/features/wake_plan/ui/**
- depends_on: []
- description: |
  Original Task_17. 週カレンダーのタップから作成BottomSheetを開き、プレビューと保存を実装する。
- acceptance:
  - タップした日付・時刻が起床目標時刻として初期入力される。
  - タップした日付・時刻が過去の場合は作成シートを確定できず、予約やWakePlan保存を行わない。
  - デフォルト値は60分前、5分間隔、繰り返しなし、バイブON、デフォルト音になる。
  - 音/バイブなどの詳細設定は折りたたみで表示できる。
  - プレビューに時間帯、間隔、合計回数、今回残り回数が表示される。
  - 作成後にWake Planブロックがカレンダーへ表示される。
  - 重複時間帯がある場合はinline warningで警告できる。
  - 重複時間帯がある場合でも保存時の追加dialogは出さない。
  - 過去時刻タップなど作成シートを出す前の軽いエラーはsnackbarで通知できる。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/wake_plan/ui test/features/week_calendar"
  - kind: e2e
    required: true
    owner: reviewer
    detail: "E2E / Visual Validation Specの作成フローを確認する"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]

## E2E / Visual Validation Spec

- provider: playwright-cli for Flutter web smoke where applicable; native manual evidence if schedule is exercised.
- artifact_root:
  - `.playwright-cli/`
  - `docs/qa/artifacts/`
- flows:
  - Week calendarで07:00相当をタップする。
  - Create sheetに起床目標、60分前、5分間隔、合計13回が表示される。
  - 保存後に06:00-07:00のWakePlan blockが表示される。
  - schedule failure fakeの場合、成功を偽らずwarningが表示される。
- viewports:
  - Mobile compact: 390x844.
  - Mobile large: 430x932.
- evidence_requirements:
  - Screenshot or recording of create sheet preview and resulting block.

## Rollback / Safety

- Create flowがnative予約に失敗した場合、WakePlanを保持し警告状態を表示する。

## Handoff To Next Wave

- Wave 11はこのcreate flowで作成されたWakePlanを詳細/編集/削除/鳴動/health checkで扱う。

## Progress Log (append-only)

- 2026-07-05 Draft created.
- 2026-07-07 Wave 10 delegated to Codex thread worker.
  - Task_1 Create Wake Plan Flow pending worktree: `local:2f8ac276-c4df-4e8b-9c27-290b3745d83b`; branch `codex/wave-10-create-flow`.
  - Validation gate: worker must return a merge-ready PR with required focused tests, analyzer, diff check, self-review, independent review, and `rtk gh-review-hook <PR>` exit 0 before orchestrator review/merge.
  - Runtime note: iOS 26+/Android API 36 real-device alarm validation remains user-deferred/unapproved; any simulator/emulator evidence is NEAR_DEVICE or BLOCKED only.
- 2026-07-07 Task_1 PR #21 returned merge-ready, then failed orchestrator merge gate after ready-for-review conversion.
  - Worker evidence on head `47176cff9a8a156135e63da39eb3dc18b503548b`: focused tests, full `rtk flutter test`, analyzer, diff check, independent review, and worker `rtk gh-review-hook 21` passed.
  - Orchestrator evidence: PR metadata/diff/current head inspected; deep-review common/UI/tests/data-store references consulted; `rtk flutter test test/features/wake_plan/ui test/features/week_calendar`, `rtk flutter analyze`, and `rtk git diff --check` passed in the worker worktree.
  - Gate result: after marking PR #21 ready, orchestrator `rtk gh-review-hook 21` exited 2 with Greptile findings around overlap-warning coverage, exception/provider error visibility, and database fallback diagnostics. The PR was not merged; the worker thread was instructed to verify/fix in scope and rerun validation/hook.
- 2026-07-07 Task_1 PR #21 merged; Wave 10 completed.
  - Summary: PR #21 `Add wake plan create flow` was squash-merged with merge commit `1fd61b7bc3555a7d77e0fef737b6d784365f5971`.
  - Final head: `83bc0830d320df7b913e78b4e6103356098a508a`.
  - Worker evidence: focused `rtk flutter test test/features/wake_plan/ui test/features/week_calendar`, `rtk flutter analyze`, `rtk git diff --check`, remote Baseline CI, Greptile Review, CodeRabbit, Socket checks, and worker `rtk gh-review-hook 21` passed after review follow-up fixes.
  - Orchestrator validation: PR metadata/diff/current head inspected; deep-review common/UI/tests pass found no blocker; `rtk gh-review-hook 21` exited 0; `rtk flutter test test/features/wake_plan/ui test/features/week_calendar`, `rtk flutter analyze`, and `rtk git diff --check` passed in the Task_1 worktree.
  - UI/E2E evidence: widget-level coverage verifies calendar tap -> create sheet preview -> save -> rendered block, plus schedule failure, provider error, overlap, and concurrent tap paths. Browser screenshot evidence remains not captured because no seeded Flutter web route/harness exists for this flow.
  - Worker lifecycle: Task_1 worker thread `019f3ca6-835c-7f00-a197-79e33b5b895b` archived after merge. The remote branch remained present because local branch deletion failed while the worker worktree was still attached; no product code action is pending.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Make create flow the first full vertical UI slice.
  - Trigger / new insight: MVP価値の入口は「タップしてWakePlanを作る」体験。
  - Plan delta (what changed): Wave 10を単独flowにした。
  - Tradeoffs considered: 編集や繰り返しは後続に回し、最初の縦切りを安定させる。
  - User approval: pending.

- 2026-07-05 Decision: Reject past target taps.
  - Trigger / new insight: User clarified that tap position always maps to one concrete date-time, so past targets should be rejected.
  - Plan delta (what changed): Create flow now treats past target taps as invalid and must not save or schedule a WakePlan.
  - Tradeoffs considered: Allowing future-only remaining occurrences was rejected because it would make the tapped target ambiguous from the user's intent.
  - User approval: yes.

- 2026-07-05 Decision: Use inline warnings, snackbars, and dialogs by severity.
  - Trigger / new insight: User requested applying the recommended error-display policy.
  - Plan delta (what changed): Wave 10 now treats overlap and form-level errors as inline warnings, pre-sheet transient errors as snackbar, and destructive confirmations as dialogs only.
  - Tradeoffs considered: This keeps routine validation visible without interrupting the create flow.
  - User approval: yes.

- 2026-07-05 Decision: Collapse advanced create settings and avoid duplicate-save dialogs.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 10 now requires basic create inputs to stay visible, sound/vibration-style details to be collapsed, and overlap warnings to avoid extra save-time dialogs.
  - Tradeoffs considered: This keeps the create flow fast while still surfacing conflict information.
  - User approval: yes.

## Notes

- Risks:
  - BottomSheetが小画面で詰まりやすい。
