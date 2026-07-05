# Plan: Wake Alarm MVP Wave 6 - Domain and Gateway Contracts

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-05
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
- Q2: ScheduleResultの部分失敗をどの粒度で表すか。
- Q3: Gateway contractをMethodChannel Mapで固定するか、将来Pigeon化前提の型へ寄せるか。

## Assumptions

- A1: OccurrenceをdismissしてもWakePlan全体は停止しない。
- A2: GatewayはiOS/Androidの具体APIに依存しないDart interfaceとして定義する。

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

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Domain and Gateway can run in parallel.
  - Trigger / new insight: 両者はWave 5/3の前提に依存するが互いのファイル所有は分離している。
  - Plan delta (what changed): Wave 6内でparallel tasksにした。
  - Tradeoffs considered: 型の名前合わせはreviewで統合する。
  - User approval: pending.

## Notes

- Risks:
  - Gateway result modelが後続native実装で不足する可能性がある。
