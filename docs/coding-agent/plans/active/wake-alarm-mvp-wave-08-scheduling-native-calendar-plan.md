# Plan: Wake Alarm MVP Wave 8 - Scheduling, Native Bridges, and Calendar Core

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-05
- work_type: code

## Goal

- WakePlan作成/編集/削除の予約サービス、iOS/Android native bridge、週カレンダーのinteraction coreを並行して実装する。

## Definition of Done

- WakePlanSchedulingServiceが保存、生成、予約、cancel、失敗反映を一貫して扱う。
- iOS/Android bridgeがWave 3/7のcontractに接続され、実機確認チェックリストが作成される。
- 週カレンダーのグリッド、ページング、タップ位置変換がテスト済み。

## Scope / Non-goals

- Scope:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `test/features/wake_plan/application/wake_plan_service_test.dart`
  - `ios/**`
  - `android/**`
  - `docs/qa/ios-alarmkit-checklist.md`
  - `docs/qa/android-alarm-checklist.md`
  - `lib/features/week_calendar/**`
  - `test/features/week_calendar/**`
- Non-goals:
  - 完成した作成/編集UI。
  - 繰り返しskip UI。
  - 最終QA。

## Context (workspace)

- Related files/areas:
  - Wave 3 platform decision.
  - Wave 7 planner/repository/channel.
- Existing patterns or references:
  - `requirements.md` の編集・削除・権限不足時の明示要件。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: Android再起動後再予約の実装詳細として、native mirror保存をどの粒度にするか。
- Q2: 現在時刻付近の初期スクロールを何分前の余白付きにするか。
- Q3: `pendingChange`状態が残ったままアプリ終了した場合の復旧UIをどう表示するか。

## Assumptions

- A1: 古いOccurrence cancelは新Occurrence scheduleより前に行う。
- A2: Native bridgeは失敗理由をScheduleResultへ返し、Flutter側が成功を偽らない。
- A3: Android再起動後再予約はMVP必須とする。
- A4: Native予約は7日分のローリングOccurrence予約を基本方針にする。
- A5: エラー表示はinline warningを基本とし、操作結果の短い通知はsnackbar、破壊的確認だけdialogを使う。
- A6: 週カレンダー初期スクロールは、今日を含む週なら現在時刻付近、それ以外の週なら05:00にする。
- A7: 編集時のDB更新順序は`pendingChange`保存 → old cancel → new schedule → committed/failedとする。

## Tasks

### Task_1: Wake Plan Scheduling Service
- type: impl
- owns:
  - lib/features/wake_plan/application/wake_plan_service.dart
  - test/features/wake_plan/application/wake_plan_service_test.dart
- depends_on: []
- description: |
  Original Task_11. 作成、編集、削除、skip、予約結果反映を一貫して扱うアプリケーションサービスを実装する。
- acceptance:
  - 作成時にWakePlan保存、Occurrence生成、Gateway予約、platformAlarmId反映ができる。
  - 編集時は`pendingChange`を保存し、古いOccurrence cancel、新Occurrence生成・予約、committed/failed反映の順序を守る。
  - 削除時は未来Occurrenceをcancelし、WakePlanをdeletedまたはdisabledにできる。
  - 予約失敗時はWakePlanを保持し、警告表示に使える状態を保存する。
  - 予約失敗や権限不足はinline warningとして表示できる状態で返せる。
  - 同一WakePlan内の重複Occurrenceを作らない。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/wake_plan/application/wake_plan_service_test.dart"
  - kind: review
    required: true
    owner: reviewer
    detail: "編集・削除・予約失敗時に古いアラームが残らない制御になっているかレビューする"

