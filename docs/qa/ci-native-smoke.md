# CI Native Smoke

Wave 8 Task_5 adds hosted simulator/emulator smoke coverage for the native alarm bridge. This evidence is limited to CI simulator or emulator behavior and is labeled `NEAR_DEVICE` only when a hosted runtime executes the smoke test. It is labeled `BLOCKED` when the hosted runner lacks the required SDK, runtime, emulator image, or bootable simulator/emulator.

## Workflows

- Baseline CI remains in `.github/workflows/baseline-ci.yml` as the ordinary pull request validation for `flutter pub get`, `dart format --set-exit-if-changed .`, `flutter analyze`, and `flutter test`.
- Native Smoke CI is in `.github/workflows/native-smoke.yml` and runs on pull requests touching native smoke areas, on a weekly schedule, and by manual dispatch.
- Native Smoke CI uploads `android-native-smoke` and `ios-native-smoke` artifacts containing Flutter logs, native build logs, simulator/emulator logs, optional screenshots, and per-platform Markdown summaries.

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
- Build the debug APK.
- Install and run `integration_test/native_alarm_smoke_test.dart` on the selected emulator.
- Exercise `getCapability`, `scheduleOccurrences`, `cancelOccurrences`, `scheduleTestAlarm`, and best-effort cleanup cancel paths through the native MethodChannel.
- Upload Flutter logs, emulator logs, `adb logcat`, and optional `dumpsys alarm`.

Release status: Android CI emulator evidence does not approve real-device Android API 36 wake delivery, lock/terminated behavior, full-screen stop UI, notification/Silent/Focus-equivalent behavior, or reboot restore. Those gates remain release-blocking until real-device QA explicitly passes.

## iOS Hosted Evidence

Target preference: iOS 26+ simulator SDK and runtime on a macOS hosted runner.

Fallback: if the iOS 26+ simulator SDK is unavailable, the workflow records `BLOCKED` and skips the smoke because the AlarmKit bridge cannot be meaningfully built. If the SDK is available but the closest hosted simulator runtime is below iOS 26, the workflow can still build and run the MethodChannel unavailable-path smoke, but the summary remains `BLOCKED`.

Smoke steps when supported:

- Resolve Flutter dependencies.
- Record Xcode, simulator SDK, and simulator runtime inventory.
- Build the iOS simulator app.
- Boot the closest available simulator, preferring iOS 26+.
- Run `integration_test/native_alarm_smoke_test.dart`.
- Upload Flutter logs, `simctl` logs, and a screenshot when available.

Release status: iOS CI simulator evidence does not approve real-device iOS 26+ wake delivery, lock/terminated behavior, Silent/Focus behavior, or full-screen stop UI. Those gates remain release-blocking until real-device QA explicitly passes.

## Current Expected Labels

| Platform | Hosted target | CI result label | Release runtime approval |
| --- | --- | --- | --- |
| Android | API 36 emulator preferred, API 35 fallback | `NEAR_DEVICE` only when API 36 boots and smoke passes; API 35 fallback or unavailable emulator is `BLOCKED` | Not approved |
| iOS | iOS 26+ simulator preferred | `NEAR_DEVICE` only with iOS 26+ simulator runtime; otherwise `BLOCKED` | Not approved |
