# Plan: Alarm permission startup gate

- status: done
- generated: 2026-07-15
- last_updated: 2026-07-15
- work_type: code

## Goal

- Prevent users from reaching alarm-dependent workflows until Android alarm readiness is verified, with clear full-screen remediation and defensive downstream error handling.

## Definition of Done

- Startup checks exact-alarm, notification, full-screen-intent, and wake-channel readiness before reconciliation or home display.
- Missing readiness shows a full-screen gate that opens the correct system flow one item at a time and refreshes after app resume.
- Android 13+ notification access uses the runtime permission flow, with settings fallback where appropriate.
- Capability check failures are retryable and never become an infinite loading state.
- Permission revocation races remain safely surfaced by scheduling and receiver paths.
- Required Flutter/Android checks pass and independent review approves startup, lifecycle, and device evidence.
- A temporary near-future wake alarm is created on the connected device, rings through the intended alarm UI, can be stopped, and is removed without leaving changed permission state.

## Scope / Non-goals

- Scope: shared gateway/capability state, root startup routing, full-screen gate, lifecycle/reconciliation ordering, Android permission intents/callback, downstream permission failure mapping, receiver containment, and one reversible physical-device alarm creation/ringing flow.
- Non-goals: battery-optimization exemption, OEM-specific autostart instructions, changing the four-condition full-screen-alarm promise, or persisted schema changes.

## Context (workspace)

- Related files/areas: `lib/app.dart`, platform gateway/bootstrap, alarm health settings, inline save flow, Android alarm bridge/receiver, and corresponding tests.
- Existing patterns or references: `AlarmHealthController` capability state and native bridge `NativeAlarmCapability` requirement flags.
- Repo reference docs consulted: root `AGENTS.md`, `docs/coding-agent/lessons.md`; repository rule suite is absent.

## Open Questions (max 3)

- None blocking.

## Assumptions

- All four current native readiness conditions remain hard prerequisites because scheduling currently rejects any missing condition and the product promises reliable full-screen wake alarms.
- The gate requests or opens one missing requirement per user action, then relies on lifecycle resume refresh before proceeding.
- Battery optimization remains advisory and is not requested.

## Tasks

### Task_1: Research native alarm readiness and startup ordering

- type: research
- owns: []
- depends_on: []
- description: |
  Map capability checks, permission flows, lifecycle refresh, reconciliation, scheduling failures, receiver behavior, and platform-version rules.
- acceptance:
  - Required versus advisory capabilities are identified for supported Android versions.
  - Exact source paths, state transitions, failure gaps, and validation commands are documented.
- validation:
  - kind: review
    required: true
    owner: orchestrator
    detail: "Research covers startup race, Android 31/33/34+ behavior, resume, transport failures, and receiver fallback."

### Task_2: Implement startup permission readiness gate