### Task_2: iOS AlarmKit Bridge
- type: impl
- owns:
  - ios/**
  - docs/qa/ios-alarmkit-checklist.md
- depends_on: []
- description: |
  Original Task_13. SwiftでAlarmKitBridgeを実装し、Dart MethodChannel契約に接続する。
- acceptance:
  - AlarmKit権限状態取得と権限要求が動作する。
  - 一回限りOccurrenceを複数予約し、platformAlarmIdを返せる。
  - Occurrence単位cancelとPlan単位cancelが動作する。
  - テストアラームを予約できる。
  - iOS実機確認結果がQA checklistに記録されている。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test"
  - kind: manual
    required: true
    owner: worker
    detail: "iOS 26以上環境でテストアラーム、複数Occurrence、個別cancel、plan cancelを確認する"
  - kind: review
    required: true
    owner: reviewer
    detail: "iOSコードとQA checklistをレビューする"

### Task_3: Android Alarm Bridge
- type: impl
- owns:
  - android/**
  - docs/qa/android-alarm-checklist.md
- depends_on: []
- description: |
  Original Task_14. KotlinでAlarmBridge、AlarmReceiver、BootReceiverを実装し、Dart MethodChannel契約に接続する。
- acceptance:
  - exact alarm、notification、full-screen intentの権限・設定状態を取得できる。
  - 複数Occurrenceを予約し、platformAlarmIdを返せる。
  - Occurrence単位cancelとPlan単位cancelが動作する。
  - 再起動後の再予約が実装され、制限がある場合はQA checklistに記録されている。
  - Android実機確認結果がQA checklistに記録されている。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test"
  - kind: manual
    required: true
    owner: worker
    detail: "Android API 36環境でテストアラーム、複数Occurrence、個別cancel、plan cancel、再起動後再予約を確認する"
  - kind: review
    required: true
    owner: reviewer
    detail: "AndroidコードとQA checklistをレビューする"

### Task_4: Week Calendar Grid and Interaction Core
- type: impl
- owns:
  - lib/features/week_calendar/**
  - test/features/week_calendar/**
- depends_on: []
- description: |
  Original Task_15. Wake Plan専用の週カレンダー表示、時間グリッド、ページング、タップ位置変換を実装する。
- acceptance:
  - 日付ヘッダー、縦時間軸、週PageView、現在時刻ラインが表示される。
  - 初期表示位置は今日を含む週なら現在時刻付近、それ以外の週なら05:00にできる。
  - タップ位置から日付と5分刻みの起床目標時刻を算出できる。
  - 00:00〜24:00内部モデルを保ち、早朝/深夜の表示が可能。
  - 外部カレンダー予定を前提にしないWake Plan専用UIになっている。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/week_calendar"
  - kind: e2e
    required: true
    owner: reviewer
    detail: "E2E / Visual Validation Specの週カレンダー空状態・タップ変換を確認する"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1, Task_2, Task_3, Task_4]

## E2E / Visual Validation Spec

- provider: playwright-cli for Flutter web smoke where applicable; iOS/Android simulator or実機 manual evidence for native alarm behavior.
- artifact_root:
  - `.playwright-cli/`
  - `docs/qa/artifacts/`
- flows:
  - Week calendar renders current week, time grid, current time line, and empty state.
  - Tap a day/time cell and verify date/time conversion.
  - iOS/Android test alarm can be scheduled and cancelled.
- viewports:
  - Mobile compact: 390x844.
  - Mobile large: 430x932.
- evidence_requirements:
  - Screenshots for calendar empty state.
  - Native logs/checklist rows for schedule/cancel.

## Rollback / Safety

- Native alarm changes must include cleanup/cancel procedure in QA checklist.
- Calendar code must not assume external calendar permissions.

## Handoff To Next Wave

- Wave 9 builds WakePlan block rendering and settings defaults on top of this wave.
- Wave 10 uses scheduling service and calendar tap interaction for create flow.

## Progress Log (append-only)

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Run service, bridges, and calendar core in parallel.
  - Trigger / new insight: File ownership is disjoint enough and all depend on Wave 7 outputs.
  - Plan delta (what changed): Wave 8 keeps integration-heavy tasks together but parallel.
  - Tradeoffs considered: Integration risk is higher, so each task has review and concrete validation.
  - User approval: pending.

- 2026-07-05 Decision: Set week calendar initial scroll behavior.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 8 now fixes initial scroll to current time for the current week and 05:00 for other weeks.
  - Tradeoffs considered: Current-week context improves immediate use, while 05:00 keeps non-current weeks focused on wake-planning hours.
  - User approval: yes.

- 2026-07-05 Decision: Use pending-change state for edit scheduling.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 8 now requires edit flows to persist `pendingChange`, cancel old alarms, schedule new alarms, then mark committed or failed.
  - Tradeoffs considered: This preserves recoverability if native cancel/schedule fails mid-edit.
  - User approval: yes.

## Notes

- Risks:
  - Native manual validation may block completion if devices are unavailable.
