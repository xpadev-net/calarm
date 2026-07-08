# Plan: Wake Alarm MVP Release Artifacts and Device Distribution

- status: in_progress
- generated: 2026-07-08
- last_updated: 2026-07-08
- work_type: ci

## Goal

- 実機検証を進められるように、GitHub Release から Android 検証用 APK を取得できるようにし、iOS 検証配布は IPA / Ad Hoc / TestFlight のどの経路を使うべきかを明確化し、必要なセットアップをリポジトリに記録する。

## Definition of Done

- GitHub Release または手動 release workflow から Android 実機検証用 APK を取得できる。
- APK が production approval artifact ではなく real-device validation artifact であることが明記されている。
- iOS の IPA 配布可否、Ad Hoc 配布条件、TestFlight が必要になる条件が公式情報ベースで docs に整理されている。
- TestFlight を使う場合に必要な GitHub Secrets / Apple Developer / App Store Connect 作業が漏れなく docs に整理されている。
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
  Add a release/distribution workflow and documentation so Android real-device validation can start from a GitHub Release APK, and iOS validation has a precise TestFlight/Ad Hoc setup path.
- acceptance:
  - A GitHub Actions workflow can build an Android installable APK and upload it to an existing GitHub Release or create/update a validation prerelease from a tag/workflow_dispatch.
  - Workflow permissions and triggers are least-privilege for release asset upload.
  - Artifact names and release notes make clear the APK is for validation and does not approve Android API 36 runtime gates.
  - iOS documentation explains that arbitrary IPA sideloading is not a general replacement for TestFlight, and records Ad Hoc requirements for registered-device testing.
  - TestFlight setup docs list required Apple/App Store Connect records, signing/provisioning choices, GitHub secrets, build-number/version behavior, and the remaining manual steps before an automated upload can run.
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

## Decision Log

- 2026-07-08 Decision: Treat GitHub Release APK as validation distribution, not release approval.
  - Trigger / new insight: Real-device validation needs installable artifacts before runtime evidence can be collected.
  - Plan delta (what changed): Add a release artifact workflow and distribution docs while preserving the existing BLOCKED runtime gates.
  - Tradeoffs considered: Debug/validation APKs can unblock Android device checks quickly, while production-quality signed releases and TestFlight require secrets and Apple account setup.
  - User approval: user requested enabling GitHub Release APK generation and TestFlight setup if needed.
