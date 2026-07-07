# Plan: Wake Alarm MVP Wave 11 - Edit, Ringing, and Health Checks

- status: in progress
- generated: 2026-07-05
- last_updated: 2026-07-07
- work_type: code

## Goal

- 作成済みWakePlanの詳細/編集/削除、鳴動画面と停止動作、テストアラーム・権限チェックを実装する。

## Definition of Done

- 編集時に古いOccurrenceをcancelしてから新Occurrenceを予約できる。
- 鳴動画面は「今のアラームを止める」のみを主操作にし、未来Occurrenceを維持する。
- 権限不足やOS設定問題を検知し、テストアラームを実行できる。

## Scope / Non-goals

- Scope:
  - `lib/features/wake_plan/ui/**`
  - `lib/features/week_calendar/**`
  - `test/features/wake_plan/ui/**`
  - `lib/features/alarm_ringing/**`
  - `ios/**`
  - `android/**`
  - `test/features/alarm_ringing/**`
  - `lib/features/settings/**`
  - `lib/core/platform/**`
  - `test/features/settings/**`
- Non-goals:
  - 繰り返し・次回スキップUI完成。
  - 最終QA。

## Context (workspace)

- Related files/areas:
  - Wave 8 native bridges and scheduling service.
  - Wave 10 create flow.
- Existing patterns or references:
  - `requirements.md` の7.9、7.10、7.11、7.12、7.13、12.2、12.3、12.4。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: Android fallback画面をFlutter起動失敗時だけ表示するか、native firstからFlutterへ遷移するか。
- Q2: iOS AlarmKit UIで表示できない項目をアプリ内履歴で補完するか。
- Q3: テストアラーム結果を履歴としてどの期間保持するか。

## Assumptions

- A1: 鳴動中画面には「起きた」「残り全部停止」「今日はもう鳴らさない」「スヌーズ」を表示しない。
- A2: Health checkはスケジュール成功を偽らず、失敗理由を保持する。
- A3: AndroidはFlutter起動失敗時でも最低限停止できるnative fallback UIを必須にする。
- A4: テストアラームは1分後を標準にする。
- A5: エラー表示はinline warningを基本とし、操作結果の短い通知はsnackbar、破壊的確認だけdialogを使う。
- A6: Wave 3 keeps iOS/Android runtime behavior unapproved; ringing and health checks must record missing runtime evidence as BLOCKED, not as success.
- A7: Android stop behavior must have a native minimal UI path; Flutter-only stop handling is insufficient for MVP reliability.
- A8: Optional runtime checks are optional only for device execution; missing runtime evidence still requires explicit PASS or BLOCKED QA evidence rows.

## Tasks

