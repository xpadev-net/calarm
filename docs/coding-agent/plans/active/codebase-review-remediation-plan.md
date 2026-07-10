# Plan: Codebase Deep-Review Remediation

- status: approved
- generated: 2026-07-10
- last_updated: 2026-07-10
- work_type: code
- orchestrator_model_policy: `gpt-5.6-luna` / `xhigh` for every worker start, resume, and replacement

## Goal

- Remediate every confirmed actionable finding from the 2026-07-10 whole-codebase deep review without implementing product code in the parent thread.
- Deliver small, independently reviewed PRs, merged only after worker and orchestrator validation gates pass.
- Restore reliable alarm scheduling across Dart, Android, and iOS while preserving explicit failure semantics and release-blocking real-device gates.

## Definition of Done

- Tasks 1-14 are merged with current validation, independent review, worker `gh-review-hook` exit 0, orchestrator deep-review, orchestrator hook exit 0, and clean merge state.
- Task 15 harmonization passes full format/analyze/test and Android build checks; iOS compile validation is pass or explicitly blocked only by a recorded local platform limitation with remote CI evidence.
- No confirmed deep-review finding remains unowned.
- Existing real-device iOS 26+ and Android API 36 release gates remain truthfully BLOCKED until Task 16 receives user-owned device evidence.
- Every worker thread is archived after merge or an explicit stopped/split decision.

## Scope / Non-goals

- Scope:
  - iOS AlarmKit authorization configuration.
  - Android alarm identity, permission, vibration, reboot, and Direct Boot behavior.
  - Flutter home responsiveness and deterministic clock injection.
  - Rolling schedule replenishment, mutation compensation, idempotent retry, native/Drift reconciliation, and ringing state.
  - Repository-generated-file ignore hygiene.
- Non-goals:
  - New alarm features, custom sounds, snooze, stop-all, calendar integrations, or release-signing setup.
  - Relabeling simulator/emulator evidence as real-device approval.
  - Broad refactors not required by a confirmed finding.

## Context

- Source review: parent thread whole-codebase `$deep-review` on 2026-07-10.
- Existing release gate: `docs/qa/release-readiness.md` is BLOCKED for real-device evidence.
- Repository rules: `docs/coding-agent/rules/**` is absent; validation is inferred from `.github/workflows/baseline-ci.yml`, `.github/workflows/native-smoke.yml`, and repository QA docs.
- Research waived: the immediately preceding deep review mapped the architecture, reproduced the two failing tests, verified Android build, and grounded every task below to current source.
- Repository owner: `xpadev-net`; autonomous worker PR creation and orchestrator merge are allowed.
- Parent implementation boundary: the parent may mutate only this ledger/plan and perform orchestrator-owned GitHub merge/archive actions.

## Quality Routing

- Routing level: L3.
- In scope: Flutter/Dart, Kotlin/Android, Swift/AlarmKit, MethodChannel contracts, SQLite/Drift state, lifecycle/retry/idempotency, UI layout, platform permissions.
- Out of scope quality docs: Rust, TypeScript/JavaScript, Python, Go, and web-framework gates because those stacks are absent.
- Top risks: data integrity, ordering/concurrency, cross-platform contract drift, untracked native side effects, permission/reboot recovery, user-visible alarm failure.

## Tasks

### Task_1: Add required iOS AlarmKit usage description

- status: unstarted
- type: impl
- owns:
  - `ios/Runner/Info.plist`
  - `ios/RunnerTests/**` only for configuration regression coverage
- depends_on: [Task_4]
- acceptance:
  - `NSAlarmKitUsageDescription` is non-empty, user-facing, and consistent with Calarm's wake-alarm purpose.
  - A deterministic plist/configuration check fails when the key is missing or blank.
  - No unrelated iOS project or signing changes are included.
- validation:
  - kind: command; required: true; owner: worker; detail: `plutil -lint ios/Runner/Info.plist` plus focused configuration test.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: independent review plus `$deep-review` of the final diff.

### Task_2: Separate Android alarm detail and firing intents; honor vibration

