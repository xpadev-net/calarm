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
  - `.github/workflows/**`
  - `docs/qa/ci-baseline.md`
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
- A8: Baseline GitHub Actions CI can be implemented before native bridge runtime smoke because it only needs the Flutter scaffold and existing unit/analyzer tooling.

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

### Task_4: Baseline GitHub Actions CI
- type: chore
- owns:
  - `.github/workflows/**`
  - `docs/qa/ci-baseline.md`
- depends_on: []
- description: |
  Add ordinary PR CI as early as practical so formatting, lint/analyzer, and unit tests run automatically before later native smoke workflows are added.
- acceptance:
  - GitHub Actions workflow runs on pull_request and manual dispatch for ordinary validation.
  - CI installs or selects the project Flutter SDK consistently with `.fvmrc` when available.
  - CI runs dependency resolution before validation.
  - CI runs Dart formatting check, Flutter analyzer/lints, and Flutter unit tests.
  - CI uploads or prints enough logs to diagnose format/analyzer/test failures.
  - CI is documented in `docs/qa/ci-baseline.md`, including commands, trigger policy, and what evidence it does and does not cover.
  - Baseline CI is separate from Wave 8 simulator/emulator native smoke and does not claim runtime alarm validation.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "dart format --set-exit-if-changed ."
  - kind: command
    required: true
    owner: worker
    detail: "flutter analyze"
  - kind: command
    required: true
    owner: worker
    detail: "flutter test"
  - kind: ci
    required: true
    owner: worker
    detail: "GitHub Actions baseline CI workflow is syntax-checked and observed on the PR, or any hosted-runner/toolchain blocker is recorded with exact evidence"
  - kind: review
    required: true
    owner: reviewer
    detail: "Verify baseline CI covers formatting, analyzer/lint, and unit tests without overlapping or weakening native smoke/release validation"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1, Task_2, Task_3, Task_4]

## Rollback / Safety

- Native側stubはproduction alarm予約を行わない。
- MethodChannel schema変更はテストと一緒に更新する。
- Drift schema変更はschemaVersionとmigration方針を同じtask内で更新する。
- 破壊的DB resetはdev/debug環境限定にする。

## Handoff To Next Wave

- Wave 8のWakePlanSchedulingServiceはTask_1/2/3を統合する。
- Wave 8のiOS/Android bridgeはTask_3のschemaをsource of truthにする。
- Wave 8はRepositoryのpersisted platform alarm identityを使って予約成功反映、individual cancel、plan cancel、reconciliationを実装する。Plan cancelではRepositoryが対象Occurrenceのstored `platformAlarmId` listを解決してからnative gateway APIを呼び、native境界へlogical WakePlan idだけを渡さない。
- Wave 8のCI simulator/emulator native smoke workflowは、Task_4のbaseline CI workflowを置き換えず、native smoke用job/workflowとして追加または拡張する。

## Progress Log (append-only)

- 2026-07-06 Wave 7 Task_1 Occurrence Planner merged.
  - Summary: PR #11 `Add wake occurrence planner` was squash-merged after worker validation, independent review, gh-review-hook, base-branch updates, hosted Baseline CI, and orchestrator merge gate.
  - Merge commit: `3878b794d1f83ddd58f84b5fa1488417c161ca7b`.
  - Branch/head: `codex/wave-07-occurrence-planner` at `dea80f19bbc7407f618c894ee438410bf7bc410d`.
  - Changed files: `lib/features/wake_plan/application/occurrence_planner.dart` and `test/features/wake_plan/application/occurrence_planner_test.dart`.
  - Validation evidence: Worker `rtk flutter test test/features/wake_plan/application/occurrence_planner_test.dart`, `rtk flutter analyze`, and `rtk git diff --check` passed; orchestrator reran the same checks from a clean PR-head worktree after updating the branch to current master, and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved; orchestrator inspected preview vs scheduling candidate semantics, repeat/skip usage through `WakePlan.occursOn`, day-crossing handling, and interval target inclusion.
  - Hook/check evidence: Worker final `rtk gh-review-hook 11` exited 0; orchestrator reran `rtk gh-review-hook 11`, waited for refreshed hosted Baseline CI, CodeRabbit, Greptile, and Socket checks, and all passed.
  - Remaining Wave 7 work: Task_2 Wake Plan Repository remains active or pending orchestrator merge; Task_3 and Task_4 are already merged.

- 2026-07-06 Wave 7 Task_4 Baseline GitHub Actions CI merged.
  - Summary: PR #9 `Add baseline Flutter CI` was squash-merged after worker validation, hosted CI, independent review, hook fixes, base-branch merge, and orchestrator merge gate.
  - Merge commit: `962dbc5da24ae6447efc436be2464d9c8a922b42`.
  - Branch/head: `codex/wave-07-baseline-ci` at `c9f75b0fccad1edb979163a827beb3425f1bd64d`.
  - Changed files: `.github/workflows/baseline-ci.yml` and `docs/qa/ci-baseline.md`.
  - Validation evidence: Worker `rtk flutter pub get`, `rtk dart format --set-exit-if-changed .`, `rtk flutter analyze`, `rtk flutter test`, and `rtk git diff --check` passed; orchestrator reran the same checks plus workflow YAML parse from a clean PR-head worktree after updating the branch to current master, and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved; hook-requested `.fvmrc` `.flutterSdkVersion` compatibility was fixed; orchestrator inspected workflow triggers, Flutter setup, validation commands, artifact upload, and non-coverage of native runtime smoke.
  - Hook/check evidence: Worker final `rtk gh-review-hook 9` exited 0; orchestrator reran `rtk gh-review-hook 9`, observed refreshed hosted Baseline CI success, and verified GitHub CodeRabbit, Greptile, Socket, and Baseline CI checks passed.
  - Remaining Wave 7 work: Task_1 Occurrence Planner and Task_2 Wake Plan Repository remain active or pending orchestrator merge; Task_3 is already merged.