### Task_1: Detail, Edit, and Delete Flow
- type: impl
- owns:
  - lib/features/wake_plan/ui/**
  - lib/features/week_calendar/**
  - test/features/wake_plan/ui/**
- depends_on: []
- description: |
  Original Task_18. Wake Plan詳細、編集、削除、繰り返し削除確認を実装する。
- acceptance:
  - ブロックタップから詳細を開き、次回予定、繰り返し、スキップ状態を確認できる。
  - 編集保存時に古いOccurrence cancel、新Occurrence生成、Gateway予約の順序を守る。
  - 削除時に未来Occurrenceをcancelし、カレンダーから消える。
  - 繰り返しWakePlan削除時は確認ダイアログを表示する。
  - 編集後の発火予定をユーザーが確認できる。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/wake_plan/ui test/features/week_calendar"
  - kind: e2e
    required: true
    owner: reviewer
    detail: "E2E / Visual Validation Specの詳細・編集・削除フローを確認する"

### Task_2: Alarm Ringing UI and Dismiss Flow
- type: impl
- owns:
  - lib/features/alarm_ringing/**
  - ios/**
  - android/**
  - test/features/alarm_ringing/**
- depends_on: []
- description: |
  Original Task_20. 鳴動中の表示と停止動作を実装する。AndroidはFlutter画面またはnative fallback、iOSはAlarmKit表示前提で必要な状態反映を行う。
- acceptance:
  - 現在時刻、起床目標時刻、何回目か、次回予定時刻を表示できる。
  - 主操作は「今のアラームを止める」のみ。
  - 「起きた」「残り全部停止」「今日はもう鳴らさない」「スヌーズ」は表示しない。
  - 停止すると当該Occurrenceのみdismissedになり、未来Occurrenceはscheduledのまま残る。
  - AndroidでFlutter起動が遅い場合も最低限停止できるfallbackがある。
  - iOS/Android runtime stop evidence is recorded when available; missing runtime evidence remains a release-blocking checklist item.
  - Runtime stop cases have explicit PASS or BLOCKED QA evidence rows even when device execution is unavailable.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/alarm_ringing"
  - kind: manual
    required: false
    owner: worker
    detail: "iOS/Android実機が利用可能な場合は鳴動画面と停止後の未来Occurrence維持を確認する。実行できない場合はBLOCKEDとして残し、Wave 11 completionやrelease approvalとは扱わない"
  - kind: review
    required: true
    owner: worker
    detail: "鳴動画面・停止・未来Occurrence維持のruntime evidenceについて、利用可能ならPASS、 unavailableならBLOCKEDのQA evidence rowがあることを確認する。device実行可否とは独立した必須evidence step"
  - kind: review
    required: true
    owner: reviewer
    detail: "鳴動画面に禁止導線が存在しないことと、stop/future-occurrence runtime evidenceにPASSまたはBLOCKEDのQA rowが記録されていることをレビューする"

### Task_3: Test Alarm and Health Checks
- type: impl
- owns:
  - lib/features/settings/**
  - lib/core/platform/**
  - ios/**
  - android/**
  - test/features/settings/**
- depends_on: []
- description: |
  Original Task_22. テストアラームと権限・OS設定チェックを実装する。
- acceptance:
  - 1分後のテストアラームを予約できる。
  - iOS AlarmKit権限不足を検知して警告できる。
  - Android exact alarm、notification、full-screen intent、通知チャンネルの問題を検知して警告できる。
  - 権限不足や予約失敗がホーム画面または設定画面のinline warningで確認できる。
  - アプリがスケジュール成功を偽らず、失敗理由を保持する。
  - 権限拒否やOS設定問題が未検証の場合はruntime validation pending/BLOCKEDとしてQA evidenceに残る。
  - 権限・テストアラームruntime cases have explicit PASS or BLOCKED QA evidence rows even when device execution is unavailable.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/settings test/core/platform"
  - kind: manual
    required: false
    owner: worker
    detail: "iOS/Android実機が利用可能な場合は権限拒否、権限許可、テストアラームを確認する。実行できない場合はBLOCKEDとして残し、Wave 11 completionやrelease approvalとは扱わない"
  - kind: review
    required: true
    owner: worker
    detail: "権限拒否・権限許可・テストアラームのruntime evidenceについて、利用可能ならPASS、unavailableならBLOCKEDのQA evidence rowがあることを確認する。device実行可否とは独立した必須evidence step"
  - kind: review
    required: true
    owner: reviewer
    detail: "権限不足時に鳴らない状態を放置しないUIになっていることと、permission/test-alarm runtime evidenceにPASSまたはBLOCKEDのQA rowが記録されていることをレビューする"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1, Task_2, Task_3]

## E2E / Visual Validation Spec

- provider: playwright-cli for Flutter web smoke where applicable; iOS/Android実機 manual evidence for native alarm behavior.
- artifact_root:
  - `.playwright-cli/`
  - `docs/qa/artifacts/`
- flows:
  - Open WakePlan detail, edit time, verify old schedule cancel and new preview/block.
  - Delete WakePlan, verify block disappears and future native alarms are cancelled.
  - Trigger alarm, stop current occurrence, verify future occurrence remains scheduled.
  - Deny/revoke permissions and verify warning.
- viewports:
  - Mobile compact: 390x844.
  - Mobile large: 430x932.
- evidence_requirements:
  - Screenshots or recordings for detail/edit/delete, alarm ringing UI, health warning.
  - Native logs for schedule/cancel/dismiss.

## Rollback / Safety

- Deleting or editing WakePlan must cancel old native reservations first.
- Test alarm ids must be distinguishable from production WakePlan ids.

## Handoff To Next Wave

- Wave 12 adds repeating/skip behavior on top of create/edit/delete and health checks.

## Progress Log (append-only)

- 2026-07-06 Wave 3 decision integrated.
  - Ringing, stop, permission, and test-alarm flows may be implemented before runtime approval, but missing iOS 26+ and Android API 36 evidence remains release-blocking.
  - Android fallback policy is native minimal stop UI, not Flutter-only recovery.
  - PASS/BLOCKED QA evidence rows are required even when device execution is unavailable.

- 2026-07-05 Draft created.
- 2026-07-07 Wave 11 Task_1 and Task_2 delegated to Codex thread/worktree workers.
  - Task_1 Detail, Edit, and Delete Flow pending worktree: `local:0b418590-5b9f-4bf7-9ea2-5d1e5f11ba52`; branch `codex/wave-11-detail-edit-delete`.
  - Task_2 Alarm Ringing UI and Dismiss Flow pending worktree: `local:1b45c1de-9357-4405-9010-75016431a711`; branch `codex/wave-11-alarm-ringing-dismiss`.
  - Worker type: Codex thread/worktree, not multi-agent subagent.
  - Merge gate: workers must provide required tests, analyzer/diff checks, self-review, independent review, and `rtk gh-review-hook <PR>` exit 0 before orchestrator review/merge.
  - Task_3 Test Alarm and Health Checks is intentionally not started yet because it overlaps Task_2 ownership in `ios/**` and `android/**`; start it after Task_2 merges or after a replan narrows non-overlapping native ownership.
  - Runtime note: iOS 26+/Android API 36 real-device alarm validation remains user-deferred/unapproved; runtime rows must be PASS only with actual evidence or BLOCKED when unavailable.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-06 Decision: Runtime stop and permission evidence remains release-blocking.
  - Trigger / new insight: Wave 3 distinguished implementation feasibility from runtime-approved reliability.
  - Plan delta (what changed): Wave 11 manual validations now explicitly record unavailable runtime cases as optional implementation evidence; unavailable cases are BLOCKED for release approval but do not block Wave 11 completion.
  - Tradeoffs considered: This permits feature implementation while preserving alarm reliability as a release gate.
  - User approval: yes, from Wave 3 deferment.

- 2026-07-05 Decision: Group edit, ringing, and health in one wave.
  - Trigger / new insight: これらは「作成後に信頼できるアラームとして運用できるか」を確認する一群。
  - Plan delta (what changed): Wave 11をoperational correctness waveにした。
  - Tradeoffs considered: Native file overlapがあるためparallel workers must coordinate through MethodChannel contract and checklist sections.
  - User approval: pending.

- 2026-07-07 Decision: Stagger Task_3 until Task_2 native ownership is clear.
  - Trigger / new insight: Task_2 and Task_3 both own `ios/**` and `android/**`, so starting both immediately would create high-conflict native bridge edits.
  - Plan delta (what changed): Start Task_1 and Task_2 now; defer Task_3 until Task_2 merges or a follow-up replan splits native ownership safely.
  - Tradeoffs considered: This reduces parallelism but protects merge safety and review clarity.
  - User approval: orchestrator-owned dependency adjustment under the existing parent instruction to continue through the plan.

- 2026-07-05 Decision: Require Android fallback UI and 1-minute test alarms.
  - Trigger / new insight: User accepted the recommended decisions except for explicitly overridden calendar/tap behavior.
  - Plan delta (what changed): Wave 11 now treats Android native fallback stopping UI as mandatory and fixes test alarms to 1 minute.
  - Tradeoffs considered: 30-second alarms can be less reliable across OS states; 1 minute is clearer for manual validation.
  - User approval: yes.

## Notes

- Risks:
  - iOS AlarmKit system UIでFlutter側と同一の鳴動画面を表示できない可能性がある。