- status: unstarted
- type: impl
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt`
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmReceiver.kt`
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmStopActivity.kt`
  - `android/app/src/test/**`
  - `android/app/build.gradle.kts` only if narrowly required for native tests
- depends_on: [Task_4]
- acceptance:
  - `AlarmClockInfo.showIntent` opens a non-ringing detail surface and cannot start sound/vibration or mutate the scheduled alarm.
  - The operation PendingIntent remains the only time-triggered firing path.
  - Firing reads the persisted request and never vibrates when `vibrationEnabled` is false.
  - Early detail display does not remove mirror state or leave a second scheduled firing path.
  - Regression tests cover early showIntent send, scheduled fire, stop, and vibration on/off.
- validation:
  - kind: command; required: true; owner: worker; detail: focused Android native tests.
  - kind: command; required: true; owner: worker; detail: `flutter build apk --debug`, `flutter analyze`, `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: Android lifecycle/security review and `$deep-review`.

### Task_3: Make the Flutter home layout responsive after async load

- status: unstarted
- type: impl
- owns:
  - `lib/app.dart`
  - `lib/features/settings/presentation/settings_placeholder.dart`
  - `test/app_scaffold_test.dart`
  - `test/features/settings/presentation/settings_placeholder_test.dart`
- depends_on: [Task_4]
- acceptance:
  - The loaded home screen has no vertical RenderFlex overflow on compact portrait and landscape constraints.
  - Calendar, ringing, settings, and wake-plan surfaces remain reachable through an intentional scroll/flex structure.
  - Async loading, error, and loaded states have regression tests that call `pumpAndSettle` and assert no framework exception.
  - Existing settings save/error behavior remains unchanged.
- validation:
  - kind: command; required: true; owner: worker; detail: focused app/settings widget tests at compact portrait and landscape sizes.
  - kind: command; required: true; owner: worker; detail: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`.
  - kind: e2e; required: true; owner: reviewer; detail: bounded Flutter widget visual/layout evidence; native/browser screenshot waiver must be explicit if no runnable harness exists.

### Task_4: Propagate the injected clock into wake-plan sheets

- status: in_progress
- worker_thread: `019f4a0e-0e34-7193-b3ec-f42d6216acfb`
- worker_branch: `codex/reviewfix-clock-injection`
- worker_runtime: `gpt-5.6-luna` / `xhigh`
- type: test
- owns:
  - `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`
  - `lib/features/wake_plan/ui/wake_plan_detail_sheet.dart`
  - `test/features/week_calendar/presentation/week_calendar_placeholder_test.dart`
  - `test/features/wake_plan/ui/wake_plan_detail_sheet_test.dart`
- depends_on: []
- acceptance:
  - Create/edit sheets use the same injected clock as the calendar and `WakePlanService` for validation.
  - The two currently failing tests pass regardless of wall-clock date.
  - Tests explicitly prove the provider clock, not `DateTime.now`, controls future/past save eligibility.
- validation:
  - kind: command; required: true; owner: worker; detail: run both previously failing tests individually and the full week-calendar test file.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: clock-boundary and test-hermeticity review.

### Task_5: Restore Flutter generated-file ignore hygiene

- status: unstarted
- type: chore
- owns:
  - `.gitignore`
- depends_on: [Task_4]
- acceptance:
  - Standard Flutter/Dart build, tool, IDE, and platform-generated artifacts are ignored without ignoring tracked source/configuration.
  - Existing `.serena` exclusion remains.
  - The change does not remove or rewrite any user-owned untracked file.
- validation:
  - kind: command; required: true; owner: worker; detail: `git check-ignore -v` for `.dart_tool/`, `.flutter-plugins-dependencies`, `build/`, and generated SwiftPM configuration paths.
  - kind: review; required: true; owner: reviewer; detail: verify no source or intended lockfile is over-ignored.

### Task_6: Repair Android exact-alarm, full-screen, and Direct Boot recovery

- status: unstarted
- type: impl
- owns:
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt`
  - `android/app/src/main/kotlin/dev/xpa/calarm/BootReceiver.kt`
  - `android/app/src/test/**`
  - `android/app/build.gradle.kts` only if required for tests
  - `docs/qa/android-alarm-checklist.md` only for changed recovery evidence
- depends_on: [Task_2]
- acceptance:
  - Full-screen access uses `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT` with package URI and a safe fallback.
  - `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` triggers idempotent restore after re-grant.
  - `LOCKED_BOOT_COMPLETED` is actually executable before unlock and reads only device-protected mirror state.
  - Boot, package replacement, permission re-grant, and duplicate broadcasts restore each future alarm once and drop expired entries safely.
  - Tests cover missing permission, re-grant, locked boot, unlocked boot, duplicate delivery, and corrupt mirror rows.
- validation:
  - kind: command; required: true; owner: worker; detail: focused native recovery tests and manifest inspection.
  - kind: command; required: true; owner: worker; detail: `flutter build apk --debug`, `flutter analyze`, `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: Android permission/direct-boot security review.

### Task_7: Add rolling schedule replenishment

- status: unstarted
- type: impl
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `lib/features/wake_plan/application/occurrence_planner.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart`
  - `lib/core/bootstrap/app_bootstrap.dart`
  - `lib/app.dart`
  - corresponding `test/features/wake_plan/**` and `test/app_scaffold_test.dart`
- depends_on: [Task_3]
- acceptance:
  - Enabled repeating plans always maintain the configured rolling future horizon after startup/resume/reconciliation.
  - A same-weekday plan created after today's target schedules the next valid week instead of succeeding with zero requests.
  - Repeated reconciliation is idempotent and does not duplicate existing occurrences or native requests.
  - Disabled/deleted/skipped plans are not replenished incorrectly.
  - Empty schedule results cannot masquerade as successful scheduling when an enabled plan should have a future occurrence.
- validation:
  - kind: command; required: true; owner: worker; detail: focused tests for same-weekday-after-time, day advancement, restart/resume, duplicate reconcile, skip, disabled, deleted.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: state/idempotency/time-boundary review.

### Task_8: Make edit/delete/skip compensation preserve the authoritative schedule

- status: unstarted
- type: impl
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `test/features/wake_plan/application/wake_plan_service_test.dart`
- depends_on: [Task_7]
- acceptance:
  - Old cancel success followed by replacement schedule failure restores the old native reservation set, not only the plan row.
  - Partial old-cancel and replacement-cancel failures converge to an explicit recoverable state without silent missing or extra alarms.
  - Delete, edit, skip, and undo share consistent compensation semantics.
  - Every returned result accurately describes DB and native state; no success or restored UI state is emitted while alarms differ.
- validation:
  - kind: command; required: true; owner: worker; detail: focused fault-injection tests for each cancel/schedule/compensation boundary.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: failure-state-machine and retry review.

### Task_9: Make create retry idempotent

- status: unstarted
- type: impl
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `lib/features/wake_plan/ui/create_wake_plan_sheet.dart`
  - `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`
  - corresponding wake-plan service/UI/calendar tests
- depends_on: [Task_4, Task_8]
- acceptance:
  - Retrying from the same open sheet reuses one logical plan identity.
  - Full failure leaves no duplicate plan; partial failure retry creates at most one native reservation per occurrence.
  - Calendar invalidation displays one plan and truthful warning/recovery state.
  - Double-tap and delayed completion cannot race into duplicate saves.
- validation:
  - kind: command; required: true; owner: worker; detail: full/partial failure retry, double-submit, and stale-completion widget/service tests.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: idempotency and UI lifecycle review.

### Task_10: Define an additive stable-ID and native inventory contract

- status: unstarted
- type: design
- owns:
  - `lib/core/platform/native_alarm_gateway.dart`
  - `lib/core/platform/method_channel_native_alarm_gateway.dart`
  - `lib/core/platform/fake_native_alarm_gateway.dart`
  - `test/core/platform/**`
  - `docs/platform/native-alarm-channel.md`
- depends_on: [Task_9]
- acceptance:
  - The contract supports durable caller-correlatable native alarm identity before/through scheduling and an inventory/status read for reconciliation.
  - The extension is schema-versioned or additive so rolling deployment and platform implementation order are safe.
  - Unknown, missing, duplicate, corrupt, and extra native rows have explicit failure semantics.
  - Fake and MethodChannel implementations have parity tests.
  - If a safe additive contract cannot fit this scope, the worker stops before broad edits and requests decomposition with a compatibility plan.
- validation:
  - kind: command; required: true; owner: worker; detail: focused gateway contract tests and `flutter test test/core/platform`.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and full `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: cross-version contract and boundary validation review.

### Task_11: Implement native inventory/stable identity on Android

- status: unstarted
- type: impl
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/**`
  - `android/app/src/main/AndroidManifest.xml` only if contract delivery requires it
  - `android/app/src/test/**`
  - `integration_test/native_alarm_smoke_test.dart` only for Android contract coverage
- depends_on: [Task_6, Task_10]
- acceptance:
  - Android accepts/preserves the contract identity and enumerates authoritative mirror/AlarmManager-correlatable state.
  - Inventory excludes expired/corrupt rows safely and reports mismatches without inventing success.
  - Schedule/cancel/inventory/reboot remain idempotent under duplicate calls.
  - Existing Android wake, notification, stop, vibration, and recovery behavior remains intact.
- validation:
  - kind: command; required: true; owner: worker; detail: focused native contract/recovery tests.
  - kind: command; required: true; owner: worker; detail: `flutter build apk --debug`, Android native smoke where environment permits, `flutter analyze`, `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: Android integration and mirror-authority review.

### Task_12: Implement AlarmKit inventory and stop-state observation on iOS

- status: unstarted
- type: impl
- owns:
  - `ios/Runner/AlarmKitBridge.swift`
  - `ios/Runner/AppDelegate.swift`
  - `ios/Runner/SceneDelegate.swift` only if lifecycle delivery requires it
  - `ios/RunnerTests/**`
  - `integration_test/native_alarm_smoke_test.dart` only for iOS contract coverage
- depends_on: [Task_1, Task_10]
- acceptance:
  - AlarmKit uses/preserves the contract identity and exposes authoritative scheduled inventory.
  - AlarmKit stop/removal changes become observable to Dart or are recoverable on the next inventory read.
  - Authorization denied, disappeared one-shot alarm, cancel, and corrupt/unknown identity have explicit semantics.
  - Result callbacks are delivered on a Flutter-safe execution context.
- validation:
  - kind: command; required: true; owner: worker; detail: focused Swift/contract tests and plist validation.
  - kind: command; required: true; owner: worker; detail: iOS simulator build/smoke when platform is installed; otherwise record exact BLOCKED evidence and require remote CI before merge.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: AlarmKit lifecycle/contract review.

### Task_13: Reconcile Drift and native reservations durably

- status: unstarted
- type: impl
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart`
  - `lib/features/wake_plan/data/src/wake_plan_database.dart`
  - generated Drift output only when regeneration is required
  - `lib/core/bootstrap/app_bootstrap.dart`
  - corresponding repository/service/migration tests
- depends_on: [Task_7, Task_8, Task_9, Task_11, Task_12]
- acceptance:
  - Native success followed by process/DB failure is detected on restart and converges by adopting or cancelling the alarm safely.
  - DB-only scheduled rows and native-only alarms are repaired according to one documented authority/merge policy.
  - Reconciliation is idempotent across repeated startup/resume calls and survives corrupt/stale rows.
  - Any schema change uses expand-contract migration and remains rollback-aware.
- validation:
  - kind: command; required: true; owner: worker; detail: fault-injection tests for every native/DB interruption point, reopen/restart, duplicates, corrupt rows, and migration.
  - kind: command; required: true; owner: worker; detail: `flutter analyze`, full `flutter test`, `flutter build apk --debug`.
  - kind: review; required: true; owner: reviewer; detail: data authority, migration, and failure-recovery review.

### Task_14: Reconcile native stop state and current-ringing selection

- status: unstarted
- type: impl
- owns:
  - `lib/features/alarm_ringing/application/alarm_ringing_controller.dart`
  - `lib/features/alarm_ringing/presentation/alarm_ringing_placeholder.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart` only for the minimal ringing query/state operation
  - corresponding alarm-ringing and repository tests
- depends_on: [Task_13]
- acceptance:
  - A native/system stop becomes dismissed/expired in Drift on next event or reconciliation.
  - Stale overdue `scheduled` rows cannot mask a newer truly active alarm.
  - Current selection has a bounded, documented due window and deterministic ordering.
  - Stop remains retryable when native cancel/update fails and never dismisses the wrong occurrence.
- validation:
  - kind: command; required: true; owner: worker; detail: native-stop then reopen, stale-vs-current, multiple due, retry, and idempotent dismissal tests.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: lifecycle/state-selection review.

### Task_15: Final harmonization and repository-wide merge gate

- status: unstarted
- type: review
- owns: []
- depends_on: [Task_5, Task_11, Task_12, Task_14]
- acceptance:
  - All confirmed findings map to merged evidence and no cross-PR contract drift remains.
  - Dart/Android/iOS channel schemas, IDs, state transitions, docs, and tests agree.
  - Orchestrator deep-review returns APPROVED with no Blocker/High finding.
- validation:
  - kind: command; required: true; owner: orchestrator; detail: `dart format --output=none --set-exit-if-changed lib test integration_test`.
  - kind: command; required: true; owner: orchestrator; detail: `flutter analyze`, full `flutter test`, `flutter build apk --debug`, and `git diff --check`.
  - kind: review; required: true; owner: reviewer; detail: repository-wide `$deep-review` and orchestrator `gh-review-hook` evidence for every final PR.

### Task_16: Real-device release evidence

- status: blocked
- type: test
- owns:
  - `docs/qa/artifacts/**`
  - `docs/qa/release-readiness.md`
  - platform QA checklists
- depends_on: [Task_15]
- acceptance:
  - iOS 26+ real-device alarm authorization, delivery, lock/terminated, stop, cancel, multi-reservation, and cleanup pass.
  - Android API 36 real-device delivery, lock/terminated, full-screen, permission transitions, reboot/direct-boot restore, stop, cancel, multi-reservation, and cleanup pass.
- validation:
  - kind: manual; required: true; owner: user; detail: collect device logs/screenshots under `docs/qa/artifacts/` and update release-readiness truthfully.
- blocker: no real-device evidence is currently available; code workers must not waive or relabel this gate.

## Task Waves

- Wave 1A (baseline repair): [Task_4]
- Wave 1B (parallel, disjoint after the required full-test baseline is green): [Task_1, Task_2, Task_3, Task_5]
- Wave 2 (parallel after dependencies): [Task_6, Task_7]
- Wave 3 (sequential state mutations): [Task_8]
- Wave 4 (sequential idempotency): [Task_9]
- Wave 5 (contract foundation): [Task_10]
- Wave 6 (parallel platform implementations): [Task_11, Task_12]
- Wave 7 (sequential durable reconciliation): [Task_13]
- Wave 8 (sequential ringing reconciliation): [Task_14]
- Wave 9 (orchestrator/reviewer): [Task_15]
- Wave 10 (user-owned): [Task_16]

## Worker Contract

- Every worker uses `gpt-5.6-luna` with `xhigh` reasoning in a separate Codex worktree and `codex/reviewfix-*` branch.
- Every worker loads repository instructions, `$task-pr-worker`, `$orchestration-harness`, `$engineering-quality-baselines`, `$git-workflow`, and `$deep-review` before editing.
- Every shell command is prefixed with `rtk`; no force push, history rewrite, broad cleanup, or other worker's changes.
- Workers perform bounded investigation before editing, use subagents when allowed, obtain independent review, create a PR, iterate `gh-review-hook` to exit 0, and never merge.
- A worker must report before stopping and must request decomposition before crossing `owns` or growing a broad diff.

## Rollback / Safety

- Merge small PRs in dependency order; revert a single PR rather than rewriting history.
- Keep channel changes additive until both native implementations and Dart consumers are merged.
- Do not delete native mirror/Drift data during migration without an explicit reconciliation policy and recovery test.
- Do not mark release readiness PASS without Task 16 evidence.

## Progress Log

- 2026-07-10 Plan created from whole-codebase deep-review findings.
  - Research waived using current source-grounded review evidence.
  - No open PRs were present; `master` matched `origin/master` except user-owned untracked `docs/coding-agent/reports/`.
  - Next action: merge this ledger-only plan, then dispatch Wave 1 with Luna ExtraHigh.

- 2026-07-10 Task_4 dispatched and startup-checked.
  - Worker thread: `019f4a0e-0e34-7193-b3ec-f42d6216acfb` in a separate worktree.
  - Branch/runtime: `codex/reviewfix-clock-injection` on `gpt-5.6-luna` / `xhigh` (Luna ExtraHigh).
  - Startup state: active; exact Task_4 goal set; skill loading and pre-edit failure reproduction in progress.
  - Next action: review and merge Task_4 only after worker and orchestrator gates pass, then dispatch Wave 1B in parallel.

## Decision Log

- 2026-07-10 Decision: split cross-platform state repair into additive contract, platform implementation, durable reconciliation, and ringing reconciliation.
  - Trigger: a single fix would span Dart, Drift, Android, iOS, lifecycle, migrations, and UI state.
  - Tradeoff: more PRs and sequential waves in exchange for bounded ownership, rollback safety, and reviewable contracts.
  - User approval: yes; user explicitly requested orchestration, detailed Luna ExtraHigh workers, and decomposition of complex tasks.

- 2026-07-10 Decision: keep real-device release evidence blocked and user-owned.
  - Trigger: existing release-readiness requires physical iOS 26+ and Android API 36 evidence.
  - Tradeoff: code remediation can complete while normal MVP release remains blocked.
  - User approval: inherited from existing release gate; no waiver requested.

- 2026-07-10 Decision: run Task_4 before the remaining Wave 1 tasks.
  - Trigger: the repository-wide `flutter test` baseline currently fails on the two clock-dependent tests, so parallel workers could not satisfy their required full-suite merge gate.
  - Plan delta: Task_4 now owns the detail-sheet clock propagation path; Tasks 1, 2, 3, and 5 depend on Task_4 for validation readiness.
  - Tradeoff: one short sequential PR before parallel work prevents every other worker from carrying and later rebasing around the same known red baseline.
  - User approval: covered by the user's instruction to split clearly complex work and proceed autonomously.
