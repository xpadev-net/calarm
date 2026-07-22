# CI Native Smoke

Wave 8 Task_5 adds hosted simulator/emulator smoke coverage for the native alarm bridge. This evidence is limited to CI simulator or emulator behavior and is labeled `NEAR_DEVICE` only when a hosted runtime executes the smoke test. It is labeled `BLOCKED` when the hosted runner lacks the required SDK, runtime, emulator image, or bootable simulator/emulator.

## Workflows

- Baseline CI remains in `.github/workflows/baseline-ci.yml` as the ordinary pull request validation for `flutter pub get`, `dart format --set-exit-if-changed .`, `flutter analyze`, and `flutter test`.
- Native Smoke CI is in `.github/workflows/native-smoke.yml` and runs on pull requests touching native smoke areas, on a weekly schedule, and by manual dispatch.
- Native Smoke CI uploads `android-native-smoke` and `ios-native-smoke` artifacts containing Flutter logs, native build logs, simulator/emulator logs, optional screenshots, and per-platform Markdown summaries.
- Release Distribution Artifacts is in `.github/workflows/release-distribution.yml` and attaches `calarm-android-validation-debug.apk` to a GitHub Release for Android real-device validation. The same workflow has an opt-in guarded TestFlight internal-testing upload job for iOS. These are distribution setup only; they do not replace Native Smoke CI or approve any real-device runtime gate.

## Wave 14 Release Evidence Snapshot

Date: 2026-07-08

Evidence source: GitHub Actions inspected with `gh` after PR #26 merged.

Release baseline:

- PR #26 (`Wave 13 UI harmonization and accessibility pass`) merged into `master` at 2026-07-08T05:27:23Z with merge commit `abfb5a58c1311a4537338c102ee340bb7baef8cd`.
- `origin/master` release evidence head is `905de9f2aa614abab30c97403c53e01f5a3267fb` (`Complete Wave 13 and start Wave 14`), which is after the PR #26 merge commit.
- Baseline CI was manually rerun on `master` with `workflow_dispatch`: run `28920020032`, head SHA `905de9f2aa614abab30c97403c53e01f5a3267fb`, completed `success` at 2026-07-08T05:34:40Z.
- Baseline CI job `Format, analyze, and test` passed `flutter pub get`, `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`, and `baseline-ci-logs` upload.

Native smoke release evidence:

| Platform | Run / job | Hosted evidence label | Result | Evidence summary |
| --- | --- | --- | --- | --- |
| Android | Native Smoke CI run `28920020031`, job `85795058134`, `master` head `905de9f2aa614abab30c97403c53e01f5a3267fb` | `BLOCKED` | Workflow job succeeded, release smoke result remains blocked | Android debug APK built, but the hosted runner did not expose the required emulator executable at `/usr/local/lib/android/sdk/emulator/emulator`, so no API 36/API 35 emulator boot or MethodChannel smoke execution occurred. |
| iOS | Native Smoke CI run `28920020031`, job `85795058139`, `master` head `905de9f2aa614abab30c97403c53e01f5a3267fb` | `BLOCKED` | Workflow job succeeded, release smoke result remains blocked | Hosted macOS runner used Xcode 26.5, iPhoneSimulator SDK 26.5, and an iOS 26.5 simulator. The app built and the MethodChannel smoke test ran, but `scheduleOccurrences` and `scheduleTestAlarm` returned `permissionMissing`; `CALARM_NATIVE_SMOKE_OUTCOME=BLOCKED`. |

Retrieved artifact references:

- `docs/qa/artifacts/wave14-android-native-smoke-20260708-0533.md`
- `docs/qa/artifacts/wave14-ios-native-smoke-20260708-0533.md`

Release interpretation:

- The Baseline CI release hygiene gate is green for the `master` head inspected above.
- Native Smoke CI is runnable manually and uploaded per-platform artifacts on `master`, but both simulator/emulator results remain `BLOCKED`.
- These CI results are simulator/emulator evidence only. They do not approve real-device Android API 36 or iOS 26+ wake delivery, lock/terminated behavior, Silent/Focus behavior, full-screen stop UI, cancel semantics, 13-equivalent reservations, or Android reboot restore.
- Real-device iOS 26+ and Android API 36 runtime validation remains BLOCKED/user-deferred and release-blocking unless a separate product/release decision explicitly chooses a waiver or platform-limited path.

## Baseline Artifact Runtime Warning

The Baseline CI warning was caused by `actions/upload-artifact@v4`, whose action metadata declares `runs.using: node20`, while GitHub hosted runners now force older Node actions onto Node.js 24. The supported upstream action/runtime path was verified with `gh`:

