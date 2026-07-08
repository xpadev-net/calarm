# Plan: Wake Alarm MVP Release Artifacts and Device Distribution

- status: blocked
- generated: 2026-07-08
- last_updated: 2026-07-08
- work_type: ci

## Goal

- 実機検証を進められるように、GitHub Release から Android 検証用 APK を取得できるようにし、iOS 検証配布は TestFlight 内部テストを前提に、必要なセットアップと可能な安全な自動化をリポジトリに記録する。

## Definition of Done

- GitHub Release または手動 release workflow から Android 実機検証用 APK を取得できる。
- APK が production approval artifact ではなく real-device validation artifact であることが明記されている。
- iOS は TestFlight 内部テストを想定し、App Store Connect / Apple Developer / GitHub Secrets / signing setup と、secret-driven なアップロード workflow が整理されている。
- IPA / Ad Hoc は補足経路として、任意配布できない理由と登録デバイス・証明書・provisioning profile 条件が docs に整理されている。
- 変更は PR 化され、worker validation、independent review、`gh-review-hook` を通過してから orchestrator が merge する。

## Scope / Non-goals

- Scope:
  - `.github/workflows/**`
  - `docs/qa/**`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-implementation-plan.md`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-release-artifacts-plan.md`
- Non-goals:
  - 未承認の Apple Developer 証明書、provisioning profile、App Store Connect API key、private key を作成・保存すること。
  - 実機検証結果を APPROVED として記録すること。
  - 製品コードの挙動変更。
  - Unguarded TestFlight upload or any claim that upload means runtime approval.

## Context

- GitHub Releases can include binary files and can be created or managed with GitHub CLI.
- Apple Ad Hoc IPA installation requires an App ID, distribution certificate, and registered test devices.
- TestFlight avoids manual UDID/provisioning tracking for testers, but requires App Store Connect setup and uploaded beta builds.

## Tasks

### Task_1: Release APK and iOS Distribution Setup
- type: ci
- owns:
  - `.github/workflows/**`
  - `docs/qa/**`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-implementation-plan.md`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-release-artifacts-plan.md`
- depends_on: []
- description: |
  Add a release/distribution workflow and documentation so Android real-device validation can start from a GitHub Release APK, and iOS validation can proceed through TestFlight internal testing when Apple/App Store Connect credentials and signing setup are available.
- acceptance:
  - A GitHub Actions workflow can build an Android installable APK and upload it to an existing GitHub Release or create/update a validation prerelease from a tag/workflow_dispatch.
  - Workflow permissions and triggers are least-privilege for release asset upload.
  - Artifact names and release notes make clear the APK is for validation and does not approve Android API 36 runtime gates.
  - iOS distribution target is TestFlight internal testing. The workflow is manual/guarded, secret-driven, and fails fast when signing/App Store Connect setup is absent.
  - TestFlight setup docs list required Apple/App Store Connect records, signing/provisioning choices, GitHub secrets, build-number/version behavior, internal tester setup, and the remaining manual steps before an automated upload can run.
  - iOS documentation explains that arbitrary IPA sideloading is not a general replacement for TestFlight, and records Ad Hoc requirements for registered-device testing only as a secondary path.
  - Parent and child ledgers are updated with the new release-artifact enablement status.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "git diff --check origin/master...HEAD && git diff --check"
  - kind: command
    required: true
    owner: worker
    detail: "Validate GitHub Actions workflow YAML syntax or dry-run equivalent available in this repo/tooling"
  - kind: command
    required: true
    owner: worker
    detail: "flutter build apk --debug or --release as selected for the validation APK, unless blocked by local SDK; if blocked, rely on PR CI and record exact blocker"
  - kind: review
    required: true
    owner: worker
    detail: "deep-review self-review plus independent review for release-artifact safety, GitHub token permissions, secret handling, and evidence wording"
  - kind: command
    required: true
    owner: worker
    detail: "gh-review-hook <PR> exits 0 before merge-ready handoff"

