# Plan: Polish the Full-screen Alarm and Add a Stop Notification Action

- status: approved
- execution_status: queued
- generated: 2026-07-22
- last_updated: 2026-07-22
- work_type: code
- requested_by: user
- blocked_by:
  - `codebase-review-remediation-plan.md` Task_15
  - `codebase-review-remediation-plan.md` Task_24
  - `codebase-review-remediation-plan.md` Task_26

## Goal

- Make the Android full-screen ringing surface visually clear, calm, and usable when the device is locked, unlocked, or opened from the notification.
- Let the user stop the exact currently ringing alarm directly from the notification action without first navigating through the app.
- Preserve the existing alarm authority, privacy, Direct Boot, event-journal, recovery, and exact-current-only stop contracts.

## Current State

- Task_19 added scheduled/current context, wake target, alarm position, next-alarm context, private/public notification variants, vibration cleanup, and legacy-row compatibility.
- `AlarmStopActivity` renders the full-screen native Android ringing surface and owns active sound/vibration cleanup.
- `AlarmReceiver` posts full-screen/private and redacted public notifications, but the notification has no explicit stop action button.
- Existing notification taps and full-screen intents open `AlarmStopActivity`; stop behavior is exact-current-only and feeds the durable native event journal added by Tasks 20-21.
- Task_26 will add receiver-entry recovery and therefore must merge before this plan changes the delivery/notification path.

## Definition of Done

- The full-screen alarm has a deliberate hierarchy for current time, wake target, plan/alarm context, next alarm, and the primary stop action across supported screen sizes and orientations.
- The screen remains legible on the lock screen, with large text, adequate contrast and touch targets, TalkBack semantics, and no unnecessary sensitive content.
- The private notification exposes a clear stop action; the public lock-screen notification remains generic while still allowing the authorized exact alarm to be stopped according to the documented security policy.
- The action stops only the intended current alarm, cleans up notification/sound/vibration, records durable dismissal only after the native stop contract succeeds, and remains idempotent under duplicate taps, process death, and replay.
- Existing full-screen fallback, Direct Boot, Task_24 identity, Task_26 recovery, and Task_13/20/21 reconciliation tests remain green.
- Heavy validation runs on exact-head GitHub Actions while the battery override is active; no acceptance gate is waived.

## Scope / Non-goals

- In scope:
  - Android native full-screen ringing layout, styling, accessibility, and state presentation.
  - Android notification action plumbing for exact-current-only stop.
  - A narrowly shared native stop operation when required to keep Activity and notification behavior identical.
  - Focused Android JVM/Robolectric tests and native-smoke evidence.
- Non-goals:
  - Redesigning Flutter calendar, settings, or Wake Plan editing screens.
  - Snooze, skip-next, dismiss-all, notification reply, or arbitrary background controls.
  - Custom notification layouts that expose private plan details on a public lock screen.
  - Replacing AlarmKit's system-owned iOS ringing presentation.
  - Changing alarm sounds; that remains in `alarm-sound-selection-plan.md`.

## Quality Routing

- Routing level: L3.
- Primary risks: stopping the wrong alarm, duplicate dismissal events, bypassing recovery/ownership checks, lock-screen privacy regressions, background-execution restrictions, PendingIntent identity collisions, inaccessible controls, and OEM full-screen differences.
- Required perspectives: Android lifecycle/security, event/failure recovery, Direct Boot, notification privacy, accessibility/responsive layout, concurrency/idempotence, and integration contracts.

## Tasks

### Task_1: Freeze the ringing-surface and notification-action contract

- status: unstarted
- type: research/contract
- owns:
  - `docs/platform/android-ringing-surface.md`
  - focused static contract tests only if needed
- depends_on:
  - codebase remediation Task_15
  - codebase remediation Task_24
  - codebase remediation Task_26
- acceptance:
  - Document the information hierarchy, public/private notification boundary, stop-action authorization, exact PendingIntent identity, and Activity/receiver/service lifecycle choice.
  - Define stop success, failure, duplicate-tap, stale-action, process-death, Direct Boot, and event-journal behavior before implementation.
  - Confirm supported Android APIs for notification actions and full-screen intent behavior using official platform documentation; record OEM/permission limitations without treating them as proof of physical-device behavior.
  - Attribute every overlapping file against the completed Task_19 and the merged Task_24/26 implementation before dispatching product workers.
- validation:
  - kind: review; required: true; owner: reviewer; detail: Android security/lifecycle, lock-screen privacy, exact-identity, background-execution, and accessibility contract review.
  - kind: command; required: true; owner: worker; detail: lightweight documentation/static checks and git diff-check only.

### Task_2: Polish the Android full-screen ringing surface

