# Plan: Wake Alarm MVP Wave 8 - Scheduling, Native Bridges, and Calendar Core

- status: in progress
- generated: 2026-07-05
- last_updated: 2026-07-06
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
  - `.github/workflows/**`
  - `integration_test/**`
  - `test_driver/**`
  - `docs/qa/ci-native-smoke.md`
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
- A8: Wave 3 approves implementation from API-surface evidence only; native bridge work must keep iOS 26+ and Android API 36 runtime reliability unapproved until manual evidence passes.
- A9: OS recurrence is not the MVP source of truth; bridge tasks schedule concrete occurrences and persist one platform alarm identity per occurrence.
- A10: Optional runtime checks are optional only for device execution; each unavailable runtime case still requires an explicit QA checklist row with PASS or BLOCKED status.
- A11: CI simulator/emulator smoke is useful immediately after native bridge implementation to catch build/install/platform-channel regressions, but hosted simulator/emulator evidence is NEAR_DEVICE or BLOCKED and does not approve deferred real-device runtime cases.
- A12: Wave 7 owns ordinary baseline CI for format/analyzer/unit tests; Wave 8 native smoke CI must extend or coexist with it rather than replacing it.

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
  - iOS 26+ runtime validation status is recorded in the QA checklist; missing device/runtime evidence remains release-blocking and is not treated as platform approval.
  - QA checklist includes explicit PASS or BLOCKED rows for iOS runtime cases even when the iOS 26+ runtime is unavailable.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test"
  - kind: manual
    required: false
    owner: worker
    detail: "iOS 26以上環境が利用可能な場合はテストアラーム、複数Occurrence、個別cancel、plan cancelを確認する。実行できない場合もQA checklistへ該当caseごとのBLOCKED rowを必ず記録し、Wave 8 completionやrelease approvalとは扱わない"
  - kind: review
    required: true
    owner: worker
    detail: "docs/qa/ios-alarmkit-checklist.mdにiOS runtime casesごとのPASSまたはBLOCKED rowがあることを確認する。device実行可否とは独立した必須evidence step"
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
  - Android API 36 runtime validation status is recorded in the QA checklist; missing device/runtime evidence remains release-blocking and is not treated as platform approval.
  - QA checklist includes explicit PASS or BLOCKED rows for Android runtime cases even when the Android API 36 runtime is unavailable.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test"
  - kind: manual
    required: false
    owner: worker
    detail: "Android API 36環境が利用可能な場合はテストアラーム、複数Occurrence、個別cancel、plan cancel、再起動後再予約を確認する。実行できない場合もQA checklistへ該当caseごとのBLOCKED rowを必ず記録し、Wave 8 completionやrelease approvalとは扱わない"
  - kind: review
    required: true
    owner: worker
    detail: "docs/qa/android-alarm-checklist.mdにAndroid runtime casesごとのPASSまたはBLOCKED rowがあることを確認する。device実行可否とは独立した必須evidence step"
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

### Task_5: CI Simulator/Emulator Native Smoke Harness
- type: chore
- owns:
  - `.github/workflows/**`
  - `integration_test/**`
  - `test_driver/**`
  - `docs/qa/ci-native-smoke.md`
  - `docs/qa/artifacts/**`
- depends_on:
  - Task_2
  - Task_3
- description: |
  Implement CI-backed near-device smoke checks as soon as native bridge code exists, so Android Emulator / iOS Simulator build, install, platform-channel, schedule/cancel, permission/capability, and log collection regressions surface before final QA.
