# Plan: Wake Alarm MVP Wave 6 - Domain and Gateway Contracts

- status: done
- generated: 2026-07-05
- last_updated: 2026-07-06
- work_type: code

## Goal

- Wake Plan domain modelとNativeAlarmGateway契約を並行実装し、後続のplanner/service/native wiringの入力を固定する。

## Definition of Done

- WakePlan、AlarmOccurrence、RepeatRule、AppSettings、主要状態enumが表現できる。
- Native alarm capability、permission、schedule/cancel/test resultのDart契約とFakeがテストできる。

## Scope / Non-goals

- Scope:
  - `lib/features/wake_plan/domain/**`
  - `test/features/wake_plan/domain/**`
  - `lib/core/platform/native_alarm_gateway.dart`
  - `lib/core/platform/fake_native_alarm_gateway.dart`
  - `test/core/platform/**`
- Non-goals:
  - OccurrencePlanner本体。
  - MethodChannel実装。
  - 永続化実装。

## Context (workspace)

- Related files/areas:
  - Wave 5 time foundation.
  - Wave 3 platform decision.
- Existing patterns or references:
  - `requirements.md` のWakePlan/AlarmOccurrence状態定義。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: `failed`状態はOccurrenceだけに持つか、WakePlanにもsummaryとして持つか。
- Q2: ScheduleResultの部分失敗をどの粒度で表すか。Wave 3 decisionにより、少なくともOccurrence単位でsuccess/failure/platformAlarmIdを相関できる必要がある。
- Q3: Gateway contractをMethodChannel Mapで固定するか、将来Pigeon化前提の型へ寄せるか。

## Assumptions

- A1: OccurrenceをdismissしてもWakePlan全体は停止しない。
- A2: GatewayはiOS/Androidの具体APIに依存しないDart interfaceとして定義する。
- A3: Wave 3 rolling reservation decision requires one persisted platform alarm identity per scheduled `AlarmOccurrence`; the domain model must allow it to be absent before scheduling and present after successful native reservation.

## Tasks

