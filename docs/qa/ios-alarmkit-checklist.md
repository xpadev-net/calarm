# iOS AlarmKit Runtime Checklist

Wave 8 Task_2 implementation evidence is separate from release approval. Missing iOS 26+ real-device/runtime evidence remains release-blocking until these rows are rerun on a matching device or runtime.

## Local Build Evidence

| Check | Status | Evidence | Notes |
| --- | --- | --- | --- |
| Swift bridge typecheck against iOS 26.5 simulator SDK | PASS | `rtk xcrun swiftc -typecheck -sdk .../iPhoneSimulator26.5.sdk -target arm64-apple-ios26.0-simulator -F .../Flutter.xcframework/ios-arm64_x86_64-simulator ios/Runner/AlarmKitBridge.swift` exited 0. | Catches AlarmKit and Flutter API usage in the bridge file, but is not a full app build. |
| Full Flutter/Xcode iOS build | BLOCKED | `rtk flutter build ios --simulator --no-codesign`, `rtk xcodebuild ... -sdk iphoneos -destination generic/platform=iOS ... build`, and `rtk xcodebuild ... -sdk iphonesimulator -destination 'platform=iOS Simulator,OS=18.0,name=iPhone 16' ... build` all failed before compilation because Xcode reported no eligible destination and `iOS 26.5 is not installed`. | `rtk xcrun simctl list runtimes` showed only iOS 18.0 available. This blocks full native build/runtime evidence in this worker session. |

## Runtime Cases

| Case | Status | Evidence | Notes |
| --- | --- | --- | --- |
| iOS 26+ AlarmKit capability lookup returns permission state and schedule capability | BLOCKED | No iOS 26+ runtime/device execution was available in this worker session. | Bridge implemented against local iPhoneOS 26.5 SDK; runtime behavior not approved. |
| iOS 26+ permission request prompts or returns final AlarmKit authorization state | BLOCKED | No iOS 26+ runtime/device execution was available in this worker session. | Must verify `requestPermissionIfNeeded` on device/runtime before release approval. |
| iOS 26+ schedules one concrete occurrence and returns `platformAlarmId` | BLOCKED | No iOS 26+ runtime/device execution was available in this worker session. | Must verify returned ID can be persisted and later cancelled. |
| iOS 26+ schedules multiple concrete occurrences and reports per-occurrence failures | BLOCKED | No iOS 26+ runtime/device execution was available in this worker session. | Must verify partial failures preserve `(occurrenceId, wakePlanId)` correlation. |
| iOS 26+ cancels one occurrence by stored `platformAlarmId` | BLOCKED | No iOS 26+ runtime/device execution was available in this worker session. | Must verify cancellation uses the stored AlarmKit UUID returned by schedule. |
| iOS 26+ cancels all resolved alarms for a plan through `cancelPlan` payload rows | BLOCKED | No iOS 26+ runtime/device execution was available in this worker session. | Native bridge does not look up a logical plan ID; Flutter supplies resolved rows. |
| iOS 26+ schedules a test alarm using `scheduleTestAlarm` | BLOCKED | No iOS 26+ runtime/device execution was available in this worker session. | Must verify delivery and returned `platformAlarmId`; this worker did not approve wake delivery behavior. |
| Settings inline warning for iOS AlarmKit authorization problems | PASS | `rtk flutter test test/features/settings test/core/platform` covers denied/not-determined native alarm readiness warnings in the settings path. | Widget/controller evidence only; runtime AlarmKit authorization remains separate. |
| iOS 26+ AlarmKit authorization denial warning | BLOCKED | No iOS 26+ runtime/device execution was available in this worker session. | Must deny/revoke AlarmKit authorization and verify the live settings warning before release approval. |
| iOS 26+ 1-minute test alarm settings action | BLOCKED | Widget/controller tests verify `fireAfter: Duration(minutes: 1)` and failure preservation. | Must verify actual AlarmKit test-alarm delivery and returned platform ID on iOS 26+ before release approval. |
| Cleanup after runtime QA cancels every alarm created during the test session | BLOCKED | No iOS 26+ runtime/device execution was available in this worker session. | Use returned `platformAlarmId` values with `cancelOccurrences` or `cancelPlan`. |