- acceptance:
  - GitHub Actions workflow exists for manual dispatch and PR/scheduled smoke where practical.
  - Android job uses an emulator image closest to the MVP target available in CI, preferring API 36 when available and recording BLOCKED/unavailable evidence when not available.
  - iOS job uses a macOS runner and simulator/runtime closest to the MVP target available in CI, preferring an iOS 26+ runtime when available and recording BLOCKED/unavailable evidence when not available.
  - CI runs Flutter dependency resolution, build/install or integration-test smoke, and platform-channel/native alarm gateway smoke for schedule/cancel/test-alarm paths where simulator/emulator supports them.
  - CI keeps the Wave 7 baseline validation path for format, analyzer/lint, and unit tests intact.
  - Existing baseline CI warnings are addressed when they fall within `.github/workflows/**`, including the `actions/upload-artifact@v4` Node.js 20 deprecation warning observed on the `Format, analyze, and test` job; update or replace action pins only after verifying the current supported action/runtime path, and preserve artifact upload behavior.
  - CI uploads logs/artifacts such as Flutter test logs, Android `adb` logs, optional `dumpsys alarm`, iOS `simctl` logs, screenshots when available, and a summary under `docs/qa/ci-native-smoke.md`.
  - CI evidence labels simulator/emulator results as NEAR_DEVICE or BLOCKED, never as real-device APPROVED for wake delivery, lock/terminated behavior, Silent/Focus behavior, full-screen stop UI, or Android reboot restore.
  - If hosted runner SDK/runtime limitations prevent a meaningful iOS/Android smoke, the workflow still records the exact unavailable runner/runtime/toolchain fact and leaves the corresponding release gate BLOCKED.
- validation:
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
    detail: "GitHub Actions workflow is syntax-checked and either runs the simulator/emulator smoke successfully or records precise BLOCKED evidence for unavailable hosted runtimes"
  - kind: ci
    required: true
    owner: worker
    detail: "Baseline CI artifact upload no longer emits the observed Node.js 20 deprecation warning, or the PR records a precise upstream/action-version blocker if no supported fix is available yet"
  - kind: review
    required: true
    owner: worker
    detail: "After worker self-review, independent review, and any review-driven fixes are complete, rerun `rtk gh-review-hook <PR_NUMBER>` from the worker worktree and report hook exit 0 for the final reviewed head SHA"
  - kind: review
    required: true
    owner: reviewer
    detail: "CI smoke evidence is clearly separated from real-device runtime approval and cannot mark deferred Wave 3 cases APPROVED"

### Task_6: Wave 8 Whole Codebase Review and Fix Loop
- type: review
- owns:
  - docs/coding-agent/plans/active/wake-alarm-mvp-wave-08-scheduling-native-calendar-plan.md
  - docs/coding-agent/plans/active/wake-alarm-mvp-implementation-plan.md
- depends_on:
  - Task_1
  - Task_2
  - Task_3
  - Task_4
  - Task_5
- description: |
  After Wave 8 implementation and CI smoke tasks land, run an integrated review across the current codebase and Wave 8 evidence. This is an orchestrator/reviewer closeout loop, not product-code implementation in the parent thread; any fixes must be delegated as narrow worker tasks or handled by the owning worker/PR before the wave is marked complete.
- acceptance:
  - Existing codebase is reviewed across Wake Plan scheduling, repository/domain interactions, MethodChannel contract, iOS bridge, Android bridge, week calendar, CI workflows, and QA docs.
  - Review explicitly checks for stale native alarms, duplicate/uncancelled occurrences, platformAlarmId persistence, MethodChannel schema drift, native checklist honesty, baseline CI preservation, and release-blocking runtime validation wording.
  - Every in-scope finding is fixed through a worker PR or documented as an explicit deferred/out-of-scope decision with rationale.
  - The review/fix loop repeats until the final orchestrator/reviewer pass reports no in-scope findings.
  - Wave 8 is not moved to `docs/coding-agent/plans/completed/` until this loop and all required Task_1-Task_5 validation are complete.
- validation:
  - kind: review
    required: true
    owner: orchestrator
    detail: "Run and record a codebase-wide Wave 8 closeout review; if findings exist, do not close the wave and delegate fixes."
  - kind: review
    required: true
    owner: reviewer
    detail: "Independent reviewer confirms no remaining in-scope Wave 8 integration findings after fixes."

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1, Task_2, Task_3, Task_4]
- Wave 2 (parallel): [Task_5]
- Wave 3 (parallel): [Task_6]

## E2E / Visual Validation Spec

- provider: playwright-cli for Flutter web smoke where applicable; iOS/Android simulator or実機 manual evidence for native alarm behavior.
- artifact_root:
  - `.playwright-cli/`
  - `docs/qa/artifacts/`
