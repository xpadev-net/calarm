# Plan: Wake Alarm MVP Release Artifacts

- status: blocked
- generated: 2026-07-08
- last_updated: 2026-07-08
- work_type: ci_docs

## Goal

Add release/distribution setup that lets a GitHub Release receive an installable Android validation APK for real-device testing, and add a safe manual/guarded TestFlight internal-testing path for iOS without storing secrets or claiming unresolved runtime gates are approved.

## Scope / Non-goals

Scope:

- GitHub Actions release/distribution workflow for an Android validation APK.
- QA documentation for Android artifact behavior and iOS TestFlight internal-testing setup.
- Release-readiness wording that preserves blocked iOS 26+ and Android API 36 runtime gates.

Non-goals:

- Product code changes.
- Apple private keys, certificates, provisioning profiles, keystores, passwords, or other secrets.
- Unguarded TestFlight upload or any claim that upload means runtime approval.
- Any claim that distribution artifacts approve real-device runtime behavior.

## Tasks

### Task_1: Release APK and iOS Distribution Setup

- type: chore
- owns:
  - `.github/workflows/**`
  - `docs/qa/**`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-implementation-plan.md`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-release-artifacts-plan.md`
- depends_on: []
- acceptance:
  - GitHub Release workflow can build an Android validation APK and attach it to an existing GitHub Release.
  - Artifact names and README identify the APK as debug-signed validation-only and not release approval.
  - iOS TestFlight internal-testing automation is manual, guarded by required secrets, and fails fast when signing/App Store Connect setup is absent.
  - iOS documentation identifies TestFlight internal testing as the intended validation distribution path and keeps Ad Hoc as a fallback.
  - Required Android/iOS secrets and external Apple setup are documented without committing credentials.
  - Release-readiness docs continue to mark iOS 26+ and Android API 36 real-device runtime gates BLOCKED.
- validation:
  - kind: diff
    required: true
    owner: worker
    detail: "Run `git diff --check origin/master...HEAD && git diff --check`."
  - kind: yaml
    required: true
    owner: worker
    detail: "Validate workflow YAML syntax with available local tooling."
  - kind: build
    required: true
    owner: worker
    detail: "Run the selected Flutter Android build command if a compatible local SDK is available; otherwise record the exact blocker."
  - kind: review
    required: true
    owner: worker
    detail: "Run deep-review self-review focused on release artifact safety, GitHub token permissions, secret handling, and blocked runtime-gate wording."
  - kind: review
    required: true
    owner: reviewer
    detail: "Obtain independent review when tooling is available."
  - kind: pr
    required: true
    owner: worker
    detail: "Open/update PR, run `gh-review-hook <PR>` until exit 0 when tooling is available, and do not merge."

## Task Waves

- Wave 1 (parallel): Task_1

## Decision Log

- 2026-07-08: Use a debug-signed Android validation APK because the repo does not currently provide release-signing secrets and the Android release build type still uses the debug signing config.
- 2026-07-08: Orchestrator clarified iOS distribution should target TestFlight internal testing. Implement a manual `workflow_dispatch` TestFlight job guarded by signing/App Store Connect secrets, using the repo's Flutter iOS project and local Xcode `xcrun altool` upload capability.
- 2026-07-08: Independent review found manual dispatch could otherwise attach an artifact built from a mismatched workflow ref to a release tag. The workflow now checks out `refs/tags/<release_tag>`, verifies the checked-out commit matches the tag commit, and writes source commit provenance into the Android artifact README.

## Progress Log

- 2026-07-08: Task_1 started on branch `codex/release-device-artifacts`.
- 2026-07-08: Updated workflow/docs for TestFlight internal-testing target after orchestrator clarification.
- 2026-07-08: Implementation validation completed:
  - `git diff --check origin/master...HEAD && git diff --check`: PASS.
  - `ruby -e 'require "yaml"; ... YAML.load_file(...)' .github/workflows/baseline-ci.yml .github/workflows/native-smoke.yml .github/workflows/release-distribution.yml`: PASS.
  - Targeted workflow semantic checks for tag checkout/provenance, Android debug APK upload, guarded TestFlight secrets, `flutter build ipa`, and `xcrun altool --upload-app`: PASS.
  - `/Users/xpadev/fvm/versions/3.35.7/bin/flutter build apk --debug`: BLOCKED during dependency resolution because installed Dart is `3.9.2` and `pubspec.yaml` requires SDK `^3.12.2`.
  - `actionlint`: BLOCKED because it is not installed in this environment.
  - Independent review: APPROVED after fixing release-tag provenance.
  - PR creation / `gh-review-hook`: BLOCKED because `gh` and `gh-review-hook` are not installed in this environment.
