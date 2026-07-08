# Release Distribution Artifacts

Date: 2026-07-08

This document describes how Calarm release artifacts are produced for real-device validation. These artifacts help collect the missing runtime evidence; they do not change the release-readiness result.

Current release status remains **BLOCKED for normal MVP release** until the iOS 26+ and Android API 36 real-device runtime gates in `docs/qa/release-readiness.md` are validated with evidence.

## Android Validation APK

Workflow: `.github/workflows/release-distribution.yml`

Triggers:

- `release` with type `published`.
- `workflow_dispatch` with `release_tag`, which must name an existing GitHub Release.

Behavior:

- Checks out the repository.
- Checks out `refs/tags/<release_tag>` and fails if the checked-out commit does not match the tag commit.
- Reads the Flutter SDK version from `.fvmrc`.
- Runs `flutter pub get`.
- Runs `flutter build apk --debug`.
- Copies `build/app/outputs/flutter-apk/app-debug.apk` to `artifacts/release-distribution/android/calarm-android-validation-debug.apk`.
- Writes a SHA-256 checksum and a README that labels the artifact as validation-only and records the source commit.
- Uploads the artifact bundle to the workflow run.
- Attaches the APK, checksum, and README to the target GitHub Release with `gh release upload --clobber`.

Permissions:

- The workflow default is `contents: read`.
- The Android artifact job uses `contents: write` because attaching files to a GitHub Release requires write access to release contents.

Artifact status:

- Build mode: debug.
- Signing: Android debug signing key.
- Intended use: installable real-device validation on Android devices.
- Not intended use: Play Store submission, production distribution, release approval, or evidence that runtime gates passed.

The repository does not currently contain a release-signing configuration. `android/app/build.gradle.kts` still uses the debug signing config for the `release` build type, so the workflow intentionally builds a debug validation APK instead of pretending to produce a production-signed APK.

## Android Release-Signed Path

To add a production or release-candidate APK/AAB path later, configure signing without committing secrets. A safe GitHub Actions implementation should require these encrypted secrets or equivalent environment-scoped secrets:

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded Android upload/release keystore. |
| `ANDROID_KEYSTORE_PASSWORD` | Password for the keystore. |
| `ANDROID_KEY_ALIAS` | Key alias inside the keystore. |
| `ANDROID_KEY_PASSWORD` | Password for the signing key. |

The workflow should decode the keystore into `$RUNNER_TEMP`, write any generated signing properties into `$RUNNER_TEMP`, and delete temporary files at job end. The repo should not store keystores, passwords, generated signing properties, or upload keys.

Only after that setup exists should the release workflow build `flutter build apk --release` or `flutter build appbundle --release`. The artifact names and release notes must still separate installable validation artifacts from release approval evidence.

## iOS TestFlight Internal Testing

Target path: TestFlight internal testing.

An arbitrary IPA is not a general substitute for TestFlight. iOS devices will only install signed apps that match Apple's distribution rules. For Calarm validation, TestFlight internal testing is the preferred iOS distribution path because it avoids per-device UDID management for internal App Store Connect users.

Workflow: `.github/workflows/release-distribution.yml`

Trigger:

- `workflow_dispatch` with `release_tag: <existing GitHub Release tag>` and `upload_ios_testflight: true`.

The iOS TestFlight job does not run on GitHub Release publication. It is manual and guarded so release creation cannot imply that an iOS build was uploaded or validated. The `release_tag` input is required so the job can check out and build the exact GitHub Release tag before uploading to TestFlight.

Behavior when explicitly enabled:

- Fails fast if any required signing or App Store Connect secret is absent.
- Checks out `refs/tags/<release_tag>` and fails if the checked-out commit does not match the tag commit.
- Installs the Apple Distribution certificate into a temporary keychain.
- Installs the App Store provisioning profile from a secret.
- Writes the App Store Connect API private key under `$RUNNER_TEMP/private_keys`.
- Runs `flutter pub get`.
- Runs `flutter build ipa --release --export-options-plist "$IOS_EXPORT_OPTIONS_PLIST"`.
- Uploads the resulting IPA with `xcrun altool --upload-app` using App Store Connect API-key authentication.
- Uploads logs to the workflow run.

