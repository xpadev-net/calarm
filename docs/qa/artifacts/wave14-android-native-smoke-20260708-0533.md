# Wave 14 Android Native Smoke Artifact Reference

Source: GitHub Actions Native Smoke CI run `28920020031`, job `85795058134`.

- Workflow event: `workflow_dispatch`
- Branch: `master`
- Head SHA: `905de9f2aa614abab30c97403c53e01f5a3267fb`
- Run URL: `https://github.com/xpadev-net/calarm/actions/runs/28920020031`
- Job URL: `https://github.com/xpadev-net/calarm/actions/runs/28920020031/job/85795058134`
- Artifact: `android-native-smoke`
- Artifact files inspected:
  - `logs/android-build-apk-debug.log`
  - `logs/android-flutter-pub-get.log`
  - `summary/android-summary.md`

Summary from retrieved artifact:

- status: `BLOCKED`
- preferred target: Android API 36 emulator
- reason: Required Android emulator tool was unavailable: `/usr/local/lib/android/sdk/emulator/emulator`
- evidence: hosted runner environment
- runtime approval: not approved; real-device Android API 36 wake, lock/terminated, full-screen UI, Silent/Focus-equivalent, and reboot restore gates remain BLOCKED

Interpretation:

- The hosted workflow built the debug APK successfully before the smoke step.
- No Android emulator booted, so no Android MethodChannel smoke result can be labeled `NEAR_DEVICE`.
- This artifact does not approve Android real-device release runtime behavior.
