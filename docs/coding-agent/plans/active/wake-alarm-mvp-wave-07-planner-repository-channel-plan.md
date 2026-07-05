# Plan: Wake Alarm MVP Wave 7 - Planner, Repository, and MethodChannel Wiring

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-06
- work_type: code

## Goal

- Wake PlanからOccurrenceを生成し、保存し、MethodChannel経由でnative alarm gatewayへ渡すための中間層を実装する。

## Definition of Done

- OccurrencePlannerが代表ケースをすべてテストで通す。
- WakePlanRepositoryがplan単位/期間指定/履歴保持の基本操作を持つ。
- MethodChannel gatewayがcontractのメソッド・引数・戻り値を固定する。

## Scope / Non-goals

- Scope:
  - `lib/features/wake_plan/application/occurrence_planner.dart`
  - `test/features/wake_plan/application/occurrence_planner_test.dart`
  - `lib/features/wake_plan/data/**`
  - `test/features/wake_plan/data/**`
  - `lib/core/platform/method_channel_native_alarm_gateway.dart`
  - `docs/platform/native-alarm-channel.md`
  - `ios/**`
  - `android/**`
  - `test/core/platform/**`
- Non-goals:
  - Production native bridge実装。
  - Full scheduling service orchestration。
  - UI。

## Context (workspace)

- Related files/areas:
  - Wave 5 time foundation.
  - Wave 6 domain and gateway contract.
- Existing patterns or references:
  - `requirements.md` の受け入れ条件12.1、12.4、12.5、12.6。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: Native側stubをどこまでこのwaveに含めるか。
- Q2: Native側で未知の`schemaVersion`を受け取った場合のエラーコードを何にするか。
- Q3: Drift migrationのintegration testをMVP中に必須にするか。

## Assumptions

- A1: 過去分Occurrenceは予約対象から除外するが、プレビューには本来回数と今回残り回数を表現できる。
- A2: 繰り返しWakePlanは表示/予約範囲に応じて生成し、無限にDB化しない。
- A3: WakePlanRepositoryの永続化backendはDriftを採用する。
- A4: MethodChannel payload schemaは`docs/platform/native-alarm-channel.md`とcontract testsの両方で固定する。
- A5: Drift migrationはMVP中もschemaVersionを上げて同一PR/taskでmigrationを書く。破壊的resetはdev/debug限定にする。
- A6: MethodChannel payloadには`schemaVersion: 1`を含める。
- A7: Repository schema must persist a nullable platform alarm identity per `AlarmOccurrence`, populated after successful native scheduling and used for occurrence/plan cancel. The Dart gateway/repository API for plan cancel requires the resolved stored occurrence/platform identity list before crossing the native boundary; native plan cancel does not receive only a logical WakePlan id and does not look up Drift rows.

## Tasks

### Task_1: Occurrence Planner
- type: impl
- owns:
  - lib/features/wake_plan/application/occurrence_planner.dart
  - test/features/wake_plan/application/occurrence_planner_test.dart
- depends_on: []
- description: |
  Original Task_8. Wake PlanからWake InstanceとAlarm Occurrenceを生成する純粋ロジックを実装する。
- acceptance:
  - `07:00 / 60分 / 5分` で13件生成される。
  - `07:00 / 45分 / 10分` で `06:15, 06:25, 06:35, 06:45, 06:55, 07:00` が生成される。
  - 作成時点で過去のOccurrenceは予約対象から除外される。
  - 日跨ぎ、一回限り、毎日、平日、土日、任意曜日が扱える。
  - 次回だけスキップ対象のWake Instanceは生成または予約対象から除外される。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/wake_plan/application/occurrence_planner_test.dart"
  - kind: review
    required: true
    owner: reviewer
    detail: "Occurrence生成ルールがrequirements.mdの受け入れ条件と一致するかレビューする"