Required GitHub secrets:

| Secret | Purpose |
| --- | --- |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded `.p12` Apple Distribution certificate. |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for the `.p12` certificate. |
| `IOS_APP_STORE_PROVISIONING_PROFILE_BASE64` | Base64-encoded App Store provisioning profile for `dev.xpa.calarm`. |
| `IOS_EXPORT_OPTIONS_PLIST_BASE64` | Base64-encoded export options plist for App Store export. |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID. |
| `APP_STORE_CONNECT_API_ISSUER_ID` | App Store Connect issuer ID. |
| `APP_STORE_CONNECT_API_PRIVATE_KEY` | Private key content for the App Store Connect API key. |

Required Apple/App Store Connect setup:

- Apple Developer Program membership.
- An explicit App ID / Bundle ID for `dev.xpa.calarm`.
- An App Store Connect app record for that bundle identifier.
- A valid Apple Distribution certificate exported as `.p12`.
- An App Store provisioning profile for `dev.xpa.calarm`.
- An App Store Connect API key with permission to upload builds.
- Internal tester users or groups configured in App Store Connect.
- A unique uploaded build number for each TestFlight attempt. The workflow uses `ios_build_number` when provided, otherwise `GITHUB_RUN_NUMBER`.

The workflow does not store credentials, certificates, provisioning profiles, private keys, or generated signing material in the repo. Signing files and App Store Connect API key files are created under `$RUNNER_TEMP` during the job.

TestFlight upload status:

- Automation is implemented as an opt-in guarded workflow path.
- It is not locally executable in this worker because the required Apple signing material and App Store Connect secrets are intentionally absent.
- A successful upload only makes a build available for App Store Connect processing and internal testing assignment. It does not approve iOS 26+ AlarmKit runtime behavior.

## iOS Ad Hoc Alternative

Ad Hoc distribution is a fallback for a small, known set of registered devices. It requires Apple Developer account setup outside the repo:

- An explicit App ID for Calarm.
- An Apple Distribution certificate.
- Registered device UDIDs for every test device.
- An Ad Hoc provisioning profile that includes the App ID, certificate, and registered devices.
- Xcode signing configuration that uses the Ad Hoc profile for archive/export.

Do not commit certificates, private keys, provisioning profiles, export options containing private team data, or passwords to the repository. If Ad Hoc automation is added later, store sensitive values in GitHub encrypted secrets or an environment protected by reviewers.

Potential automation secrets:

| Secret | Purpose |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer team identifier. |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded `.p12` distribution certificate. |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for the `.p12` certificate. |
| `IOS_AD_HOC_PROVISIONING_PROFILE_BASE64` | Base64-encoded Ad Hoc provisioning profile. |
| `IOS_EXPORT_OPTIONS_PLIST_BASE64` | Base64-encoded export options plist for Ad Hoc export. |

## Evidence Boundaries

The Android validation APK and any future iOS Ad Hoc/TestFlight build are distribution mechanisms only. They are useful when collecting evidence for:

- iOS 26+ wake delivery, lock/terminated behavior, authorization denial, Silent/Focus behavior, stop/dismiss behavior, individual cancel, plan cancel, 13-equivalent reservations, 1-minute test alarm delivery, and cleanup.
- Android API 36 `setAlarmClock` delivery, lock/terminated behavior, exact alarm denial, notification denial, full-screen setting denial, channel disabled path, full-screen stop UI fallback, stop/dismiss behavior, individual cancel, plan cancel, 13-equivalent reservations, reboot/package-replace restore, 1-minute test alarm delivery, and cleanup.

Do not mark any of those rows PASS until the corresponding real-device QA logs/screenshots are attached under `docs/qa/artifacts/` and referenced from `docs/qa/release-readiness.md`.