- flows:
  - Week calendar renders current week, time grid, current time line, and empty state.
  - Tap a day/time cell and verify date/time conversion.
  - iOS/Android test alarm can be scheduled and cancelled.
  - After Wave 8 implementation tasks complete, review the existing codebase end-to-end for integration, ownership, validation, and deferred-runtime wording regressions; fix or delegate every in-scope finding until the review returns no findings.
- viewports:
  - Mobile compact: 390x844.
  - Mobile large: 430x932.
- evidence_requirements:
  - Screenshots for calendar empty state.
  - Native logs/checklist rows for schedule/cancel when runtime evidence is available.
  - Explicit PASS or BLOCKED checklist rows for every unavailable iOS 26+ / Android API 36 runtime case.

## Rollback / Safety

- Native alarm changes must include cleanup/cancel procedure in QA checklist.
- Calendar code must not assume external calendar permissions.
- Native bridge implementation may proceed without runtime approval, but any unavailable manual runtime cases must remain visible as release blockers.
- Optional runtime checks must never disappear silently; missing devices/runtimes are recorded as BLOCKED checklist rows.

## Handoff To Next Wave

- Wave 9 builds WakePlan block rendering and settings defaults on top of this wave.
- Wave 10 uses scheduling service and calendar tap interaction for create flow.

## Progress Log (append-only)

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness returned after Android timeout review.
  - PR: #17 `Add native smoke CI harness`, branch `codex/wave-08-ci-native-smoke`, reviewed head `7d5f074a62a5a30d068453251015235bd3585222`.
  - Worker evidence before return: worker validation passed (`rtk flutter analyze`, `rtk flutter test`, `rtk git diff --check`, workflow YAML parse, extracted bash syntax, mutable action/cache scan, Flutter tag check), GitHub Baseline CI/Android smoke/iOS smoke/checks were success, final run-log scan found no `actions/cache` or `subosito/flutter-action`, and worker `rtk gh-review-hook 17` exited 0.
  - Orchestrator validation before return: clean PR-head temp worktree passed `rtk flutter pub get`, `rtk dart format --set-exit-if-changed .`, `rtk flutter analyze`, `rtk flutter test`, `rtk git diff --check`, workflow YAML parse, extracted bash syntax, mutable action/cache scan, Flutter tag check, final GitHub run-log scan, and orchestrator `rtk gh-review-hook 17`.
  - Orchestrator review finding: Android native smoke process execution is not bounded before artifact upload; if `flutter build apk --debug` or Android `flutter test ... -d emulator-5554` hangs, the job-level timeout can cancel before `Upload Android native smoke artifacts`, losing required BLOCKED evidence.
  - Action: worker thread `019f360f-e59c-7440-8c24-9ff9904c1e9d` was asked to add Android process-level timeout handling around build and smoke test, write BLOCKED hosted-runner evidence on timeout, preserve artifact upload behavior, rerun required checks, and provide refreshed final `rtk gh-review-hook 17` evidence.
  - Merge impact: PR #17 remains unmerged until the Android timeout evidence gap is fixed and the orchestrator reruns review/checks/hook on the new head.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness continued after final hook evidence scan.
  - PR: #17 `Add native smoke CI harness`, branch `codex/wave-08-ci-native-smoke`, reviewed head before continuation `2c71c39019f04b45446bb54cd4d71617b0d15481`.
  - Worker `rtk gh-review-hook 17` exited 0 and GitHub checks were green, but the worker's post-hook GitHub log scan still found runtime download/use of nested mutable `actions/cache@v5` through `subosito/flutter-action`.
  - Action: worker is replacing `subosito/flutter-action` setup blocks with shell-based Flutter SDK setup pinned to the `.fvmrc` version output, then will rerun workflow syntax checks, project validation, GitHub checks, and final `rtk gh-review-hook 17`.
  - Merge impact: PR #17 remains unmerged until the final head proves no nested mutable cache action is downloaded and the orchestrator reruns review/checks/hook.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness returned after final-head orchestrator review.
  - PR: #17 `Add native smoke CI harness`, branch `codex/wave-08-ci-native-smoke`, reviewed head `f419abaf7c44d42cda6975eca2802d0788526b88`.
  - Worker evidence before return: worker validation passed (`rtk flutter analyze`, `rtk flutter test`, `rtk git diff --check`, workflow YAML parse, extracted bash syntax, mutable action scan), GitHub Baseline CI/Android smoke/iOS smoke/checks were success, and worker `rtk gh-review-hook 17` exited 0 on the final head.
  - Orchestrator validation before return: clean PR-head temp worktree passed `rtk flutter pub get`, `rtk flutter analyze`, `rtk flutter test`, `rtk git diff --check`, `rtk dart format --set-exit-if-changed .`, workflow YAML parse, extracted bash syntax, mutable action scan, and `rtk gh-review-hook 17`.
  - Orchestrator review finding: `.github/workflows/baseline-ci.yml` and `.github/workflows/native-smoke.yml` SHA-pin `subosito/flutter-action`, but `cache: true` causes the pinned composite action to execute mutable `actions/cache@v5` internally at runtime.
  - Action: worker thread `019f360f-e59c-7440-8c24-9ff9904c1e9d` was asked to remove or replace the mutable nested cache path while preserving CI behavior, rerun required checks and final `rtk gh-review-hook 17`, and report a refreshed merge-ready handoff.
  - Runtime status: hosted CI evidence remains NEAR_DEVICE/BLOCKED only and does not approve iOS 26+ or Android API 36 real-device release gates.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness returned after orchestrator review.
  - PR: #17 `Add native smoke CI harness`, branch `codex/wave-08-ci-native-smoke`, reviewed head `304ad085e2390126bdca873f6caefbdc56d61508`.
  - Worker evidence before return: worker validation passed (`rtk flutter analyze`, `rtk flutter test`, `rtk git diff --check`, workflow YAML parse, extracted bash syntax, mutable action scan), GitHub Baseline CI/Android smoke/iOS smoke/checks were success, and worker `rtk gh-review-hook 17` exited 0.
  - Orchestrator validation before return: clean PR-head temp worktree passed `rtk flutter pub get`, `rtk flutter analyze`, `rtk flutter test`, `rtk git diff --check`, workflow YAML parse, extracted bash syntax, mutable action scan, and `rtk gh-review-hook 17`.
  - Orchestrator review findings: iOS smoke could publish `NEAR_DEVICE` even when schedule/test-alarm operations failed with permission/unavailable paths; Native Smoke CI `pull_request.paths` omitted `.fvmrc`, `pubspec.yaml`, and `pubspec.lock` even though the workflow depends on them.
  - Action: worker thread `019f360f-e59c-7440-8c24-9ff9904c1e9d` was asked to fix the evidence-label semantics and path filters, rerun required checks and final `rtk gh-review-hook 17`, and report a refreshed merge-ready handoff.
  - Runtime status: hosted CI evidence remains NEAR_DEVICE/BLOCKED only and does not approve iOS 26+ or Android API 36 real-device release gates.

