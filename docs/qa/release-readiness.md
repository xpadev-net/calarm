# MVP Release Readiness

Date: 2026-07-08

Overall result: **BLOCKED for normal MVP release**.

Reason: app-level implementation and baseline CI evidence exist for the representative MVP flows, but iOS 26+ and Android API 36 real-device runtime validation remains absent/user-deferred. Simulator/emulator and widget evidence is not sufficient to approve an alarm app release gate for wake delivery, lock/terminated behavior, permission policy behavior, stop UI behavior, cancel semantics, 13-equivalent reservations, or Android reboot restore.

## Evidence Sources

- Parent plan: `docs/coding-agent/plans/active/wake-alarm-mvp-implementation-plan.md`
- Wave 14 plan: `docs/coding-agent/plans/active/wake-alarm-mvp-wave-14-mvp-qa-release-plan.md`
- Completed Wave 1-13 plans under `docs/coding-agent/plans/completed/`
- Baseline CI evidence: `docs/qa/ci-baseline.md`
- Native smoke release evidence: `docs/qa/ci-native-smoke.md`
- iOS runtime checklist: `docs/qa/ios-alarmkit-checklist.md`
- Android runtime checklist: `docs/qa/android-alarm-checklist.md`
- UI review evidence: `docs/qa/ui-review.md`
- Wave 14 native smoke artifacts:
  - `docs/qa/artifacts/wave14-android-native-smoke-20260708-0533.md`
  - `docs/qa/artifacts/wave14-ios-native-smoke-20260708-0533.md`

## Release Gate Matrix

| Gate | App / CI evidence | Release status | Evidence / blocker |
| --- | --- | --- | --- |
| Create Wake Plan | PASS | BLOCKED | Widget/service evidence covers calendar tap, create sheet preview, save, rendered block, overlap warning, schedule-failure warning, and repeat selection. Real-device native schedule delivery remains unapproved. |
| Edit Wake Plan | PASS | BLOCKED | Widget/service evidence covers edit rescheduling and old occurrence cancellation intent. Real-device old-native-alarm removal and replacement schedule delivery remain unapproved. |
| Delete Wake Plan | PASS | BLOCKED | Widget/service evidence covers destructive confirmation, future occurrence cancel intent, and keeping the plan when cancellation fails. Real-device OS alarm removal remains unapproved. |
| Repeat Wake Plan | PASS | BLOCKED | Domain/planner/service/UI evidence covers weekly repeat rules and rolling concrete occurrence generation. Real-device multiple future reservations remain unapproved. |
| Skip next | PASS | BLOCKED | Planner/service/UI evidence covers target-date skip, undo skip, removing next instance, and preserving following repeats. Real-device cancel/recreate behavior remains unapproved. |
| Test alarm | PASS | BLOCKED | Settings/controller evidence covers 1-minute test-alarm request and failure preservation. iOS simulator smoke returned `permissionMissing`; Android hosted smoke did not boot an emulator; real-device delivery remains unapproved. |
| Permission warning | PASS | BLOCKED | Settings/controller/widget evidence covers inline warnings for missing alarm permission and Android exact alarm, notification, full-screen, and channel readiness. Live iOS 26+/Android API 36 permission denial and post-return states remain unapproved. |
| Minimum vertical flow | PASS | BLOCKED | App-level evidence covers 07:00 target creation with 06:00-07:00 occurrence window and stop-current-alarm-only ringing affordance. The native requirement that one stopped alarm leaves later alarms scheduled remains unapproved on real devices. |
| Baseline CI | PASS | PASS for inspected release evidence head | Wave 14 Task_2 recorded successful Baseline CI run `28920020032` on `master` head `905de9f2aa614abab30c97403c53e01f5a3267fb`, covering `flutter pub get`, `dart format --set-exit-if-changed .`, `flutter analyze`, and `flutter test`. Current PR CI still requires PR creation/check inspection before merge-ready handoff. |
| CI native smoke | BLOCKED | BLOCKED | Android Native Smoke CI built the debug APK but could not run the required emulator executable. iOS Native Smoke CI built and ran on an iOS 26.5 simulator, but scheduling/test-alarm paths returned `permissionMissing`. These are not real-device approvals. |
| E2E / visual evidence | BLOCKED | BLOCKED | Wave 13 UI review recorded code/test review evidence and widget-level coverage, but full Playwright/browser screenshots are blocked because no seeded Flutter web route/harness exists. Native E2E evidence is blocked by absent real-device validation. |

## Wave 3 Deferred Runtime Gates

### iOS 26+