- type: impl
- owns:
  - lib/app.dart
  - lib/core/bootstrap/app_bootstrap.dart
  - lib/core/platform/native_alarm_gateway.dart
  - lib/core/platform/method_channel_native_alarm_gateway.dart
  - lib/features/settings/application/alarm_health_controller.dart
  - lib/features/settings/presentation/alarm_permission_gate.dart
  - lib/features/week_calendar/presentation/week_calendar_placeholder.dart
  - android/app/src/main/kotlin/dev/xpa/calarm/MainActivity.kt
  - android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt
  - android/app/src/main/kotlin/dev/xpa/calarm/AlarmReceiver.kt
  - test/app_scaffold_test.dart
  - test/core/platform/method_channel_native_alarm_gateway_test.dart
  - test/features/settings/application/alarm_health_controller_test.dart
  - test/features/week_calendar/presentation/week_calendar_placeholder_test.dart
  - android/app/src/test/kotlin/dev/xpa/calarm/**
- depends_on: [Task_1]
- description: |
  Add shared startup readiness state and full-screen remediation, correct notification permission requests, reorder reconciliation, and contain late permission/receiver failures.
- acceptance:
  - Root displays loading, actionable missing-readiness, and retryable check-failure states; calendar/home is hidden until ready.
  - Reconciliation runs only after a fresh ready capability result, runs once per transition, and revocation on resume returns to the gate before further reconciliation.
  - Gate explains each missing exact-alarm/notification/full-screen/channel requirement, requests one item, and refreshes after resume without trusting an immediate stale result.
  - API 33+ notification permission uses runtime request/callback; exact alarm, full-screen intent, and channel use the appropriate settings surfaces.
  - Gateway transport/malformed failures become stable typed capability/scheduling failures, and permission loss during Save refreshes readiness while keeping inline Retry diagnostics.
  - Alarm receiver isolates notification/full-screen/vibration runtime/security failures so ringing state and remaining fallbacks survive revocation.
  - Compact portrait/landscape gate layouts and existing ready-home/calendar/settings flows remain passing.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "rtk dart format --output=none --set-exit-if-changed on owned Dart files"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter analyze"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter test focused app/platform/settings/calendar tests"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter test"
  - kind: command
    required: true
    owner: worker
    detail: "cd android && rtk ./gradlew testDebugUnitTest"
  - kind: command
    required: true
    owner: worker
    detail: "rtk git diff --check"

### Task_3: Independently review permission and lifecycle safety

- type: review
- owns: []
- depends_on: [Task_2]
- description: |
  Review cross-layer permission routing and independently execute Flutter/Android acceptance flows, including denied/granted/error/revoked states.
- acceptance:
  - Reviewer status is APPROVED with no blocking findings.
  - Evidence covers startup gating, reconciliation ordering, resume transitions, all requirement types, notification runtime flow, save races, receiver containment, and compact layouts.
- validation:
  - kind: e2e
    required: true
    owner: reviewer
    detail: "Run Flutter and Android permission/readiness acceptance tests and inspect device behavior when available."
  - kind: review
    required: true
    owner: reviewer
    detail: "Review capability authority, lifecycle races, typed failures, native callback cleanup, and receiver fallbacks."

### Task_4: Validate a real alarm end to end on the connected device

- type: review
- owns:
  - artifacts/ui/alarm-creation-device/**
- depends_on: [Task_3]
- description: |
  Temporarily satisfy required Android alarm permissions, create one uniquely identifiable near-future alarm through the app UI, observe real ringing and stop behavior, then remove the created alarm and restore the original permission state.
- acceptance:
  - The app reaches the calendar only after every required system permission is satisfied.
  - One near-future alarm is created through the calendar UI and appears as scheduled before firing.
  - With the app backgrounded or device locked, the alarm presents the expected ringing UI/notification and can be stopped without a fatal exception.
  - The created alarm is removed and exact-alarm, notification, full-screen-intent, and channel states are restored to their recorded pre-test values.
  - Reviewer reports APPROVED with screenshots, UI dumps, timing evidence, and relevant logcat/dumpsys evidence.
- validation:
  - kind: e2e
    required: true
    owner: reviewer
    detail: "Run one reversible physical-device create/schedule/ring/stop/delete flow on the connected Sony XQ-FS44 and capture evidence."
  - kind: review
    required: true
    owner: reviewer
    detail: "Confirm cleanup, permission restoration, and absence of fatal receiver/ringing exceptions."

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]
- Wave 2 (parallel): [Task_2]
- Wave 3 (parallel): [Task_3]
- Wave 4 (parallel): [Task_4]

## E2E / Visual Validation Spec

- provider: Flutter widget tests, Android JVM tests, and ADB device checks when available
- artifact_root: Flutter/Gradle output; optional screenshots under `artifacts/ui/`
- base_url: n/a
- app_start_command: `rtk flutter run -d <device-id>`
- readiness_check: ADB reports the device and the app reaches either the readiness gate or calendar without uncaught startup errors.
- flows: fresh denied startup; sequential exact/notification/full-screen/channel remediation; return/resume; ready startup; capability check error/retry; revocation on resume; permission-loss save race; receiver fallback; one reversible near-future create/schedule/background-or-lock/ring/stop/delete flow.
- viewports: 320x568 portrait, 568x320 landscape, Android 31/33/34+ simulated tests, and connected Android 16 device if present.
- evidence_requirements: exact commands, positive executed-test counts, reconciliation call counts/order, native callback results, no overflow/exception, and reviewer source/diff notes.
- known_flakiness: Android system permission/settings screens vary by OEM; device validation must distinguish app behavior from system UI wording.

## Rollback / Safety

- Restore unconditional home routing and reconciliation timing, leaving existing settings health panel and schedule-time checks; no data/schema rollback is needed.

## Progress Log (append-only)

- 2026-07-15 Wave 4 completed: [Task_4]
  - Summary: Reviewer approved the Sony XQ-FS44 create/schedule/screen-off/ring/stop/delete/restore flow for one calendar Wake Plan.
  - Validation evidence: Saved at 18:52:22; first exact alarm fired at 19:00:00.042; notification posted at +248ms; AlarmStopActivity appeared full-screen at +427ms from Dozing; STOP completed at 19:00:47; Plan deleted at 19:04:07; active package alarms, UI plans, notifications, and ringing surfaces were all zero/absent by 19:06:09; no fatal Flutter/platform exception occurred.
  - Notes: The one Plan expanded to 13 five-minute occurrences, but only the first rang and the remaining occurrences were cancelled before 19:05. Exact-alarm and notification permissions were restored to their initial denied/default states; FSI and channel state were unchanged. Device mute prevented auditory confirmation, while notification `isNoisy=true`, alarm channel, full-screen wake, and STOP behavior were evidenced.
- 2026-07-15 Wave 4 started: [Task_4]
  - Summary: User explicitly authorized creating a real alarm on the connected Sony XQ-FS44.
  - Validation evidence: Research waived because the completed implementation plan, connected-device state, permission sequence, and Reviewer evidence already provide the required context; no source edit is planned.
  - Notes: Reviewer must record and restore every changed permission/channel state, delete the created alarm, avoid clearing app data, and collect create/ring/stop evidence under `artifacts/ui/alarm-creation-device/`.
- 2026-07-15 Wave 4 deviation recorded: [Task_4]
  - Summary: One calendar Wake Plan for 19:00–20:00 expands into 13 native occurrences at five-minute intervals rather than one native alarm.
  - Validation evidence: Before creation there were zero package native alarms; after saving the single plan, dumpsys showed the 19:00–20:00 occurrence series.
  - Notes: Permit only the first 19:00 occurrence to ring, then stop and delete the single plan immediately so the remaining 12 occurrences are cancelled before delivery; do not create any additional plan.
- 2026-07-15 Wave 3 completed: [Task_3]
  - Summary: Reviewer approved the physical-device startup permission-gate flow on Sony XQ-FS44 / Android API 36.
  - Validation evidence: Latest debug APK installed with data preserved; denied cold start hid Calendar/home; exact-alarm CTA opened Sony settings; returning without granting kept the gate; temporary notification grant did not bypass the remaining exact-alarm gate; related logcat contained no fatal Flutter/platform exception.
  - Notes: POST_NOTIFICATIONS was restored to its original denied/app-op-ignore state. No app data, real alarm, exact-alarm, full-screen, or channel state was changed. Notification runtime dialog and ready-to-revoked transition remain covered by Android JVM/Flutter tests because exact alarm was intentionally not modified on the user device.
- 2026-07-15 Wave 3 device acceptance resumed: [Task_3]
  - Summary: ADB detected Sony XQ-FS44; independent Reviewer device validation was dispatched.
  - Validation evidence: Device reports `device` over USB and is available for data-preserving APK replacement.
  - Notes: Validation is limited to notification-permission revoke/restore, startup/resume routing, system permission UI, screenshots, and crash logs; no app-data reset or real alarm creation.

- 2026-07-15 Wave 1 completed: [Task_1]
  - Summary: Mapped root startup ordering, shared-capability gaps, Android 31/33/34+ requirements, native request flows, scheduling failures, and receiver risks.
  - Validation evidence: Research cited concrete Dart/Kotlin/manifest paths and defined Flutter/Gradle/device checks.
  - Notes: Selected all four native readiness conditions as hard gate requirements to match current scheduler semantics and full-screen alarm reliability.
- 2026-07-15 Wave 2 completed: [Task_2]
  - Summary: Added shared readiness state, full-screen sequential gate, ready-only reconciliation, API 33 runtime notification permission, typed channel failures, save-time refresh, and isolated receiver fallbacks.
  - Validation evidence: Formatting and analysis passed; 67 focused Flutter tests, all 305 Flutter tests, and 46 Android JVM tests passed; `git diff --check` passed.
  - Notes: All Worker edits stayed within corrected Task_2 ownership. Immediate permission-request results cannot admit home; application resume is the authority for a fresh capability revision.
- 2026-07-15 Wave 3 review completed; device acceptance pending: [Task_3]
  - Summary: Independent review found and then approved a latest-wins generation fix for overlapping capability checks; no remaining source or automated-test blocker was found.
  - Validation evidence: Reviewer reran 14 controller tests, all 309 Flutter tests, `flutter analyze`, and `git diff --check`; the earlier review also passed 46 Android JVM tests and compact four-requirement gate checks.
  - Notes: ADB daemon restart and USB/mDNS discovery still report no connected device, so the user-requested Android 16 physical-device install and denied-permission startup flow remain pending.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-15 Decision: Gate application entry on shared alarm readiness before reconciliation.
  - Trigger / new insight: Real-device use exposed permission failure only after Save, while startup reconciliation already ran without capability verification.
  - Plan delta (what changed): Add a full-screen sequential readiness gate, resume refresh, correct API 33 notification request, and defensive late-failure containment.
  - Tradeoffs considered: Gating only exact-alarm access is smaller but inconsistent with the scheduler's current rejection of missing notification, full-screen, or channel readiness.
  - User approval: yes; the user explicitly proposed a startup full-screen permission screen.
- 2026-07-15 Decision: Make capability publication latest-wins.
  - Trigger / new insight: Reviewer reproduced a reverse-completion race where an older ready response could overwrite a newer missing-permission response.
  - Plan delta (what changed): Add generation authority across refresh, permission, and test-alarm capability operations plus four reverse-completion regression cases.
  - Tradeoffs considered: Serializing every request would avoid overlap but delay newer lifecycle signals; latest-wins preserves responsiveness while rejecting stale results.
  - User approval: implicit within the requested permission error-handling scope.
- 2026-07-15 Decision: Extend physical-device validation through real alarm delivery.
  - Trigger / new insight: The prior device pass intentionally stopped before changing exact-alarm access or creating an alarm; the user has now explicitly authorized alarm creation.
  - Plan delta (what changed): Reopen the completed plan with Task_4 for reversible permission enablement, near-future alarm creation, real ringing/stop evidence, deletion, and permission restoration.
  - Tradeoffs considered: A test-alarm shortcut is smaller but does not validate calendar creation and persisted scheduling, so the primary calendar creation flow is required when practical.
  - User approval: yes; the user explicitly stated that creating an alarm is allowed.
- 2026-07-15 Decision: Treat one Wake Plan as the authorized creation unit while limiting delivery to its first occurrence.
  - Trigger / new insight: The product's default one-hour, five-minute interval semantics fan one saved plan out to 13 native alarms.
  - Plan delta (what changed): Keep the already-created single plan, observe only its first 19:00 delivery, then delete it immediately and prove all remaining native occurrences are cancelled.
  - Tradeoffs considered: Cancelling before any delivery would avoid extra scheduling but would not satisfy the authorized real ringing check; allowing later occurrences to ring would exceed the intended one-alarm validation.
  - User approval: the user authorized creating an alarm; no additional plan or more than one actual ringing event is permitted.

## Notes

- Risks: multiple gateway provider identity, stale immediate permission results, asynchronous runtime callback lifecycle, reconciliation duplication, permission revocation races, receiver exception containment, and repeated non-fatal AppOps attribution warnings during ringing.
- Edge cases: unsupported platform, malformed method-channel response, repeated CTA taps, permanent notification denial, activity recreation, resume during request, channel disabled, and permission loss between gate and Save.
- Quality routing note: L3 because platform permissions gate the primary alarm path and startup ordering can affect persisted scheduling state; security/data-integrity/platform-contract and lifecycle checks are in scope.
- Residual device note: Ringing emitted 168 `E/AppOps: attributionTag not declared in manifest of dev.xpa.calarm` entries without functional failure; attribution usage around the sound/vibration loop should be diagnosed separately.
