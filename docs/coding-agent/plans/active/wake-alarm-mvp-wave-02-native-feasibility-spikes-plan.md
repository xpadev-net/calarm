# Plan: Wake Alarm MVP Wave 2 - Native Alarm Feasibility Spikes

- status: complete
- generated: 2026-07-05
- last_updated: 2026-07-06
- work_type: research

## Goal

- iOS 26+ AlarmKit と Android API 36 alarm/full-screen notification がMVP要件を満たすか実機または対応環境で検証する。

## Definition of Done

- iOS/Android双方で、複数Occurrence予約、発火、停止、未来Occurrence維持、cancel、権限不足時の挙動が記録されている。
- OS繰り返しを使うかローリング予約に寄せるか判断できる証跡がある。
- 続行不可の制約があれば、Wave 3でスコープ判断できる粒度で明記されている。

## Scope / Non-goals

- Scope:
  - `ios/**`
  - `android/**`
  - `docs/spikes/native-alarm-feasibility.md`
- Non-goals:
  - Production-ready bridge実装。
  - Flutter UI実装。

## Context (workspace)

- Related files/areas:
  - `docs/spikes/native-alarm-feasibility.md`
  - `implement-plan-draft.md`
- Existing patterns or references:
  - Wave 1のテンプレートを使用する。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: iOS AlarmKitの繰り返し機能は次回だけスキップに十分か。
- Q2: Androidは`setAlarmClock`を第一候補にできるか、それとも別APIの併用が必要か。
- Q3: 実機未確保の場合、どの項目をBLOCKEDとしてWave 3へ渡すか。

## Assumptions

- A1: スパイクコードは後続で捨ててもよい最小コードとし、production設計を固定しすぎない。
- A2: ロック中・アプリ終了中・権限拒否の検証は手動証跡を必須にする。

## Tasks