- status: unstarted
- type: impl
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmStopActivity.kt`
  - `android/app/src/main/res/layout/**` only for the ringing surface
  - `android/app/src/main/res/drawable/**` and `android/app/src/main/res/values/**` only for narrowly named ringing UI resources
  - focused Activity/Robolectric and resource tests
- depends_on: [Task_1]
- acceptance:
  - Current time, wake target, alarm position, scheduled/current state, optional next alarm, and primary stop affordance have a stable visual hierarchy with graceful absence/fallback states.
  - Compact/large portrait and landscape layouts avoid clipping and preserve a reachable stop control under font scaling and display cutouts.
  - TalkBack labels/order, contrast, touch target, focus, and reduced-motion behavior meet the documented contract.
  - Public lock-screen content remains redacted; no new plan/location data leaks through Activity labels, notification text, logs, or screenshots.
  - Recreation, configuration changes, late delivery, missing vibrator service, and sound/vibration cleanup preserve Task_19 behavior.
- validation:
  - kind: command; required: true; owner: worker; detail: exact-head GitHub Actions focused/full Android JVM tests, debug APK, Android native smoke, resource/static checks, and diff-check; no local heavy build while the battery override is active.
  - kind: review; required: true; owner: reviewer; detail: exact-head visual hierarchy, responsive states, accessibility, privacy, lifecycle, and regression review using deterministic Robolectric/render evidence where available.

### Task_3: Stop the exact ringing alarm from the notification action

- status: unstarted
- type: impl
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmReceiver.kt` only for notification construction/action wiring
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmStopActivity.kt` only for shared stop delegation after Task_2
  - `android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt` only for exact intent identity/current-state helpers
  - a narrowly named Android stop-action receiver/coordinator file if the Task_1 contract requires it
  - `android/app/src/main/AndroidManifest.xml` only for the explicit non-exported action component
  - corresponding Android JVM/Robolectric tests
- depends_on: [Task_2]
- acceptance:
  - The notification exposes an explicit, immutable, collision-safe stop PendingIntent bound to the exact current platform alarm identity.
  - A valid action works from locked, unlocked, foreground, background, and terminated-process states without requiring Flutter startup or an unrelated navigation step.
  - Stale, malformed, cross-plan, inactive, duplicate, or replayed actions fail closed and cannot stop a newer/different alarm.
  - Native stop, notification cancellation, sound/vibration cleanup, durable dismissal journaling, and later Dart acknowledgement follow one idempotent success contract; partial failure retains recovery evidence.
  - Public/private notification variants preserve the Task_1 privacy policy, and the action component is non-exported or equivalently protected.
  - Task_24 recreation identity and Task_26 delivery-entry recovery remain authoritative at every interruption seam.
- validation:
  - kind: command; required: true; owner: worker; detail: exact-head GitHub Actions action/identity/failure matrix, full Android JVM tests, debug APK, Android native smoke, manifest/static checks, and diff-check; no local heavy build while the battery override is active.
  - kind: review; required: true; owner: reviewer; detail: exact-head PendingIntent identity/security, current-only stop, journal ordering, process-death/duplicate-tap, Direct Boot, cleanup, and compatibility deep review.

### Task_4: Run ringing-surface integration and device-readiness review

- status: unstarted
- type: review
- owns: []
- depends_on: [Task_3]
- acceptance:
  - Full-screen UI, notification action, Task_24 stable identity, Task_26 receiver recovery, native event journal, Dart reconciliation, and current selection agree end to end.
  - Hosted Android JVM/APK/native-smoke evidence is tied to the exact reviewed head and all CI/review/hook/CLEAN/not-behind gates pass.
  - Remaining OEM lock-screen rendering, physical vibration/audio timing, and notification-action behavior are recorded as Task_16 physical-device evidence rather than silently waived.
  - Overlap with `alarm-sound-selection-plan.md` is attributed before its Android task begins; the sound task must consume the final shared ringing lifecycle instead of duplicating it.
- validation:
  - kind: command; required: true; owner: orchestrator; detail: exact-head GitHub Actions full Android JVM suite, Flutter CI, debug APK, Android native smoke, format/static checks, and git diff-check.
  - kind: review; required: true; owner: reviewer; detail: repository-wide Android ringing, notification, identity, journal, privacy, accessibility, and failure-lifecycle review.

## Task Waves

- Wave 1 (contract after remediation): [Task_1]
- Wave 2 (full-screen UI): [Task_2]
- Wave 3 (notification action): [Task_3]
- Wave 4 (integration): [Task_4]

## Cross-plan Ordering

- Do not dispatch before codebase-remediation Tasks 15, 24, and 26 complete.
- `alarm-sound-selection-plan.md` Task_1, Flutter Task_2, and iOS Task_4 may proceed when their own dependencies permit.
- The Android sound task must start only after this plan's Task_3 merges because both features share `AlarmStopActivity` and the native ringing lifecycle.

## Rollback / Safety

- Keep the existing full-screen Activity and notification tap behavior as the fallback while action delivery is unavailable.
- Prefer reverting the action wiring independently over weakening exact-current-only ownership, journal durability, or lock-screen privacy.
- Resource/layout rollback must not change persisted alarm identity or make an alarm silent.
- Do not remove calendar drafts, reports, historical plans, lessons, device artifacts, or user-owned parent changes.

## Progress Log

- 2026-07-22: Added at user request. Execution is queued behind remediation Tasks 15, 24, and 26; heavy validation remains CI-only under the active battery override.