- 2026-07-06 Wave 7 Task_3 MethodChannel Gateway Wiring merged.
  - Summary: PR #10 `Wave 7: Wire native alarm MethodChannel gateway` was squash-merged after worker validation, independent review, gh-review-hook, and orchestrator merge gate.
  - Merge commit: `3167325907868816a04482e358d44b4b707daf9c`.
  - Branch/head: `codex/wave-07-method-channel-gateway` at `678fb2c9e8326058cca0ccf06ba2a63243d17f3a`.
  - Changed files: `lib/core/platform/method_channel_native_alarm_gateway.dart`, `docs/platform/native-alarm-channel.md`, and `test/core/platform/method_channel_native_alarm_gateway_test.dart`.
  - Validation evidence: Worker `rtk flutter test test/core/platform` passed with 34 tests, `rtk flutter analyze` passed, and `rtk git diff --check` passed; orchestrator reran `rtk flutter test test/core/platform`, `rtk flutter analyze`, and `rtk git diff --check` from a clean PR-head worktree and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved after fixing omitted `supportsTestAlarm` compatibility/default behavior; orchestrator inspected schema versioning, cancel identity payloads, PlatformException mapping, and docs/test alignment.
  - Hook/check evidence: Worker final `rtk gh-review-hook 10` exited 0 after a normal master merge; orchestrator marked PR ready and reran `rtk gh-review-hook 10`, which exited 0; GitHub CodeRabbit and Socket checks passed.
  - Remaining Wave 7 work: Task_1 Occurrence Planner, Task_2 Wake Plan Repository, and Task_4 Baseline GitHub Actions CI remain active or pending orchestrator merge.

- 2026-07-06 Wave 7 planner/repository/channel/CI tasks delegated in parallel.
  - Task_1 Occurrence Planner thread: `019f33d4-a600-7462-96ef-26c49e67a936`; pending worktree: `local:4503e9d0-f2d6-4bf8-98de-c839dbad3111`.
  - Task_1 Branch: `codex/wave-07-occurrence-planner`.
  - Task_1 Scope: `lib/features/wake_plan/application/occurrence_planner.dart` and `test/features/wake_plan/application/occurrence_planner_test.dart`.
  - Task_2 Wake Plan Repository thread: `019f33d4-a5fc-7ba0-8f14-f974af181e28`; pending worktree: `local:8fe1664a-241c-44a9-b5af-6da9c8d272bf`.
  - Task_2 Branch: `codex/wave-07-wake-plan-repository`.
  - Task_2 Scope: `lib/features/wake_plan/data/**` and `test/features/wake_plan/data/**`.
  - Task_3 MethodChannel Gateway Wiring thread: `019f33d4-a978-7b32-8aa5-c9c67e531f6a`; pending worktree: `local:140e55b3-2943-487f-9b05-06f15194ac54`.
  - Task_3 Branch: `codex/wave-07-method-channel-gateway`.
  - Task_3 Scope: `lib/core/platform/method_channel_native_alarm_gateway.dart`, `docs/platform/native-alarm-channel.md`, `ios/**`, `android/**`, and `test/core/platform/**`.
  - Task_4 Baseline GitHub Actions CI thread: `019f33d4-aeca-7053-89b3-8041f60a3f64`; pending worktree: `local:6966b4b3-034f-49e2-a2df-4113c90f2439`.
  - Task_4 Branch: `codex/wave-07-baseline-ci`.
  - Task_4 Scope: `.github/workflows/**` and `docs/qa/ci-baseline.md`.
  - Validation ownership: each worker must provide focused required validation, independent review, PR hook evidence, and a merge-ready or blocked report without merging.

- 2026-07-06 Baseline CI task added.
  - Summary: Add Task_4 for ordinary GitHub Actions PR CI covering format, analyzer/lint, and unit tests before later native smoke work.
  - Timing: This is placed in Wave 7 because it can run as soon as the Flutter scaffold exists and does not require native bridge runtime smoke implementation.

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

- 2026-07-06 Decision: Add ordinary baseline CI before native smoke CI.
  - Trigger / new insight: User asked to add ordinary CI checks in addition to near-device CI, including formatting, lint, and unit tests.
  - Plan delta (what changed): Wave 7 now includes Task_4 for GitHub Actions baseline PR CI and documentation, independent from Wave 8 simulator/emulator native smoke.
  - Tradeoffs considered: Baseline CI can be added earlier and improves every following PR; native smoke remains later because it needs bridge code and runtime/toolchain evidence.
  - User approval: yes.

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