- 2026-07-06 Worker-side post-review gh-review-hook requirement clarified.
  - Trigger: User clarified that after review completes, `gh-review-hook` must also be run from the worker worktree.
  - Action: Task_5 validation now explicitly requires worker-side `rtk gh-review-hook <PR_NUMBER>` after self-review, independent review, and review-driven fixes are complete.
  - Merge gate impact: Orchestrator must reject merge-ready handoffs whose hook evidence is not from the final reviewed head SHA.

- 2026-07-06 Baseline CI Node.js 20 deprecation warning added to Task_5 scope.
  - Trigger: GitHub Actions `Format, analyze, and test` emitted a warning that `actions/upload-artifact@v4` targets Node.js 20 and is being forced to Node.js 24.
  - Action: Task_5 now explicitly owns fixing or precisely documenting this workflow warning because it already owns `.github/workflows/**` and must preserve Wave 7 baseline CI while adding native smoke CI.
  - Validation impact: Task_5 worker must verify the current supported action/runtime path before changing action pins, preserve artifact upload behavior, and provide CI/syntax evidence that the warning is gone or record a concrete upstream blocker.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness delegated.
  - Task_5 pending worktree: `local:d74c6506-5d51-4135-936d-0efe755d9012`.
  - Task_5 Branch: `codex/wave-08-ci-native-smoke`.
  - Task_5 Scope: `.github/workflows/**`, `integration_test/**`, `test_driver/**`, `docs/qa/ci-native-smoke.md`, and `docs/qa/artifacts/**`.
  - Context: Task_1 scheduling service, Task_2 iOS bridge, Task_3 Android bridge, and Task_4 week calendar core are merged; CI smoke evidence must be NEAR_DEVICE or BLOCKED and cannot approve deferred real-device runtime cases.
  - Validation ownership: worker must provide analyzer/test/diff checks, workflow syntax validation or exact unavailable-tool evidence, independent review, PR hook evidence, and a merge-ready or blocked report without merging.