### Task_1: iOS AlarmKit Feasibility Spike
- type: research
- owns:
  - ios/**
  - docs/spikes/native-alarm-feasibility.md
- depends_on: []
- description: |
  Original Task_2. iOS 26以上でAlarmKitを使い、MVPの複数アラーム要件が成立するか検証する。
- acceptance:
  - AlarmKit認可、1分後テスト、短間隔3件、5分間隔13件相当の予約結果が記録されている。
  - ロック中、アプリ終了中、サイレント/Focus中の挙動が記録されている。
  - 1件停止後に未来アラームが残るか検証されている。
  - platformAlarmId相当の識別子で個別cancelとplan cancelができるか記録されている。
  - AlarmKitの繰り返し機能が次回だけスキップに向くか、ローリング予約が必要か判断材料がある。
- validation:
  - kind: manual
    required: true
    owner: worker
    detail: "iOS 26以上の実機または対応環境で検証し、docs/spikes/native-alarm-feasibility.mdへ結果とartifactパスを記録する"
  - kind: review
    required: true
    owner: reviewer
    detail: "iOSスパイク結果がMVP続行判断に十分かレビューする"

### Task_2: Android Alarm Feasibility Spike
- type: research
- owns:
  - android/**
  - docs/spikes/native-alarm-feasibility.md
- depends_on: []
- description: |
  Original Task_3. Android API 36でAlarmManager、exact alarm権限、full-screen notification、BootReceiverの成立性を検証する。
- acceptance:
  - 1分後テスト、短間隔3件、5分間隔13件相当の予約結果が記録されている。
  - ロック中、アプリ終了中、通知権限拒否、exact alarm不可、再起動後再予約の挙動が記録されている。
  - full-screen notificationから停止UIを表示できるか確認されている。
  - 1件停止後に未来アラームが残るか検証されている。
  - setAlarmClock採用可否、権限方針、native fallback要否が結論化されている。
- validation:
  - kind: manual
    required: true
    owner: worker
    detail: "Android API 36実機またはエミュレータで検証し、docs/spikes/native-alarm-feasibility.mdへ結果とartifactパスを記録する"
  - kind: review
    required: true
    owner: reviewer
    detail: "Androidスパイク結果がMVP続行判断に十分かレビューする"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1, Task_2]

## Rollback / Safety

- スパイクコードは後続実装へ流用する前にreviewする。
- 実機に残ったtest alarmはWave終了時に全cancelし、cleanup結果をスパイク文書へ記録する。

## Handoff To Next Wave

- Wave 3へ、採用API、権限方針、ローリング予約要否、未解決BLOCKED項目を渡す。

## Progress Log (append-only)

- 2026-07-06 Runtime validation deferred by user decision.
  - User decision: runtime validation is acceptable to defer.
  - Scope of deferment: iOS 26+ real-device/compatible-runtime validation and Android API 36 device/emulator/runtime validation remain unexecuted.
  - Completion basis: Wave 2 now closes as merged blocker/API-surface evidence with user-approved runtime-validation deferment, not as platform runtime approval.
  - Handoff: Wave 3 must treat both platforms as runtime-unapproved and decide whether MVP continues with explicit risk, scope limits, and later validation gates.

- 2026-07-06 Task_2 blocked evidence merged.
  - PR: #3 https://github.com/xpadev-net/calarm/pull/3
  - Branch head: `a1af0266505850bf99c55ab68e570914a9320bb5`.
  - Merge commit: `d07086e6951aa0f2b2eae787e56d152d45fac7f4`.
  - Changed files: `docs/spikes/native-alarm-feasibility.md`.
  - Worker validation evidence: `rtk git diff --check` passed; Android build/compile was not run because the repository has no `android/**` app target and no Android API 36 SDK/runtime is installed.
  - Review evidence: independent Worker reviewer approved; `gh-review-hook 3` exited 0 after the Worker clarified runtime-readiness wording; GitHub checks passed.
  - Blocker: required Android runtime validation could not run because `adb devices -l` found no attached devices or running emulators, `emulator -list-avds` found no configured AVDs, installed Android SDK platforms were android-30, android-33, and android-34 only, and no android-36 platform/system image or installable app target was available.
  - Orchestrator validation evidence: PR diff and merge gates were inspected; Android runtime cases remain explicitly pending/blocked and the document does not approve Android MVP alarm reliability.

- 2026-07-06 Task_2 delegated to Worker.
  - Worker branch: `codex/wave-02-android-alarm-spike`.
  - Worker state: pendingWorktreeId `local:19d896f0-cf7c-4471-8110-403527fcfc38`.
  - Scope: `android/**`, Android-related sections of `docs/spikes/native-alarm-feasibility.md`.
  - Validation evidence: pending Android API 36 real-device/emulator validation, or concrete blocked report if the environment is unavailable.

- 2026-07-06 Task_1 blocked evidence merged.
  - PR: #2 https://github.com/xpadev-net/calarm/pull/2
  - Branch head: `6e5da033c8e640acf648ac5139482d5ad5e7e041`.
  - Merge commit: `1dd4b7ef91cff1f2db12a1d0a2875bfaf93d28d6`.
  - Changed files: `docs/spikes/native-alarm-feasibility.md`.
  - Worker validation evidence: `rtk git diff --check` passed; bounded AlarmKit SDK `swiftc -typecheck` probe passed for authorization APIs, fixed schedule, weekly relative recurrence, UUID IDs, cancel, stop, and alarms list.
  - Review evidence: independent Worker reviewer approved; `gh-review-hook 2` exited 0; GitHub checks passed.
  - Blocker: required iOS manual/runtime validation could not run because no iOS 26+ real device or compatible runtime was available, `xcrun devicectl list devices` found no devices, available simulator runtime was iOS 18.0 only, and the repository has no `ios/` app target for install/terminated-app validation.
  - Orchestrator validation evidence: PR diff and final evidence document were inspected; all iOS runtime cases remain explicitly pending/blocked and the local API evidence favors rolling concrete occurrence reservation but does not approve iOS MVP alarm reliability.

- 2026-07-06 Task_1 delegated to Worker.
  - Worker branch: `codex/wave-02-ios-alarmkit-spike`.
  - Worker state: pendingWorktreeId `local:e1f9aad7-06a0-4aed-b5be-fedd6a1cc42a`.
  - Scope: `ios/**`, iOS-related sections of `docs/spikes/native-alarm-feasibility.md`.
  - Validation evidence: pending iOS 26+ real-device or compatible-environment validation, or concrete blocked report if the environment is unavailable.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-06 Decision: Defer required platform runtime validation to a later gate.
  - Trigger / new insight: User confirmed runtime validation may be deferred instead of blocking current orchestration.
  - Plan delta (what changed): Wave 2 is complete with explicit validation deferment; Wave 3 may proceed, but it must not treat either iOS or Android as runtime-approved.
  - Tradeoffs considered: Deferring runtime validation allows planning and implementation scaffolding to continue from API-surface evidence, while preserving the release risk that wake reliability, lock/terminated behavior, permissions, full-screen stop UI, and reboot restore are still unverified.
  - User approval: yes.

- 2026-07-06 Decision: Treat Wave 2 as blocked until external platform runtime evidence exists.
  - Trigger / new insight: Both platform spike PRs merged blocker evidence, but neither platform has required runtime proof: iOS lacks an iOS 26+ real device/compatible runtime and Android lacks an API 36 device/emulator/SDK plus installable target.
  - Plan delta (what changed): Wave 2 was marked blocked until the external validation decision was resolved; superseded on 2026-07-06 by the user-approved runtime-validation deferment.
  - Tradeoffs considered: Preserving the merged API-surface notes helps later implementation planning, while marking the wave blocked prevents documentation-only evidence from being mistaken for production feasibility.
  - User approval: superseded by deferment approval.

- 2026-07-06 Decision: Treat Android spike as blocked until API 36 runtime evidence exists.
  - Trigger / new insight: Worker recorded Android API 36 runtime validation as unavailable because no device/emulator, no AVD, no android-36 platform/system image, and no repository Android app target were present.
  - Plan delta (what changed): Task_2 evidence is integrated as blocked; Android MVP approval remains dependent on API 36 runtime validation of alarm delivery, permissions, lock/terminated behavior, full-screen stop UI, cancel semantics, and reboot restore.
  - Tradeoffs considered: Merging blocker evidence captures the likely design direction (`setAlarmClock`, full-screen notification/native stop Activity, PendingIntent-per-occurrence, permission checks, BootReceiver restore) without converting API/documentation evidence into runtime approval.
  - User approval: orchestrator-approved as blocked evidence integration.

- 2026-07-06 Decision: Treat iOS spike as blocked until real-device/runtime evidence exists.
  - Trigger / new insight: Worker could typecheck the AlarmKit API surface against iPhoneOS 26.5 SDK but had no iOS 26+ real device or compatible simulator/runtime, and the repository has no installable `ios/` target.
  - Plan delta (what changed): Task_1 evidence is integrated as blocked; Wave 2 continues with Android Task_2 while iOS runtime validation remains a prerequisite for iOS MVP approval and Wave 3 platform decision.
  - Tradeoffs considered: Merging the blocker evidence preserves decision-quality API notes and missing validation details, while avoiding a false completion signal.
  - User approval: orchestrator-approved as blocked evidence integration.

- 2026-07-06 Decision: Execute Wave 2 platform spikes serially by PR.
  - Trigger / new insight: Task_1 and Task_2 both need to update `docs/spikes/native-alarm-feasibility.md`, so parallel workers would have overlapping ownership despite separate platform code directories.
  - Plan delta (what changed): Start iOS Task_1 first; start Android Task_2 after the iOS spike PR is merged, blocked, or otherwise integrated.
  - Tradeoffs considered: Serial execution reduces merge conflicts and evidence overwrites; it delays Android start but preserves a single authoritative evidence template.
  - User approval: orchestrator-approved to preserve ownership isolation.

- 2026-07-05 Decision: Run iOS and Android spikes in parallel.
  - Trigger / new insight: ownsは`ios/**`と`android/**`で分離でき、同じテンプレートへ結果を記録するだけで競合リスクが低い。
  - Plan delta (what changed): Wave 2内に2つのparallel research tasksを配置した。
  - Tradeoffs considered: 共通テンプレートへの同時編集競合はあるため、各platform sectionを分ける。
  - User approval: pending.

## Notes

- Risks:
  - Simulator/Emulatorではlock screenやFocusの実態が不十分な可能性がある。
  - Android OEM差分はMVP前に全網羅できない。