- `actions/upload-artifact@v4`: `runs.using: node20`.
- `actions/upload-artifact@v5`: `runs.using: node20`.
- `actions/upload-artifact@v7.0.1`: `runs.using: node24`.

Baseline CI now uses the `actions/upload-artifact@v7.0.1` commit SHA `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` without changing the `baseline-ci-logs` artifact name, path, or `if-no-files-found: warn` behavior. This should remove the Node.js 20 forced-to-24 warning for the baseline artifact upload step while keeping the action immutable. If GitHub later changes action runtime enforcement again, rerun the metadata check against the current `actions/upload-artifact` release before changing pins.

## Android Hosted Evidence

Target preference: Android API 36 Google APIs x86_64 emulator image.

Fallback: Android API 35 Google APIs x86_64 emulator image when API 36 is not listed by `sdkmanager` on the hosted runner. An API 35 fallback can still catch build/install/MethodChannel regressions, but its summary is `BLOCKED` because the MVP Android API 36 hosted target was unavailable.

Smoke steps:

- Resolve Flutter dependencies.
- Verify the checkout matches the exact pull-request head (or dispatched/scheduled commit) and retain the tested SHA in the Android artifact.
- Run the complete Android JVM/Robolectric suite with `:app:testDebugUnitTest`; failure or timeout fails the Android job, and the captured Gradle log is uploaded even on failure.
- Build the debug APK.
- Install and run `integration_test/native_alarm_smoke_test.dart` on the selected emulator.
- Exercise `getCapability`, `scheduleOccurrences`, `cancelOccurrences`, `scheduleTestAlarm`, and best-effort cleanup cancel paths through the native MethodChannel.
- Parse the machine-readable smoke outcome from the test log and keep the summary `BLOCKED` unless schedule, cancel, test-alarm, and cleanup cancel semantics all succeed.
- Upload Flutter logs, emulator logs, `adb logcat`, and optional `dumpsys alarm`.

The JVM gate runs on every manual Native Smoke dispatch. The `run_android` input controls only the additional APK/emulator smoke work, so disabling emulator smoke cannot skip the required JVM suite.

Release status: Android CI JVM and emulator evidence does not approve real-device Android API 36 wake delivery, lock/terminated behavior, full-screen stop UI, notification/Silent/Focus-equivalent behavior, or reboot restore. Those gates remain release-blocking until real-device QA explicitly passes.

## iOS Hosted Evidence

Target preference: iOS 26+ simulator SDK and runtime on a macOS hosted runner.

Fallback: if the iOS 26+ simulator SDK is unavailable, the workflow records `BLOCKED` and skips the smoke because the AlarmKit bridge cannot be meaningfully built. If the SDK is available but the closest hosted simulator runtime is below iOS 26, the workflow can still build and run the MethodChannel unavailable-path smoke, but the summary remains `BLOCKED`.

Smoke steps when supported:

- Resolve Flutter dependencies.
- Record Xcode, simulator SDK, and simulator runtime inventory.
- Build the iOS simulator app.
- Boot the closest available simulator, preferring iOS 26+.
- Run `integration_test/native_alarm_smoke_test.dart`.
- Parse the machine-readable smoke outcome from the test log and keep the summary `BLOCKED` unless schedule, cancel, test-alarm, and cleanup cancel semantics all succeed.
- Treat hosted simulator permission-missing paths and runtime smoke timeouts as bounded `BLOCKED` evidence instead of failing the workflow after the simulator build has already passed. Ordinary non-timeout test failures still fail CI. This preserves build and log evidence while keeping the iOS 26+ real-device runtime gate blocked.
- Upload Flutter logs, `simctl` logs, and a screenshot when available.

Release status: iOS CI simulator evidence does not approve real-device iOS 26+ wake delivery, lock/terminated behavior, Silent/Focus behavior, or full-screen stop UI. Those gates remain release-blocking until real-device QA explicitly passes.

## Current Expected Labels

| Platform | Hosted target | CI result label | Release runtime approval |
| --- | --- | --- | --- |
| Android | API 36 emulator preferred, API 35 fallback | `NEAR_DEVICE` only when API 36 boots and critical native alarm operations pass; API 35 fallback, unavailable emulator, or native permission/unavailable/failure paths are `BLOCKED` | Not approved |
| iOS | iOS 26+ simulator preferred | `NEAR_DEVICE` only with iOS 26+ simulator runtime and successful critical native alarm operations; missing permission, unavailable, or native failure paths are `BLOCKED` | Not approved |