- 2026-07-06 Wave 8 Task_3 Android Alarm Bridge merged.
  - Summary: PR #16 `Add Android alarm bridge` was squash-merged, adding the Kotlin MethodChannel bridge, AlarmManager/setAlarmClock scheduling and cancel paths, receiver/full-screen stop fallback, boot/package-replace restore path, Android manifest permissions/components, and Android QA checklist rows.
  - Merge commit: `c75be241db1bb2d1e4ae39144bbd439ad55186d7`.
  - Validation evidence: Worker `rtk flutter build apk --debug`, `rtk flutter test`, `rtk flutter analyze`, `rtk git diff --check`, and `rtk gh-review-hook 16` passed after the final durable mirror-write fix and latest base merge; orchestrator reran the same build/test/analyze/diff checks and `rtk gh-review-hook 16` from a clean PR-head worktree, and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved after fixing PendingIntent identity collision risk; orchestrator returned the PR once for asynchronous `SharedPreferences.apply()` mirror writes, then re-reviewed the commit-based store fix and found no remaining actionable findings.
  - Runtime status: Android API 36 runtime/device validation remains BLOCKED/deferred and release-blocking; Wave 8 implementation evidence does not approve Android runtime reliability.
  - PR state: #16 merged; branch head `c66fe594e6b708c1a9b611323da2c3ba226c9428`.

- 2026-07-06 Wave 8 Task_1 Wake Plan Scheduling Service merged.
  - Summary: PR #15 `Add wake plan scheduling service` was squash-merged, adding WakePlan create/edit/delete/skip scheduling flows, rolling concrete occurrence generation, NativeAlarmGateway schedule/cancel integration, platformAlarmId persistence, warning-ready failure results, and focused service tests.
  - Merge commit: `50b0061ed2900dd9baec5889263acd0fa3e0273d`.
  - Validation evidence: Worker `rtk flutter test test/features/wake_plan/application/wake_plan_service_test.dart`, `rtk flutter analyze`, `rtk git diff --check`, PR Baseline CI, and `rtk gh-review-hook 15` passed; orchestrator reran the focused service test, analyzer, diff check, and `rtk gh-review-hook 15` from a clean PR-head worktree, and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved after lifecycle fixes; orchestrator performed a final scheduling-service review before merge and found no actionable findings.
  - Runtime status: This service task does not claim iOS 26+ or Android API 36 runtime alarm validation; deferred runtime validation remains unapproved and release-blocking.
  - PR state: #15 merged; branch head `30e41f150f494071bcdb0217e575a984dc2a0e83`.

- 2026-07-06 Wave 8 Task_3 Android Alarm Bridge returned after orchestrator review.
  - Trigger: Orchestrator final review of PR #16 found that `AlarmStore.put` and `AlarmStore.remove` used asynchronous `SharedPreferences.apply()`, allowing schedule/cancel to report success before the reboot-restore mirror state was durable.
  - Risk: A process death immediately after cancel success could leave a removed `platformAlarmId` on disk and allow `BootReceiver`/`AlarmRestore` to restore a canceled alarm; a process death after schedule success could also lose restore state.
  - Action: Worker thread `019f35da-44bb-7a30-bb40-9d7ea9fb36b6` was instructed to make mirror writes durable or fail the native operation, rerun required validation and `rtk gh-review-hook 16`, and report an updated merge-ready head without merging.
  - Runtime status: Android API 36 runtime alarm validation remains deferred and unapproved.