| Deferred case | Status | Evidence / blocker |
| --- | --- | --- |
| Wake delivery with AlarmKit | BLOCKED | No iOS 26+ real-device execution was provided. |
| Lock-screen behavior | BLOCKED | No iOS 26+ real-device lock-screen evidence was provided. |
| App terminated behavior | BLOCKED | No iOS 26+ real-device terminated-process evidence was provided. |
| AlarmKit authorization denied/not determined path | BLOCKED | Widget/controller warnings exist; live AlarmKit authorization denial was not validated on device. |
| Silent / Focus behavior | BLOCKED | No iOS 26+ real-device Silent/Focus evidence was provided. |
| Stop/dismiss behavior | BLOCKED | App-level stop-current-alarm flow has tests; real-device AlarmKit stop/dismiss behavior was not validated. |
| Individual occurrence cancel | BLOCKED | Bridge/service intent exists; device-level AlarmKit cancel by stored platform ID was not validated. |
| Plan cancel | BLOCKED | Resolved-row cancel contract exists; device-level plan cancel removal was not validated. |
| 13-equivalent reservations for 07:00 / 60 minutes / 5 minutes | BLOCKED | Planner test covers 13 occurrences; device-level AlarmKit reservation behavior was not validated. |
| 1-minute test alarm delivery | BLOCKED | Controller/widget evidence exists; iOS simulator smoke returned `permissionMissing`, and no real-device delivery evidence was provided. |
| Cleanup after QA | BLOCKED | No iOS 26+ real-device QA session ran, so no created platform alarms or cleanup log exists. |

### Android API 36

| Deferred case | Status | Evidence / blocker |
| --- | --- | --- |
| `setAlarmClock` wake delivery | BLOCKED | No Android API 36 real-device execution was provided. |
| Lock-screen behavior | BLOCKED | No Android API 36 real-device lock-screen evidence was provided. |
| App terminated behavior | BLOCKED | No Android API 36 real-device terminated-process evidence was provided. |
| Exact alarm denial path | BLOCKED | Widget/controller warnings exist; live OS denial flow was not validated on device. |
| Notification denial path | BLOCKED | Widget/controller warnings exist; live notification denial flow was not validated on device. |
| Full-screen intent setting denial path | BLOCKED | Widget/controller warnings exist; live full-screen setting denial flow was not validated on device. |
| Notification channel disabled path | BLOCKED | Native capability path is documented; live channel-disable warning was not validated on device. |
| Full-screen stop UI fallback | BLOCKED | Android native fallback UI exists; real lock-screen/full-screen behavior was not validated on device. |
| Stop/dismiss behavior | BLOCKED | App-level stop-current-alarm flow has tests; real-device stop/dismiss behavior was not validated. |
| Individual occurrence cancel | BLOCKED | Bridge/service intent exists; device-level `PendingIntent` removal was not validated. |
| Plan cancel | BLOCKED | Resolved-row cancel contract exists; device-level plan cancel removal was not validated. |
| 13-equivalent reservations for 07:00 / 60 minutes / 5 minutes | BLOCKED | Planner test covers 13 occurrences; device-level `setAlarmClock` reservation behavior was not validated. |
| Reboot/package-replace restore | BLOCKED | BootReceiver restore path exists; no Android API 36 reboot/package-replace runtime evidence was provided. |
| 1-minute test alarm delivery | BLOCKED | Controller/widget evidence exists; hosted Android smoke did not boot an emulator, and no real-device delivery evidence was provided. |
| Cleanup after QA | BLOCKED | No Android API 36 real-device QA session ran, so no created platform alarms or cleanup log exists. |

## Decision

Normal two-platform MVP release is **BLOCKED**.

No platform is release APPROVED. A waiver or platform-limited release would require a separate explicit product/release decision and must not relabel any unresolved real-device runtime gate as passed.

Minimum external evidence needed to unblock normal MVP release:

1. iOS 26+ real-device QA logs/screenshots for every iOS deferred runtime row above, including cleanup/cancel confirmation.
2. Android API 36 real-device QA logs/screenshots for every Android deferred runtime row above, including reboot/package-replace restore and cleanup/cancel confirmation.
3. A rerun of final QA after the real-device artifacts are added under `docs/qa/artifacts/`.

## Worker Validation

Local validation in this worker:

| Command | Result | Evidence |
| --- | --- | --- |
| `git diff --check origin/master...HEAD` | PASS | Exited 0. |
| `git diff --check` | PASS | Exited 0. |
| `/Users/xpadev/fvm/versions/3.35.7/bin/flutter analyze` | BLOCKED | Failed during dependency resolution: local Dart is `3.9.2`, while `pubspec.yaml` requires SDK `^3.12.2`. |
| `/Users/xpadev/fvm/versions/3.35.7/bin/flutter test` | BLOCKED | Failed during dependency resolution for the same Dart SDK mismatch after waiting for the Flutter startup lock. |

Remote validation relied on for release hygiene:

- Wave 14 Task_2 recorded Baseline CI run `28920020032` on `master` head `905de9f2aa614abab30c97403c53e01f5a3267fb` as PASS for `flutter pub get`, `dart format --set-exit-if-changed .`, `flutter analyze`, and `flutter test`.
- Remote CI native smoke evidence remains BLOCKED for both platforms, as recorded above.
- Current branch PR checks are not yet verified in this worker because `gh` and `gh-review-hook` are unavailable on PATH.
