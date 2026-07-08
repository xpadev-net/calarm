# Plan: Wake Alarm MVP Release Artifacts and Device Distribution

- status: in_progress
- generated: 2026-07-08
- last_updated: 2026-07-08
- work_type: ci

## Goal

- 実機検証を進められるように、GitHub Release から Android 検証用 APK を取得できるようにし、iOS 検証配布は TestFlight 内部テストを前提に、必要なセットアップと可能な安全な自動化をリポジトリに記録する。

## Definition of Done

- GitHub Release または手動 release workflow から Android 実機検証用 APK を取得できる。
- APK が production approval artifact ではなく real-device validation artifact であることが明記されている。
- iOS は TestFlight 内部テストを想定し、App Store Connect / Apple Developer / GitHub Secrets / signing setup と、可能なら secret-driven なアップロード workflow が整理されている。
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
  - iOS distribution target is TestFlight internal testing. If safe automation is feasible, the workflow is manual/guarded, secret-driven, and fails fast or skips clearly when signing/App Store Connect setup is absent.
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

### Task_2: Baseline CI Date/Calendar Test Follow-up
- type: test
- status: complete
- owns:
  - `test/features/week_calendar/presentation/week_calendar_placeholder_test.dart`
  - `test/features/week_calendar/**`
  - `lib/features/week_calendar/**`
  - `lib/core/time/**`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-release-artifacts-plan.md`
- depends_on: []
- description: |
  Investigate and fix the repeated Baseline CI failure from PR #29. Timezone/current-date assumptions are plausible, but not assumed; compare them against repeat/skip logic, clock seeding, CI environment, and calendar-date conversion behavior.
- acceptance:
  - The root cause of the `CalendarDay:<2026-07-08>` vs `CalendarDay:<2026-07-09>` failure is documented.
  - Candidate causes are evaluated without prematurely assuming timezone is the root cause.
  - If caused by timezone/current-date assumptions, the affected test or code path is made deterministic using existing clock/time helpers where possible.
  - If production code is responsible, the fix is narrow and covered by regression evidence.
  - PR #29 can consume the fix by merging `master` once this follow-up lands.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "git diff --check origin/master...HEAD && git diff --check"
  - kind: command
    required: true
    owner: worker
    detail: "targeted week_calendar Flutter test(s), unless blocked by local SDK; if blocked, rely on PR CI and record exact blocker"
  - kind: review
    required: true
    owner: worker
    detail: "deep-review self-review plus independent review if available"
  - kind: command
    required: true
    owner: worker
    detail: "gh-review-hook <PR> exits 0 before merge-ready handoff"

### Task_3: iOS Native Smoke Timeout Alternative
- type: ci
- owns:
  - `.github/workflows/native-smoke.yml`
  - `integration_test/native_alarm_smoke_test.dart`
  - `docs/qa/ci-native-smoke.md`
  - `docs/qa/artifacts/**`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-release-artifacts-plan.md`
- depends_on: []
- description: |
  Investigate the iOS simulator native-smoke timeout from PR #29 and implement a safer CI alternative that preserves honest BLOCKED/NEAR_DEVICE wording.
- acceptance:
  - The timeout cause is investigated and documented from PR #29 / native-smoke logs.
  - The chosen alternative avoids hanging CI and still produces useful release-artifact validation evidence.
  - Simulator evidence remains explicitly not equivalent to iOS 26+ real-device AlarmKit runtime approval.
  - PR #29 can consume the fix by merging `master` once this follow-up lands.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "git diff --check origin/master...HEAD && git diff --check"
  - kind: command
    required: true
    owner: worker
    detail: "workflow YAML syntax validation and extractable shell/script syntax checks where feasible"
  - kind: command
    required: true
    owner: worker
    detail: "run or trigger relevant native smoke validation if feasible; otherwise record exact blocker and rely on PR CI"
  - kind: review
    required: true
    owner: worker
    detail: "deep-review self-review plus independent review if available"
  - kind: command
    required: true
    owner: worker
    detail: "gh-review-hook <PR> exits 0 before merge-ready handoff"

## Progress Log

- 2026-07-08 Plan created after final release readiness documented BLOCKED and user requested GitHub Release APK generation plus iOS/TestFlight setup path.
- 2026-07-08 User clarified iOS distribution should proceed for TestFlight internal testing. Follow-up sent to worker thread `019f4088-edf4-7481-8f1f-1bc2930a0323` with requested model `gpt-5.5` and reasoning `medium`.
- 2026-07-08 PR #29 blocked at merge gates.
  - PR: https://github.com/xpadev-net/calarm/pull/29
  - Branch/head: `codex/release-device-artifacts` at `84f8c823608dc84e6f1b6910ab3e206e79393684`; worker reported local/remote clean.
  - Implemented scope: Android GitHub Release validation APK workflow plus manual guarded iOS TestFlight internal-testing upload/docs.
  - Worker validation/review: local diff checks, Ruby workflow YAML parse, targeted workflow semantic checks passed; independent review approved after release-tag provenance fix.
  - Merge-gate failures: PR remains draft and `UNSTABLE`; parent `gh pr view 29` confirms Baseline CI `Format, analyze, and test` failed, iOS simulator native smoke failed, Android native smoke passed, CodeRabbit/Socket passed.
  - Baseline failure: repeated out-of-scope product test `test/features/week_calendar/presentation/week_calendar_placeholder_test.dart` / `skips next target from detail and keeps following repeats`, expected `CalendarDay:<2026-07-08>`, actual `CalendarDay:<2026-07-09>`.
  - iOS native smoke failure: existing native-smoke workflow built the iOS simulator app, then `Run iOS simulator smoke` timed out with exit code 124 after simulator/native smoke execution.
  - Hook result: worker ran `PATH="/opt/homebrew/bin:/Users/xpadev/go/bin:$PATH" /Users/xpadev/go/bin/gh-review-hook 29`; it exited 2 because required checks failed.
  - Blocking decision needed: either approve a scoped follow-up/decomposition to fix the failing product test and iOS native-smoke timeout, or explicitly waive/override the failing required checks for this release-artifacts PR.
- 2026-07-08 Follow-up decomposition started after user direction.
  - User guidance: Baseline CI should inspect timezone/date assumptions as one plausible lead, not as a predetermined root cause; iOS smoke should evaluate alternatives; proceed as follow-up work.
  - Task_2 queued: pending worktree `local:eb96f702-fcb4-4266-b4c9-8ccd4cafa877`; branch `codex/release-followup-baseline-timezone`; requested model `gpt-5.5`; reasoning `medium`.
  - Task_3 queued: pending worktree `local:3887ba65-1477-46f7-91d5-d417e9948cc5`; branch `codex/release-followup-ios-smoke-alternative`; requested model `gpt-5.5`; reasoning `medium`.
  - PR #29 remains draft/blocked until these follow-ups merge or a separate explicit waiver/override is approved.
- 2026-07-08 Task_2 worker branch PR created by orchestrator due worker-local GitHub tooling gap.
  - Worker thread: `019f40ae-9bbd-7132-af5d-bf6779cdc0ef`.
  - Worker report: implementation committed and pushed at `ea949066aa057f3215bc7ec01f8aa072332cdf24`; local worker could not create PR or run `gh-review-hook` because `gh` and `gh-review-hook` were unavailable there.
  - Reported root cause: `WeekCalendarPlaceholder` and `weekCalendarWakePlansProvider` used `weekCalendarClockProvider`, but `weekCalendarWakePlanServiceProvider` constructed `WakePlanService` without that clock, so service-side skip/next calculations used `DateTime.now`; on CI with real date `2026-07-09`, the frozen-clock test expected `CalendarDay<2026-07-08>` while service state advanced to `CalendarDay<2026-07-09>`.
  - Orchestrator action: created draft PR #31 (`https://github.com/xpadev-net/calarm/pull/31`) from branch `codex/release-followup-baseline-timezone`, confirmed diff is limited to `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`, and returned the non-merge-ready PR to the worker because PR is draft and checks are pending.
- 2026-07-08 Task_2 merged.
  - PR: https://github.com/xpadev-net/calarm/pull/31
  - Merge commit: `7264ea52f6373be00cea1f9cbc4ac36a6343a80a`.
  - Head merged: `41428ad4ad640d3efccc907a93c222f750ea1182`; worker merged `origin/master` normally into the PR branch after `gh-review-hook` reported the branch was behind.
  - Final diff: one insertion in `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`, passing `weekCalendarClockProvider` into `WakePlanService`.
  - Worker validation: targeted failing test passed, `flutter test test/features/week_calendar` passed with 24 tests, `flutter analyze` passed, and diff checks passed after the base merge.
  - Orchestrator validation: PR metadata/diff/current head inspected; deep-review common/UI/tests/investigation review found no in-scope issue; clean-worktree `gh-review-hook 31` exited 0; clean-worktree targeted failing test, `flutter test test/features/week_calendar`, `flutter analyze`, and diff checks passed.
  - Worker lifecycle: thread `019f40ae-9bbd-7132-af5d-bf6779cdc0ef` archived after merge.

## Decision Log

- 2026-07-08 Decision: Treat GitHub Release APK as validation distribution, not release approval.
  - Trigger / new insight: Real-device validation needs installable artifacts before runtime evidence can be collected.
  - Plan delta (what changed): Add a release artifact workflow and distribution docs while preserving the existing BLOCKED runtime gates.
  - Tradeoffs considered: Debug/validation APKs can unblock Android device checks quickly, while production-quality signed releases and TestFlight require secrets and Apple account setup.
  - User approval: user requested enabling GitHub Release APK generation and TestFlight setup if needed.

- 2026-07-08 Decision: Use TestFlight internal testing as the primary iOS validation distribution target.
  - Trigger / new insight: User asked to proceed on iOS assuming TestFlight internal testing.
  - Plan delta (what changed): Worker should prefer a safe, manual/guarded, secret-driven TestFlight upload path when feasible, and otherwise document exact App Store Connect/signing/GitHub Secrets blockers.
  - Tradeoffs considered: TestFlight internal testing avoids UDID management for testers, but requires App Store Connect app setup, signing assets, and API-key/private-key secrets that must never be committed.
  - User approval: user explicitly requested internal TestFlight setup work.

- 2026-07-08 Decision: Do follow-up fixes instead of waiving PR #29 gates.
  - Trigger / new insight: User indicated the Baseline CI failure should check timezone assumptions as a plausible lead and the smoke-test failure should be handled by considering alternatives.
  - Plan delta (what changed): Add Task_2 and Task_3 follow-up workers, then return to PR #29 after their fixes/evidence land.
  - Tradeoffs considered: Waiving PR #29 would ship useful artifact workflow sooner but would weaken required CI evidence. Follow-up PRs keep merge-gate discipline and isolate product-test/native-smoke changes from the release-distribution workflow.
  - User approval: user requested follow-up work.