- 2026-07-06 Wave 8 Task_4 Week Calendar Grid and Interaction Core merged.
  - Summary: PR #13 `Add week calendar interaction core` was squash-merged, adding the Wake Plan week calendar interaction model, week grid widget, current-time line, initial scroll behavior, tap-to-day/time conversion, compact scaffold placeholder, and focused model/widget tests.
  - Merge commit: `91d5a3b43512187c56b7e0bc42c94837dcf498d3`.
  - Validation evidence: Worker `rtk flutter test test/features/week_calendar`, `rtk flutter analyze`, `rtk git diff --check`, and PR Baseline CI passed; orchestrator reran `rtk flutter test test/features/week_calendar`, `rtk flutter analyze`, `rtk git diff --check origin/master...HEAD`, and `rtk gh-review-hook 13` from a clean PR-head worktree, and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved; orchestrator performed a final UI/model/tests review before merge and found no actionable findings.
  - Runtime status: This calendar task does not claim iOS 26+ or Android API 36 runtime alarm validation; deferred runtime validation remains unapproved and release-blocking.
  - PR state: #13 merged; branch head `4ee13efd7994d4b40b4523d35d94bc7b37306b01`.

- 2026-07-06 Wave 8 codebase-wide closeout review added.
  - Summary: Added Task_6 so Wave 8 cannot close until the existing codebase receives an integrated review/fix loop after scheduling/native/calendar/CI smoke tasks land.
  - Impact: In-scope findings from the review must be fixed through worker PRs or explicitly deferred before moving the Wave 8 plan to `completed/`.

- 2026-07-06 Wave 8 Task_2 iOS AlarmKit Bridge merged.
  - Summary: PR #14 `Add iOS AlarmKit native bridge` was squash-merged, adding Swift AlarmKit MethodChannel bridge wiring for `net.xpadev.calarm/native_alarm`, schemaVersion 1 validation, capability/permission/schedule/cancel/test-alarm methods, and iOS QA checklist rows.
  - Merge commit: `b2c6bc2abf181ef1613e5da76d6d5c2281b96dd0`.
  - Validation evidence: Worker `rtk flutter test`, `rtk flutter analyze`, `rtk git diff --check`, and focused Swift bridge typecheck against the iOS 26.5 simulator SDK passed; orchestrator reran `rtk flutter test`, `rtk flutter analyze`, `rtk git diff --check`, focused Swift bridge typecheck, and `rtk gh-review-hook 14` from a clean PR-head worktree, and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved; orchestrator inspected PR metadata, changed-file scope, checklist honesty, and MethodChannel/AlarmKit bridge diff.
  - Runtime status: Full iOS build and iOS 26+ runtime validation remain BLOCKED because the local environment had no eligible iOS 26+ runtime/destination; this remains release-blocking and is not platform approval.
  - PR state: #14 merged; branch head `a694de89cb007d9f431a0ca47e7f739eaa006119`.

- 2026-07-06 Wave 8 Task_3 and Task_4 base update requested after Task_2 merge.
  - Trigger: After PR #14 merged into `master`, parent reran `rtk gh-review-hook 13` and `rtk gh-review-hook 16`; both exited 2 because each PR was 1 commit behind base.
  - Action: Orchestrator instructed Task_3 and Task_4 workers to merge `origin/master` normally, rerun required checks and `rtk gh-review-hook`, push, and report updated merge-ready evidence without merging.
  - Runtime status: Android API 36 and iOS 26+ runtime alarm validation remains deferred and unapproved.

- 2026-07-06 Wave 8 Task_1-Task_4 delegated in parallel.
  - Task_1 Wake Plan Scheduling Service thread: `019f35cb-2642-7551-be9f-e35b60b5b1cf`; pending worktree: `local:8d7aeb74-f56b-4b33-8bbb-cac5f548ad7c`.
  - Task_1 Branch: `codex/wave-08-wake-plan-scheduling-service`.
  - Task_1 Scope: `lib/features/wake_plan/application/wake_plan_service.dart` and `test/features/wake_plan/application/wake_plan_service_test.dart`.
  - Task_1 follow-up: worker initially reported missing owned files as a blocker; orchestrator clarified that Task_1 owns creating those files from scratch and instructed the worker to continue.
  - Task_2 iOS AlarmKit Bridge pending worktree: `local:12fa1eed-c1c5-4ee1-97d1-bd3f7ba3df0c`.
  - Task_2 Branch: `codex/wave-08-ios-alarmkit-bridge`.
  - Task_2 Scope: `ios/**` and `docs/qa/ios-alarmkit-checklist.md`.
  - Task_3 Android Alarm Bridge pending worktree: `local:96734e84-dcc8-4f8d-96dd-f1be47d01269`.
  - Task_3 Branch: `codex/wave-08-android-alarm-bridge`.
  - Task_3 Scope: `android/**` and `docs/qa/android-alarm-checklist.md`.
  - Task_4 Week Calendar Grid and Interaction Core pending worktree: `local:a1efcac4-d9ac-4d4c-9f57-e453358c73d2`.
  - Task_4 Branch: `codex/wave-08-week-calendar-core`.
  - Task_4 Scope: `lib/features/week_calendar/**` and `test/features/week_calendar/**`.
  - Validation ownership: each worker must provide focused required validation, independent review, PR hook evidence, and a merge-ready or blocked report without merging. iOS 26+ and Android API 36 runtime validation remains deferred and unapproved.

