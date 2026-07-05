# Baseline CI

Baseline CI is the ordinary GitHub Actions validation for pull requests. It is intentionally limited to repository-level Flutter checks and does not replace later simulator or emulator native smoke validation.

## Triggers

- `pull_request`: runs for proposed changes before merge.
- `workflow_dispatch`: lets maintainers rerun the same validation manually.

## Toolchain

CI reads the Flutter SDK version from `.fvmrc` and installs that version with `subosito/flutter-action`. If `.fvmrc` is missing or does not contain a non-empty `flutter` value, the workflow fails instead of silently choosing a different SDK.

## Commands

The workflow runs these commands in order:

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

Dependency resolution runs before validation so analyzer and tests use the locked package graph for the selected Flutter SDK.

## Evidence

The workflow prints command output in the job log and uploads `baseline-ci-logs` with separate logs for dependency resolution, formatting, analyzer, and unit tests. The uploaded logs are intended to make format, analyzer, and test failures diagnosable without rerunning the job locally.

## Scope

Covered:

- Dart formatting check.
- Flutter analyzer and lint diagnostics.
- Flutter unit/widget tests run by `flutter test`.

Not covered:

- iOS or Android runtime alarm behavior.
- Simulator or emulator native smoke tests.
- Platform permission flows, exact alarm policy behavior, notification delivery, or app process wake-up behavior.
- Release signing, store policy, or deployment validation.

Native smoke CI for iOS 26+ and Android API 36 remains separate Wave 8 work.
