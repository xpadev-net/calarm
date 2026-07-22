# Plan: User-selectable Alarm Sounds

- status: approved
- execution_status: queued
- generated: 2026-07-22
- last_updated: 2026-07-22
- work_type: code
- requested_by: user
- blocked_by: `codebase-review-remediation-plan.md` Task_15 and Task_24

## Goal

- Let users choose an alarm sound instead of exposing a single non-functional `default` choice.
- Apply the selected sound consistently to Wake Plan creation/editing, default settings, persisted schedules, Android playback, and iOS AlarmKit where the supported platform API permits it.
- Keep sound selection deterministic, testable, and safe when a stored sound is removed, unsupported, or unavailable at delivery time.

## Current State

- `WakePlan.soundId`, `AppSettings.defaultSoundId`, Drift rows, and the Dart/native scheduling payload already carry a string sound ID.
- Domain validation currently accepts only `default`.
- Settings and Wake Plan UI render a dropdown containing only the OS/default sound.
- Android persists `soundId` but `AlarmStopActivity` always plays the OS default alarm URI.
- iOS persists `soundId` as AlarmKit metadata but the current `AlarmPresentation` construction does not apply it to audible delivery.
- This is a new feature and remains outside the codebase-remediation plan; it must not extend or delay Task_15 closeout.

## Definition of Done

- Users can select from a documented supported sound catalog in both default settings and each Wake Plan create/edit flow.
- The chosen stable sound ID survives persistence, edit/restart, scheduling, native recovery, and delivery.
- Android and iOS either play the selected sound or present an explicit platform capability limitation; the UI never offers an option that silently behaves as another sound.
- Missing, removed, corrupt, or legacy sound IDs fall back deterministically to the OS default without preventing an alarm from firing.
- Preview is bounded, stoppable, lifecycle-safe, and uses the same catalog mapping as delivery if preview is included.
- Every implementation PR passes worker review, independent exact-head review, `gh-review-hook`, CI, native smoke where applicable, and orchestrator merge gates.

## Scope / Non-goals

- In scope:
  - A small versioned catalog of stable sound IDs and user-facing labels.
  - Per-plan sound selection and a default sound setting.
  - Android and iOS mapping from stable IDs to supported bundled/system alarm audio.
  - Deterministic fallback, persistence, edit/recovery, and optional preview lifecycle.
- Non-goals:
  - Arbitrary user-imported audio files, cloud downloads, music-library access, DRM content, recording audio, or per-occurrence sound changes.
  - Volume override, gradual volume, audio focus policy beyond what alarm delivery requires, or changing the existing vibration feature.
  - Claiming cross-platform parity before current Android and iOS platform APIs are verified.

## Quality Routing

- Routing level: L3.
- Primary risks: alarms firing silently, UI/native catalog drift, unsupported stored IDs, lost audio resources, Android notification-channel sound immutability, iOS AlarmKit capability constraints, preview leaking playback after lifecycle changes, and Task_13 recovery losing sound identity.
- Required perspectives: external integration, event/failure lifecycle, data compatibility, mobile UI/accessibility, generated/native resource handling, and tests.

## Tasks

### Task_1: Define the sound catalog and prove platform capability

- status: unstarted
- type: research/contract
- owns:
  - `docs/platform/alarm-sound-catalog.md`
  - `lib/core/platform/alarm_sound_catalog.dart`
  - `lib/core/platform/native_alarm_gateway.dart` only if the existing `soundId` contract needs clarification
  - focused catalog/contract tests
- depends_on:
  - codebase remediation Task_15
  - codebase remediation Task_24
- acceptance:
  - A bounded official-SDK investigation records how Android alarm playback and iOS AlarmKit can select bundled/system sounds at schedule and delivery time.
  - Stable IDs, labels, resource names, fallback rules, legacy `default`, and catalog versioning are explicit.
  - At least two genuinely distinguishable choices are proven feasible on each supported platform before the selection UI is enabled for that platform.
  - If a platform cannot select a sound through its supported alarm API, stop with a concrete capability report and product options rather than shipping a misleading selector.
- validation:
  - kind: review; required: true; owner: reviewer; detail: official API/resource evidence, catalog stability, fallback behavior, and platform-parity review.
  - kind: command; required: true; owner: worker; detail: focused Dart catalog/contract tests, format, analyze, and diff-check.

### Task_2: Add default and per-plan sound selection in Flutter

