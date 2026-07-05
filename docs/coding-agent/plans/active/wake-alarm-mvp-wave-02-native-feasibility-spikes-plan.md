# Plan: Wake Alarm MVP Wave 2 - Native Alarm Feasibility Spikes

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-05
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

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Run iOS and Android spikes in parallel.
  - Trigger / new insight: ownsは`ios/**`と`android/**`で分離でき、同じテンプレートへ結果を記録するだけで競合リスクが低い。
  - Plan delta (what changed): Wave 2内に2つのparallel research tasksを配置した。
  - Tradeoffs considered: 共通テンプレートへの同時編集競合はあるため、各platform sectionを分ける。
  - User approval: pending.

## Notes

- Risks:
  - Simulator/Emulatorではlock screenやFocusの実態が不十分な可能性がある。
  - Android OEM差分はMVP前に全網羅できない。
