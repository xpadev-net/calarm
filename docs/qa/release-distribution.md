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

The validation workflow intentionally builds a debug APK and does not represent a release-signed artifact. The separate guarded Play workflow supplies CI signing properties to `android/app/build.gradle.kts`; release packaging without those properties fails fast instead of using the debug key.

## Android Google Play Closed Testing

Workflow: `.github/workflows/release-distribution.yml`

Trigger:

- `workflow_dispatch` with `release_tag: <existing GitHub Release tag>` and `upload_android_play_internal: true`.
- Optional `android_build_number`; when omitted, the workflow uses `GITHUB_RUN_NUMBER` as the Android version code.

The job runs in the `google-play-internal` GitHub Environment so repository administrators can require reviewers before a Play upload. It is separate from the debug validation APK job and never runs on GitHub Release publication.

Required GitHub secrets, preferably environment-scoped:

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded Android upload/release keystore. |
| `ANDROID_KEYSTORE_PASSWORD` | Password for the keystore. |
| `ANDROID_KEY_ALIAS` | Key alias inside the keystore. |
| `ANDROID_KEY_PASSWORD` | Password for the signing key. |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Full Workload Identity Provider resource name. |
| `GCP_SERVICE_ACCOUNT_EMAIL` | Google Cloud service-account email impersonated by GitHub Actions. |

Required Google Play setup:

- The Play Console app must already exist for package `dev.xpa.calarm`.
- Enable the Google Play Developer API in the Google Cloud project used by the service account.
- Configure GitHub OIDC Workload Identity Federation and restrict the provider to repository ID `1290079769`.
- Invite the service account in Play Console and grant only the app-level release permission needed to manage testing releases.
- Register the matching Android upload key in Play Console. Uploads are rejected if the AAB is signed with a different key or if the version code is not greater than the existing one.
- Configure internal testers/groups in Play Console separately; this workflow uploads the release but does not manage tester membership.

Behavior when explicitly enabled:

- Fails before building when any signing or Play secret is absent.
- Checks out and verifies the exact commit referenced by `release_tag`.
- Decodes the keystore and writes signing properties only under `$RUNNER_TEMP`.
- Builds `build/app/outputs/bundle/release/app-release.aab` with release signing and uploads it to the `closed` track with status `completed`.
- Uses `android_build_number` or the GitHub run number as the version code.
- Deletes the temporary keystore and signing properties on success and failure, and uploads build logs as a workflow artifact.

The Android release build requires `CALARM_ANDROID_SIGNING_PROPERTIES` when a release packaging task runs; this is supplied only by the guarded Play job. Debug validation builds remain available locally and in the existing artifact job, while release packaging fails fast without CI signing inputs instead of silently using the debug key.

The repository does not store keystores, passwords, generated signing properties, service-account keys, or upload credentials. A successful closed-testing upload only means that Google Play accepted the bundle for processing/testing; it does not approve the release-readiness gates described below or promote anything to production.

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