- status: unstarted
- type: impl
- owns:
  - `lib/features/wake_plan/domain/src/wake_plan.dart`
  - `lib/features/wake_plan/domain/src/app_settings.dart`
  - `lib/features/settings/application/wake_plan_defaults_controller.dart`
  - `lib/features/settings/presentation/settings_placeholder.dart`
  - `lib/features/wake_plan/ui/create_wake_plan_sheet.dart`
  - `lib/features/wake_plan/ui/wake_plan_detail_sheet.dart` only if detail/edit presentation needs the selected label
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart` only for sound fallback compatibility
  - corresponding domain, repository, controller, and widget tests
- depends_on: [Task_1]
- acceptance:
  - Settings choose the default sound; create uses that default; edit preserves and can change the plan sound.
  - The UI shows catalog labels, exposes the current value accessibly, and never saves an unsupported ID.
  - Legacy `default`, removed IDs, and corrupt persisted values sanitize to the documented fallback without changing unrelated settings.
  - Saving or editing a sound follows the existing Wake Plan rescheduling/recovery protocol and does not create duplicate alarms.
- validation:
  - kind: command; required: true; owner: worker; detail: domain/repository/controller/widget tests for default/create/edit/restart/fallback plus full Flutter tests, analyze, format, APK, and diff-check.
  - kind: e2e; required: true; owner: reviewer; detail: compact portrait/landscape, accessibility label, selection persistence, and edit-flow widget evidence.

### Task_3: Play the selected sound on Android

- status: unstarted
- type: impl
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmStopActivity.kt`
  - `android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt` only for sound resolution/persisted request compatibility
  - `android/app/src/main/res/raw/**` if bundled sounds are selected by Task_1
  - corresponding Android JVM/Robolectric tests
  - `docs/qa/android-alarm-checklist.md` only for the new sound matrix
- depends_on:
  - Task_1
  - `alarm-ringing-notification-ux-plan.md` Task_3
- acceptance:
  - The exact persisted request sound ID resolves to the intended alarm audio and loops/stops with the existing ringing lifecycle.
  - Unknown/missing resources fall back to the OS alarm sound; delivery never fails solely because sound resolution fails.
  - Sound selection does not weaken lock-screen behavior, Direct Boot access, event journaling, current-only stop, vibration cleanup, or exact alarm identity.
  - Notification-channel immutability and OEM behavior are handled explicitly rather than assuming a channel sound can change per alarm.
- validation:
  - kind: command; required: true; owner: worker; detail: focused sound resolution/playback lifecycle tests, full Android JVM tests, debug APK, format, diff-check, and Android native smoke.
  - kind: manual; required: true; owner: user; detail: Task_16 real-device evidence eventually verifies audible distinction and fallback on Android API 36 hardware.

### Task_4: Apply the selected sound through iOS AlarmKit

- status: unstarted
- type: impl
- owns:
  - `ios/Runner/AlarmKitBridge.swift`
  - `ios/RunnerTests/RunnerTests.swift`
  - iOS app audio resources and Xcode project references only when Task_1 proves they are supported and required
  - `docs/qa/ios-alarmkit-checklist.md` only for the new sound matrix
- depends_on: [Task_1]
- acceptance:
  - AlarmKit scheduling/recovery uses the documented selected sound mapping without weakening stable reservation identity or availability-first replacement.
  - Unsupported/missing resources use the documented fallback and do not prevent alarm delivery.
  - Exact inventory, cancel, replacement journal, rollback decoding, and process-death recovery retain sound identity.
  - If current AlarmKit does not expose supported per-alarm sound selection, no non-functional UI is enabled; the task returns the proven limitation and an explicit product decision point.
- validation:
  - kind: command; required: true; owner: worker; detail: focused RunnerTests/XCTest for catalog mapping, recovery, fallback, and resource presence plus iOS native smoke.
  - kind: manual; required: true; owner: user; detail: Task_16 real-device iOS 26+ evidence eventually verifies audible distinction, lock/terminated delivery, and fallback.

### Task_5: Run cross-platform alarm-sound integration review

- status: unstarted
- type: review
- owns: []
- depends_on: [Task_2, Task_3, Task_4]
- acceptance:
  - Flutter catalog IDs, Android resources/resolver, iOS resources/resolver, persisted rows, MethodChannel payloads, recovery state, and documentation agree.
  - No offered choice silently maps to another sound in supported runtime paths.
  - Existing scheduling, native inventory, event journal, ringing dismissal, vibration, and fallback tests remain green.
  - Remaining physical-device evidence stays truthfully blocked under Task_16 until supplied.
- validation:
  - kind: command; required: true; owner: orchestrator; detail: Dart format, Flutter analyze/full tests, Android JVM tests, iOS RunnerTests, debug APK, native smoke, and git diff-check.
  - kind: review; required: true; owner: reviewer; detail: repository-wide sound contract, resource, lifecycle, accessibility, and failure-path deep review.

## Task Waves

- Wave 1 (contract/capability): [Task_1]
- Wave 2 (parallel after catalog): [Task_2, Task_3, Task_4]
- Wave 3 (integration): [Task_5]

## Rollback / Safety

- Keep `default` as the durable fallback ID so reverting UI/native mappings does not make existing alarms unreadable.
- Add catalog entries; do not silently repurpose an existing ID for different audio.
- Prefer reverting one platform PR over weakening alarm delivery or Task_13 authority.
- Do not delete user-owned audio, calendar drafts, reports, artifacts, or physical-device evidence during implementation.

## Progress Log

- 2026-07-22: Added at user request. Execution is queued until codebase remediation Task_15 and identity-contract Task_24 complete.