- 2026-07-06 CI near-device smoke harness added to Wave 8.
  - Summary: Add Task_5 after iOS/Android native bridge tasks so CI simulator/emulator smoke is implemented before final QA.
  - Release impact: CI evidence can be NEAR_DEVICE or BLOCKED, but cannot approve deferred real-device runtime cases.

- 2026-07-06 Baseline CI dependency clarified.
  - Summary: Wave 8 native smoke CI must coexist with the earlier Wave 7 baseline CI for format, analyzer/lint, and unit tests.
  - Impact: Native smoke workers should add smoke-specific jobs or workflows without removing ordinary PR validation.

- 2026-07-06 Wave 3 decision integrated.
  - Native bridges must use rolling concrete occurrence reservations and one platform alarm identity per occurrence.
  - iOS/Android manual validation in this wave is optional implementation evidence when a matching runtime is available; if unavailable, the checklist records explicit BLOCKED rows and later release gates remain blocked.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-06 Decision: Preserve deferred runtime approval in native bridge validation.
  - Trigger / new insight: Wave 3 permits implementation from API-surface evidence but does not approve iOS/Android runtime reliability.
  - Plan delta (what changed): iOS and Android bridge acceptance now requires QA checklist status rather than runtime execution; blocked runtime cases remain release blockers but do not block Wave 8 completion.
  - Tradeoffs considered: Workers can implement the bridge without unavailable devices, while final release gates still require real runtime evidence.
  - User approval: yes, from Wave 3 deferment.

- 2026-07-06 Decision: Implement CI simulator/emulator smoke as early as native bridges exist.
  - Trigger / new insight: User noted that near-device CI should be done as early as it can be inserted.
  - Plan delta (what changed): Wave 8 now has Task_5 after iOS/Android bridge tasks, owning GitHub Actions workflow, integration smoke tests, and CI evidence docs.
  - Tradeoffs considered: Earlier CI catches native bridge integration regressions before final QA, but Task_5 waits for Task_2/Task_3 because meaningful platform smoke needs native bridge code.
  - User approval: yes.

- 2026-07-06 Decision: Preserve baseline CI while adding native smoke CI.
  - Trigger / new insight: User asked to add ordinary CI checks in addition to near-device CI.
  - Plan delta (what changed): Wave 8 Task_5 now explicitly preserves the Wave 7 baseline validation path while adding simulator/emulator native smoke coverage.
  - Tradeoffs considered: Keeping the workflows separate or clearly layered prevents native smoke runtime limitations from blocking or hiding ordinary PR checks.
  - User approval: yes.

- 2026-07-06 Decision: Add Wave 8 integrated codebase review before closing the wave.
  - Trigger / new insight: User requested a whole-codebase review around Wave 8 completion, with fixes repeated until review findings are gone.
  - Plan delta (what changed): Added Task_6 after Task_1-Task_5 to require orchestrator/reviewer closeout review and delegated fixes before Wave 8 can move to `completed/`.
  - Tradeoffs considered: This adds one review/fix loop before proceeding to later UI flows, but it should catch cross-task integration drift while the scheduling/native/calendar changes are still fresh.
  - User approval: yes.

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
  - Native manual validation may remain BLOCKED until later device/runtime availability, which blocks release approval but not Wave 8 implementation completion.