### Task_1: Wake Plan Domain Models
- type: impl
- owns:
  - lib/features/wake_plan/domain/**
  - test/features/wake_plan/domain/**
- depends_on: []
- description: |
  Original Task_7. WakePlan、AlarmOccurrence、RepeatRule、AppSettings、状態enumを実装する。
- acceptance:
  - WakePlanが一回限り、曜日繰り返し、enabled/deleted、skipNextDateを表現できる。
  - AlarmOccurrenceがscheduled/ringing/dismissed/missed/expired/cancelled/failedを表現できる。
  - AlarmOccurrenceがnative予約後の`platformAlarmId`相当の識別子をnullable valueとして保持できる。
  - occurrenceのdismissがWakePlan全体の停止にならない状態をモデルで表せる。
  - 音、バイブ、interval、startOffsetの制約を表現できる。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/wake_plan/domain"
  - kind: review
    required: true
    owner: reviewer
    detail: "モデルがrequirements.mdの用語・状態管理要件と対応しているかレビューする"

### Task_2: Native Alarm Gateway Contract
- type: impl
- owns:
  - lib/core/platform/native_alarm_gateway.dart
  - lib/core/platform/fake_native_alarm_gateway.dart
  - test/core/platform/**
- depends_on: []
- description: |
  Original Task_9. Flutterからネイティブ層へ渡す抽象契約とFake実装を作る。
- acceptance:
  - capability取得、権限要求、Occurrence予約、Occurrence cancel、Plan cancel、テストアラーム予約のAPIがある。
  - ScheduleResultで成功、権限不足、OS制約、部分失敗、platformAlarmIdを表現できる。
  - ScheduleResultは各native platform alarm idを入力した正確な`AlarmOccurrence`へ相関できる。部分失敗時もOccurrenceごとにsuccess/failure、failure reason、platformAlarmIdの有無を表現できる。
  - ScheduleResultとcancel APIがOccurrence単位のplatform alarm identity保存・参照に必要な情報を表現できる。
  - Plan cancel APIはlogical WakePlan idだけをnativeへ渡さず、Repository側で解決済みのOccurrence id / platformAlarmId listを入力にする。
  - Fake実装で成功、失敗、部分失敗、権限不足をテストできる。
  - ネイティブ側の具体方式に依存しないDart APIになっている。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/core/platform"
  - kind: review
    required: true
    owner: reviewer
    detail: "Gateway契約がiOS/Android双方のスパイク結論に対応しているかレビューする"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1, Task_2]

## Rollback / Safety

- DomainとGatewayはpure Dartに寄せ、native side effectsを持たせない。

## Handoff To Next Wave

- Wave 7はTask_1のdomain modelをOccurrencePlanner/Repositoryで使う。
- Wave 7はTask_2のGateway contractをMethodChannel wrapperで実装する。

## Progress Log (append-only)

- 2026-07-06 Wave 6 Task_2 Native Alarm Gateway Contract merged; Wave 6 complete.
  - Summary: PR #8 `Wave 6 Task 2: Native alarm gateway contract` was squash-merged after worker validation, independent review, hook fixes, base-branch merge, GitHub checks, and orchestrator merge gate.
  - Merge commit: `10b48a5655b7ffddc7dee600df5b31449039021d`.
  - Branch/head: `codex/wave-06-native-alarm-gateway-contract` at `bd501231535de49edf3b3aaff224d689d35de0a5`.
  - Changed files: `lib/core/platform/native_alarm_gateway.dart`, `lib/core/platform/fake_native_alarm_gateway.dart`, and `test/core/platform/native_alarm_gateway_test.dart`.
  - Validation evidence: Worker `rtk flutter test test/core/platform`, `rtk flutter analyze`, and `rtk git diff --check` passed; orchestrator reran `rtk flutter test test/core/platform`, `rtk flutter analyze`, and `rtk git diff --check` from a clean PR-head worktree and all passed.
  - Review evidence: Worker deep-review and independent reviewer approved after fixing schedule correlation by `occurrenceId + wakePlanId`, fake unsupported test-alarm behavior, fake naming, shared request/result correlation, and dominant all-failure status selection; orchestrator inspected the scoped diff and focused tests.
  - Hook/check evidence: Worker final `rtk gh-review-hook 8` exited 0; orchestrator reran `rtk gh-review-hook 8` from a clean PR-head worktree and it exited 0; GitHub CodeRabbit, Greptile, and Socket checks passed.
  - Completion: Task_1 and Task_2 are both merged, so Wave 6 is complete. Runtime validation for iOS 26+ / Android API 36 alarms remains deferred and unapproved for later release gates.

- 2026-07-06 Wave 6 Task_1 Wake Plan Domain Models merged.
  - Summary: PR #7 `Add wake plan domain models` was squash-merged after worker validation, independent review, GitHub checks, and orchestrator merge gate.
  - Merge commit: `573a5e2f22d73dca6e27bc9289fe70d165be74be`.
  - Validation evidence: Worker `rtk flutter test test/features/wake_plan/domain` passed with 15 tests, `rtk flutter analyze` passed, and `rtk git diff --check` passed; orchestrator reran `rtk flutter test test/features/wake_plan/domain`, `rtk flutter analyze`, and `rtk git diff --check` from a clean PR-head worktree and all passed.
  - Review evidence: Worker deep-review self-review fixed weekly set hash consistency and nullable settings copy behavior; independent reviewer findings on skip-state consistency, minimum interval, and occurrence timestamp/status consistency were fixed and re-reviewed as approved; orchestrator inspected model files and focused tests.
  - Hook/check evidence: Worker `rtk gh-review-hook 7` exited 0 from a clean PR-head worktree; orchestrator reran `rtk gh-review-hook 7` from a clean PR-head worktree and it exited 0; GitHub CodeRabbit, Greptile, and Socket checks passed.
  - PR state: #7 merged; branch head `3be2d61a5820d7311f08db85e795987928c9032d`; merge commit `573a5e2f22d73dca6e27bc9289fe70d165be74be`.
  - Remaining Wave 6 work: completed by PR #8 on 2026-07-06.

- 2026-07-06 Wave 6 domain and gateway contracts delegated in parallel.
  - Task_1 Worker pending worktree: `local:ba19222c-bbe3-4305-b41f-f8baa6b1c93a`.
  - Task_1 Branch: `codex/wave-06-wake-plan-domain`.
  - Task_1 Scope: `lib/features/wake_plan/domain/**` and `test/features/wake_plan/domain/**`.
  - Task_2 Worker pending worktree: `local:dc234667-dde3-4405-b6b1-6ebbbad63e9e`.
  - Task_2 Branch: `codex/wave-06-native-alarm-gateway-contract`.
  - Task_2 Scope: `lib/core/platform/native_alarm_gateway.dart`, `lib/core/platform/fake_native_alarm_gateway.dart`, and `test/core/platform/**`.
  - Required gates: each worker must provide focused Flutter tests, `rtk flutter analyze`, `rtk git diff --check`, independent review, and `rtk gh-review-hook <PR_NUMBER>`.

- 2026-07-06 Wave 3 decision integrated.
  - Domain and gateway contracts must support one persisted platform alarm identity per `AlarmOccurrence` for rolling concrete native reservations.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-06 Decision: Add platform alarm identity to domain/gateway contract.
  - Trigger / new insight: Wave 3 adopted rolling concrete native occurrence reservations with one native identity per occurrence.
  - Plan delta (what changed): Wave 6 domain and gateway acceptance now require nullable `platformAlarmId`-equivalent storage on `AlarmOccurrence`, per-occurrence ScheduleResult correlation including partial failures, and result/cancel contracts that preserve it.
  - Tradeoffs considered: Keeping the field nullable supports pre-schedule planner output while making post-schedule persistence explicit.
  - User approval: yes, from Wave 3 rolling reservation decision.

- 2026-07-05 Decision: Domain and Gateway can run in parallel.
  - Trigger / new insight: 両者はWave 5/3の前提に依存するが互いのファイル所有は分離している。
  - Plan delta (what changed): Wave 6内でparallel tasksにした。
  - Tradeoffs considered: 型の名前合わせはreviewで統合する。
  - User approval: pending.

## Notes

- Risks:
  - Gateway result modelが後続native実装で不足する可能性がある。
