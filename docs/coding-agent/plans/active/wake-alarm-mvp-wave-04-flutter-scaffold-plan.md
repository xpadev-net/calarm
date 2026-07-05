# Plan: Wake Alarm MVP Wave 4 - Flutter Project Scaffold

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-05
- work_type: code

## Goal

- Flutterアプリの最小構成を作成し、後続waveが分担しやすいディレクトリ境界と検証コマンドを用意する。

## Definition of Done

- Flutterアプリが起動可能で、`flutter analyze` と `flutter test` が実行できる。
- `lib/core/` と `lib/features/` の基本構成がある。
- `wake_plan`、`week_calendar`、`alarm_ringing`、`settings` のfeature境界が用意されている。

## Scope / Non-goals

- Scope:
  - `pubspec.yaml`
  - `analysis_options.yaml`
  - `lib/main.dart`
  - `lib/app.dart`
  - `lib/core/**`
  - `lib/features/**`
  - `test/**`
  - `ios/**`
  - `android/**`
- Non-goals:
  - Domain rulesやnative alarm production実装。
  - 完成UI。

## Context (workspace)

- Related files/areas:
  - Wave 3 platform decision.
- Existing patterns or references:
  - 新規Flutter projectとして作成する想定。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: App iconやsplash assetsをMVP scaffoldに含めるか。
- Q2: Flutter stable version更新の運用を手動にするか、toolingで検出するか。
- Q3: scaffold時点で追加するRiverpod/Drift周辺packageの最小セットをどこまでにするか。

## Assumptions

- A1: 状態管理はRiverpodを採用する。
- A2: ローカル永続化はDriftを採用する。
- A3: MVP scaffoldのapplication id/package nameは`dev.xpa.calarm`に固定する。
- A4: Flutter SDK固定は`.fvmrc`で行う。
- A5: iOS display name / Android app label は`Calarm`に固定する。
- A6: Drift/Riverpod関連packageはscaffold時点で追加する。
- A7: `.fvmrc`には実装時点のローカル`flutter --version`のstable versionを固定する。

## Tasks

### Task_1: Flutter Project Scaffold
- type: chore
- owns:
  - pubspec.yaml
  - analysis_options.yaml
  - lib/main.dart
  - lib/app.dart
  - lib/core/**
  - lib/features/**
  - test/**
  - ios/**
  - android/**
- depends_on: []
- description: |
  Original Task_5. Flutterアプリの最小構成を作成し、後続タスクが分担しやすいディレクトリ境界を用意する。
- acceptance:
  - Flutterアプリが起動できる。
  - `lib/core/` と `lib/features/` の基本構成がある。
  - `wake_plan`、`week_calendar`、`alarm_ringing`、`settings` のfeatureディレクトリがある。
  - iOS/AndroidプロジェクトがFlutterからビルド対象として存在する。
  - iOS bundle id / Android application id が`dev.xpa.calarm`で揃っている。
  - `.fvmrc`でFlutter SDK versionを固定できる。
  - iOS display name / Android app label が`Calarm`で揃っている。
  - Riverpod/Drift関連packageが追加され、後続waveで導入しやすいapp bootstrapとdirectory boundaryになっている。
  - Test placeholderがあり、後続waveで追加されるunit/widget testsが同じ規約で置ける。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter analyze"
  - kind: command
    required: true
    owner: worker
    detail: "flutter test"
  - kind: review
    required: true
    owner: reviewer
    detail: "後続waveのowns境界とディレクトリ構成が合っているかレビューする"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]

## Rollback / Safety

- Scaffoldで生成された不要ファイルは後続wave前に整理する。
- 既存ファイルがあった場合は上書きせず、差分を確認してreplanする。

## Handoff To Next Wave

- Wave 5は`lib/core/time/**`と`test/core/time/**`を使う。
- Wave 6以降はfeature directory boundaryを前提にする。

## Progress Log (append-only)

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Keep scaffold as a single gate.
  - Trigger / new insight: 後続waveはFlutter project structureに依存する。
  - Plan delta (what changed): Scaffoldを単独waveにした。
  - Tradeoffs considered: 並列化できないが、以後のowns境界が安定する。
  - User approval: pending.

- 2026-07-05 Decision: Use Riverpod, Drift, and `dev.xpa.calarm` for MVP scaffold defaults.
  - Trigger / new insight: User requested applying the recommended decisions.
  - Plan delta (what changed): Wave 4 now fixes state management, local persistence direction, and provisional app/package id.
  - Tradeoffs considered: `dev.xpa.calarm` avoids a throwaway example namespace and can be used consistently across iOS and Android.
  - User approval: yes.

- 2026-07-05 Decision: Replace recommended placeholder package name with user-provided namespace.
  - Trigger / new insight: User specified `dev.xpa.calarm`.
  - Plan delta (what changed): Wave 4 scaffold requirements now use `dev.xpa.calarm` for iOS bundle id and Android application id.
  - Tradeoffs considered: A real namespace is better than a placeholder because native entitlements, app data, and QA artifacts can remain stable.
  - User approval: yes.

- 2026-07-05 Decision: Use `.fvmrc` and `Calarm` for scaffold identity.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 4 now requires Flutter SDK pinning via `.fvmrc` and app labels/display names set to `Calarm`.
  - Tradeoffs considered: `.fvmrc` is Flutter-specific and lightweight; the app label can be changed later without disturbing package identity.
  - User approval: yes.

- 2026-07-05 Decision: Add Riverpod/Drift packages during scaffold and pin local Flutter stable.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 4 now requires adding Riverpod/Drift dependencies during scaffold and populating `.fvmrc` from the local `flutter --version` stable version.
  - Tradeoffs considered: Adding packages early makes later waves simpler; pinning the local stable version avoids guessing a version in the plan.
  - User approval: yes.

## Notes

- Risks:
  - Flutter SDKやiOS/Android SDKがローカルに未設定の可能性がある。
