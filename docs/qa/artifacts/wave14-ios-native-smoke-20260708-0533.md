# Wave 14 iOS Native Smoke Artifact Reference

Source: GitHub Actions Native Smoke CI run `28920020031`, job `85795058139`.

- Workflow event: `workflow_dispatch`
- Branch: `master`
- Head SHA: `905de9f2aa614abab30c97403c53e01f5a3267fb`
- Run URL: `https://github.com/xpadev-net/calarm/actions/runs/28920020031`
- Job URL: `https://github.com/xpadev-net/calarm/actions/runs/28920020031/job/85795058139`
- Artifact: `ios-native-smoke`
- Artifact files inspected:
  - `logs/ios-build-simulator-debug.log`
  - `logs/ios-flutter-devices.log`
  - `logs/ios-native-smoke-test.log`
  - `logs/ios-screenshot.png`
  - `logs/ios-simctl-log-show.log`
  - `logs/ios-simctl-runtimes.json`
  - `logs/ios-simctl-runtimes.txt`
  - `logs/ios-xcodebuild-version.log`
  - `summary/ios-summary.md`

Summary from retrieved artifact:

- status: `BLOCKED`
- selected runtime: iOS 26.5 (`com.apple.CoreSimulator.SimRuntime.iOS-26-5`)
- detected iphonesimulator SDK: 26.5
- Xcode: 26.5, build 17F42
- smoke log outcome: `CALARM_NATIVE_SMOKE_OUTCOME=BLOCKED`
- reason: `scheduleOccurrences` and `scheduleTestAlarm` returned `permissionMissing`; `cancelOccurrences` was skipped because no `platformAlarmId` was returned
- runtime approval: not approved; real-device iOS 26+ wake, lock/terminated, Silent/Focus, and full-screen stop UI gates remain BLOCKED

Interpretation:

- The hosted workflow built the iOS simulator app and ran the MethodChannel smoke test on an iOS 26.5 simulator.
- The result remains `BLOCKED`, not `NEAR_DEVICE`, because critical schedule/cancel/test-alarm operations did not all succeed.
- This artifact does not approve iOS real-device release runtime behavior.