## Progress Log

- 2026-07-08 Plan created after final release readiness documented BLOCKED and user requested GitHub Release APK generation plus iOS/TestFlight setup path.
- 2026-07-08 User clarified iOS distribution should proceed for TestFlight internal testing. Follow-up sent to worker thread `019f4088-edf4-7481-8f1f-1bc2930a0323` with requested model `gpt-5.5` and reasoning `medium`.
- 2026-07-08 Task_1 implementation added on branch `codex/release-device-artifacts`.
- 2026-07-08 Implementation validation completed:
  - `git diff --check origin/master...HEAD && git diff --check`: PASS before upstream merge; rerun required after merge-conflict resolution.
  - `ruby -e 'require "yaml"; ... YAML.load_file(...)' .github/workflows/baseline-ci.yml .github/workflows/native-smoke.yml .github/workflows/release-distribution.yml`: PASS.
  - Targeted workflow semantic checks for tag checkout/provenance, Android debug APK upload, guarded TestFlight secrets, `flutter build ipa`, and `xcrun altool --upload-app`: PASS.
  - `/Users/xpadev/fvm/versions/3.35.7/bin/flutter build apk --debug`: BLOCKED during dependency resolution because installed Dart is `3.9.2` and `pubspec.yaml` requires SDK `^3.12.2`.
  - `actionlint`: BLOCKED because it is not installed in this environment.
  - Independent review: APPROVED after fixing release-tag provenance.
- 2026-07-08 Draft PR #29 opened: `https://github.com/xpadev-net/calarm/pull/29`.
  - PR is draft because `gh-review-hook` is not installed locally as a command, GitHub CLI alias, or GitHub CLI extension.
  - Initial PR merge state was DIRTY because `origin/master` added this plan after the worker branch started. Worker merged `origin/master` normally and resolved the owned plan conflict.
  - Post-merge local validation rerun: `git diff --check origin/master...HEAD && git diff --check` PASS; Ruby workflow YAML parse PASS.
  - Merge-resolution commit pushed at `2d3767c6ae9780156358f239d5f6aa9139c73dd5`; GitHub reports PR merge state `UNSTABLE` with Baseline CI, Native Smoke CI, Socket Security, and CodeRabbit queued/pending.

## Decision Log

- 2026-07-08 Decision: Treat GitHub Release APK as validation distribution, not release approval.
  - Trigger / new insight: Real-device validation needs installable artifacts before runtime evidence can be collected.
  - Plan delta (what changed): Add a release artifact workflow and distribution docs while preserving the existing BLOCKED runtime gates.
  - Tradeoffs considered: Debug/validation APKs can unblock Android device checks quickly, while production-quality signed releases and TestFlight require secrets and Apple account setup.
  - User approval: user requested enabling GitHub Release APK generation and TestFlight setup if needed.

- 2026-07-08 Decision: Use TestFlight internal testing as the primary iOS validation distribution target.
  - Trigger / new insight: User asked to proceed on iOS assuming TestFlight internal testing.
  - Plan delta (what changed): Added a safe, manual/guarded, secret-driven TestFlight upload path using the repo Flutter iOS project and local Xcode `xcrun altool` upload capability.
  - Tradeoffs considered: TestFlight internal testing avoids UDID management for testers, but requires App Store Connect app setup, signing assets, and API-key/private-key secrets that must never be committed.
  - User approval: user explicitly requested internal TestFlight setup work.

- 2026-07-08 Decision: Check out release tags for distribution artifacts.
  - Trigger / new insight: Independent review found manual dispatch could attach an artifact built from a mismatched workflow ref to a release tag.
  - Plan delta (what changed): The workflow now checks out `refs/tags/<release_tag>`, verifies the checked-out commit matches the tag commit, and writes source commit provenance into the Android artifact README.
  - Tradeoffs considered: Building from the tag is stricter than building from the workflow-selected ref and prevents false release artifact provenance.