### Task_2: Wake Plan Repository
- type: impl
- owns:
  - lib/features/wake_plan/data/**
  - test/features/wake_plan/data/**
- depends_on: []
- description: |
  Original Task_10. WakePlan、AlarmOccurrence、AppSettingsのローカル保存・取得・更新・削除を実装する。
- acceptance:
  - Driftを使ってWakePlan、AlarmOccurrence、AppSettingsを保存できる。
  - Drift schema変更時はschemaVersionを上げ、migration方針またはmigration codeを同じtaskで更新できる。
  - WakePlanとOccurrenceをplan単位で取得できる。
  - AlarmOccurrenceごとのnullable `platformAlarmId`相当を保存・更新・取得でき、native予約成功後のID反映とcancel時の参照に使える。
  - 期間指定で週カレンダー表示に必要なWakePlanを取得できる。
  - 一回限りWakePlanを最終アラーム+30分後に通常一覧から除外できる。
  - deleted/disabledを扱い、デバッグやQAに必要な履歴を短期間残せる設計になっている。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/wake_plan/data"
  - kind: review
    required: true
    owner: reviewer
    detail: "永続化境界がUIとネイティブ予約に漏れていないかレビューする"

### Task_3: MethodChannel Gateway Wiring
- type: impl
- owns:
  - lib/core/platform/method_channel_native_alarm_gateway.dart
  - docs/platform/native-alarm-channel.md
  - ios/**
  - android/**
  - test/core/platform/**
- depends_on: []
- description: |
  Original Task_12. Flutter MethodChannelのチャンネル名、メソッド名、引数/戻り値形式を確定し、Dart側の変換を実装する。
- acceptance:
  - `getCapability`、`requestPermissionIfNeeded`、`scheduleOccurrences`、`cancelOccurrences`、`cancelPlan`、`scheduleTestAlarm` のchannel呼び出しがある。
  - Dart caller-facing `cancelPlan` API requires the Repository-resolved stored occurrence/platform identity list; a `cancelPlan(wakePlanId)`-only API is not allowed at the native gateway boundary.
  - すべてのMethodChannel payloadに`schemaVersion: 1`が含まれる。
  - 引数と戻り値のJSON/Map構造が`docs/platform/native-alarm-channel.md`とcontract testsで固定されている。
  - schedule result payloadは各platform alarm idを元のOccurrence idへ相関でき、部分失敗もOccurrence単位で表現できる。
  - cancel payloadにOccurrence単位のplatform alarm identity対応が含まれている。
  - `cancelPlan` channel payloadはDart/Repository側で解決済みのstored `platformAlarmId` listを含み、native側がlogical WakePlan idだけで永続化を探索しない契約になっている。
  - ネイティブからのエラーをScheduleResultに変換できる。
  - FakeとMethodChannelの差し替えが容易になっている。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/core/platform"
  - kind: review
    required: true
    owner: reviewer
    detail: "MethodChannel契約がネイティブ実装に必要十分かレビューする"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1, Task_2, Task_3]

## Rollback / Safety

- Native側stubはproduction alarm予約を行わない。
- MethodChannel schema変更はテストと一緒に更新する。
- Drift schema変更はschemaVersionとmigration方針を同じtask内で更新する。
- 破壊的DB resetはdev/debug環境限定にする。

## Handoff To Next Wave

- Wave 8のWakePlanSchedulingServiceはTask_1/2/3を統合する。
- Wave 8のiOS/Android bridgeはTask_3のschemaをsource of truthにする。
- Wave 8はRepositoryのpersisted platform alarm identityを使って予約成功反映、individual cancel、plan cancel、reconciliationを実装する。Plan cancelではRepositoryが対象Occurrenceのstored `platformAlarmId` listを解決してからnative gateway APIを呼び、native境界へlogical WakePlan idだけを渡さない。

## Progress Log (append-only)

- 2026-07-06 Wave 3 decision integrated.
  - Repository and MethodChannel schema must preserve one nullable platform alarm identity per `AlarmOccurrence` before Wave 8 scheduling integration.
  - Plan cancel gateway and channel contracts must pass resolved stored platform alarm identities, not only a logical WakePlan id.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-06 Decision: Persist platform alarm identity before native scheduling integration.
  - Trigger / new insight: Wave 3 rolling reservations and Wave 8 scheduling service require stored native IDs for cancel/reconciliation.
  - Plan delta (what changed): Wave 7 repository and MethodChannel acceptance now explicitly include nullable per-Occurrence platform alarm identity storage, per-occurrence schedule result correlation, and cancel/plan-cancel payload support using resolved stored platform IDs.
  - Tradeoffs considered: Persisting IDs at the repository boundary avoids coupling later native bridge code to transient in-memory schedule results.
  - User approval: yes, from Wave 3 rolling reservation decision.

- 2026-07-05 Decision: Planner, repository, and channel wiring can be parallelized.
  - Trigger / new insight: 3 tasks share domain types but own distinct file areas.
  - Plan delta (what changed): Wave 7内でparallel tasksにした。
  - Tradeoffs considered: 統合不整合はWave 8 serviceで検出されるためreviewを必須にした。
  - User approval: pending.

- 2026-07-05 Decision: Use Drift and document MethodChannel schema.
  - Trigger / new insight: User requested applying the recommended decisions.
  - Plan delta (what changed): Wave 7 now requires Drift-backed repository work and a `docs/platform/native-alarm-channel.md` schema document alongside contract tests.
  - Tradeoffs considered: Drift gives explicit schema/migration control for alarm data; documenting MethodChannel payloads reduces Dart/native drift.
  - User approval: yes.

- 2026-07-05 Decision: Require Drift migrations and MethodChannel schema versioning.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 7 now requires Drift schemaVersion/migration updates for schema changes and `schemaVersion: 1` in MethodChannel payloads.
  - Tradeoffs considered: Versioning adds small payload overhead but prevents silent Dart/native contract drift.
  - User approval: yes.

## Notes

- Risks:
  - Drift migration rules must be kept aligned with repository tests as the model evolves.
