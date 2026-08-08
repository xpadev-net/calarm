# Plan: Codex Security Findings Remediation (2026-07-23)

- status: open
- generated: 2026-07-23
- source_csv: docs/coding-agent/plans/active/codex-security-findings-2026-07-23.csv (not tracked in repo; obtain from the original Codex security findings export for this run)
- work_type: plan
- repository: xpadev-net/calarm

## Goal

Address all new findings in the provided CSV by producing a bounded remediation plan with concrete code targets, acceptance criteria, and required validation.  
The plan covers security findings, release gate integrity, and local persistence robustness regressions that affect alarm availability/ integrity.

## Scope / Non-goals

- In scope:
  - All findings in the provided CSV, excluding closed or duplicate historical issues outside scope.
  - Workflow hardening for Android and iOS release jobs.
  - Wake-plan scheduling, reconciliation, and native alarm delivery correctness in Dart and Android/iOS native layers.
  - Alarm-related persistence and UI robustness regressions introduced by these findings.
- Non-goals:
  - Product feature expansion or UX redesign.
  - Full release process re-architecture beyond minimum blast radius.
  - Any changes outside owned paths listed per task.

## Rules / Context

- `docs/coding-agent/rules/**` is absent in this repository; validation is inferred from existing workflow/config, test files, and this plan.
- High-level rule check result is recorded as missing; no hard blocker for planning-only work.
- Task status is set from findings and mapped into implementation tracks directly.

## Task List

### Task_01: Separate cache trust boundaries for guarded Android distribution job

- status: planned
- severity: high
- source: https://chatgpt.com/codex/cloud/security/findings/d199903fe37481918e5496a6b361a5f3
- commit_hash: 869e1ffc9da11630b091c1c6890b1746a2575d09
- owns:
  - `github/workflows/release-distribution.yml`
- depends_on: []
- acceptance:
  - Production-signed deployment job never restores cache entries written by untrusted validation job context.
  - Cache restore keys for trusted jobs include a signature/authenticated partition and do not fall back to non-matching hashes.
  - Flutter/Gradle/Pub cache setup is deterministic per trust boundary.
- validation:
  - kind: command; required: true; owner: worker; detail: `actionlint github/workflows/release-distribution.yml` and focused YAML diff inspection for key/restore logic.
  - kind: review; required: true; owner: reviewer; detail: release trust-boundary review of deployment path and secret exposure controls.

### Task_02: Prevent far-future inline draft dates from entering unschedulable success path

- status: planned
- severity: high
- source: https://chatgpt.com/codex/cloud/security/findings/d71705652d308191a8d066d5b3844a7e
- commit_hash: 3a04fccb34e9ca631ee451ee0e94b0a84fbb8d34
- owns:
  - `lib/features/wake_plan/ui/inline_wake_plan_editor.dart`
  - `lib/features/week_calendar/model/week_calendar_interaction.dart`
  - `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`
  - `lib/features/wake_plan/application/wake_plan_service.dart`
- depends_on: [Task_28, Task_25]
- acceptance:
  - Inline/one-time drafts cannot succeed as scheduled unless at least one future occurrence is generated.
  - In create/edit flow, `WakePlanSchedulingResult.isSuccess` is false when `_buildOccurrenceBundle` has no native-schedulable occurrences.
  - Reconcile and edit/create flows surface explicit warning when a far-future one-time plan is outside rolling scheduling horizon.
  - Weekly plans created after today's target time must include next-week first occurrence in a corrected 7-day rolling window boundary; do not reject as an empty-occurrence batch when a valid future weekly occurrence exists.
- validation:
  - kind: command; required: true; owner: worker; detail: widget/service tests for inline draft far-future inputs and one-time no-occurrence handling.
  - kind: command; required: true; owner: worker; detail: `flutter test` on affected feature tests.
  - kind: review; required: true; owner: reviewer; detail: alarm availability behavior review for create/empty-occurrence paths.

### Task_03: Harden iOS TestFlight workflow against tag-controlled code execution with secrets

- status: planned
- severity: high
- source: https://chatgpt.com/codex/cloud/security/findings/854aa5160cf881919793a2444856ee88
- commit_hash: 3383776de9ec73548c8d4ce675488baa16713bc1
- owns:
  - `github/workflows/release-distribution.yml`
- depends_on: [Task_01]
- acceptance:
  - iOS signing + App Store Connect secrets are only made available after code provenance checks (trusted ref/tag/event) are enforced.
  - Workflow requires protected environment before secret mount; the iOS build job in `release-distribution.yml` declares `environment: production` (or a dedicated `release-ios` environment) so GitHub applies required reviewers, branch/tag protection, and timed approval gates before any signing secret is exposed to the runner.
  - Repository precondition (required, tracked under this task's acceptance): a GitHub Environment named `production` (or `release-ios`) is created in the repository settings, configured with the allowed deployment branches/tags (e.g. `refs/tags/*` release refs only) and at least one required reviewer; secrets are attached to that Environment (not to the repository), so manual dispatch against arbitrary untrusted refs cannot reach them.
  - Manual dispatch cannot point to arbitrary untrusted refs for secret-bearing build steps.
- validation:
  - kind: command; required: true; owner: worker; detail: `actionlint github/workflows/release-distribution.yml` asserting `environment:` is set on iOS signing/distribution jobs and verifying threat-model.
  - kind: command; required: true; owner: worker; detail: manual workflow threat-model review and required approval gate mapping, including verification that the Environment is protected in repository settings before merge.
  - kind: review; required: true; owner: reviewer; detail: iOS release-path CI and secrets governance review.

### Task_04: Recovery of retryable alarms must not permanently retire schedule state

- status: planned
- severity: medium
- source: https://chatgpt.com/codex/cloud/security/findings/e1b9ba4ca26c81919ee194eee6be0020
- commit_hash: 3e509891b80af5b31e07aa876e4fac449853ea0a
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt`
  - `lib/features/wake_plan/application/wake_plan_service.dart`
- depends_on: [Task_28, Task_02, Task_13, Task_25]
  (Task_02 is ordered first: both tasks edit `wake_plan_service.dart`'s
  empty-occurrence success/failure handling, so Task_02's broader inline/
  one-time far-future rejection lands first and Task_04's narrower
  retryable-recovery fix is implemented against that already-updated
  logic — avoiding two tasks racing to change the same success-path
  behavior independently.)
- acceptance:
  - One-time targets beyond planning horizon return a user-visible validation error.
  - Schedule result is not success when no native occurrence can be produced.
  - Calendar-created one-time entries cannot complete unscheduled silently.
- validation:
  - kind: command; required: true; owner: worker; detail: calendar + creation flow tests for far-future one-time and horizon boundary.
  - kind: review; required: true; owner: reviewer; detail: alarm-availability behavior review for create path.

### Task_13: Configure AlarmKit entitlement and usage declarations

- status: planned
- severity: medium
- source: https://chatgpt.com/codex/cloud/security/findings/0b164e5ba1448191a6dd051672f29f7c
- commit_hash: b2c6bc2abf181ef1613e5da76d6d5c2281b96dd0
- owns:
  - `ios/Runner/AlarmKitBridge.swift`
  - `ios/Runner.xcodeproj/project.pbxproj`
  - `ios/Runner/Info.plist`
- depends_on: []
- acceptance:
  - AlarmKit capability files are present and project links entitlements to Runner target.
  - Info.plist usage descriptions are explicit for alarm functionality.
- validation:
  - kind: command; required: true; owner: worker; detail: Flutter + iOS native build check with AlarmKit path.
  - kind: review; required: true; owner: reviewer; detail: iOS capability provisioning review.

### Task_14: Avoid exposing sensitive alarm summary on lock-screen ringing UI

- status: planned
- severity: low
- source: https://chatgpt.com/codex/cloud/security/findings/cae0e81eea20819198e4d619c3decb26
- commit_hash: ef84b0d5e2377b335199b27c41f54502ff62b6eb
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmStopActivity.kt`
- depends_on: []
- acceptance:
  - Full-screen lock-screen ringing view hides sensitive schedule details by default.
  - Summary fields that reveal wake plan times are shown only after unlock and keyguard-inactive state is confirmed.
  - Validation requires explicit lock-state coverage:
    - onKeyguard visibility is verified by `KeyguardManager.isKeyguardLocked()` check at startup and unlock transition (`KeyguardDismissCallback` or `ACTION_USER_PRESENT`), and summary fields must remain hidden until unlocked.
    - onResume must re-check `KeyguardManager.isKeyguardLocked()` and keep sensitive summary hidden while lock remains active.
    - After unlock, summary fields are revealed and keep no hidden-state regressions on repeated Activity resume.
- validation:
  - kind: command; required: true; owner: worker; detail: Android UI/privacy regression tests and screenshot/manual acceptance for lock-screen behavior.
  - kind: review; required: true; owner: reviewer; detail: privacy surface review for lock-state.

### Task_15: Normalize persisted default sound ids to canonical value before UI binding

- status: planned
- severity: low
- source: https://chatgpt.com/codex/cloud/security/findings/795bceae0bc48191be174407dcf6f692
- commit_hash: d65f7c95740bec87f22329887b3807c26daf3abd
- owns:
  - `lib/features/wake_plan/domain/src/app_settings.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart`
  - `lib/features/settings/presentation/settings_placeholder.dart`
- depends_on: [Task_19]
  (Note: an earlier draft of this task also listed a `Task_08` dependency, but no such task
  exists in this plan or in `docs/coding-agent/plans/active/codebase-review-remediation-plan.md`;
  it has been dropped as an invalid reference. If a genuine settings-domain prerequisite is
  identified later, add it here explicitly with its owning plan file.)
- acceptance:
  - Repository mapping trims and normalizes `defaultSoundId` before persistence and when loading settings.
  - Settings dropdown receives only values present in menu items.
  - Corrupt whitespace variants no longer break dropdown rendering.
- validation:
  - kind: command; required: true; owner: worker; detail: settings domain repository tests for padded/invalid IDs.
  - kind: review; required: true; owner: reviewer; detail: settings robustness review.

### Task_16: Clamp wake-plan offsets and calendar rendering loops to safe bounds

- status: planned
- severity: low
- source: https://chatgpt.com/codex/cloud/security/findings/ce2cf2aa4478819186685b27f3e9d9a9
- commit_hash: bcb6cbf2198c7bdfab0451f694df10cdaa0b69fd
- owns:
  - `lib/features/week_calendar/model/week_calendar_interaction.dart`
  - `lib/features/week_calendar/presentation/week_calendar_view.dart`
  - `lib/features/wake_plan/domain/src/wake_plan.dart`
- depends_on: [Task_12, Task_20, Task_24, Task_25]
  (Task_12 is defined and tracked in `docs/coding-agent/plans/active/codebase-review-remediation-plan.md`
  — "Implement AlarmKit inventory and stop-state observation on iOS"; status there: complete, PR #48.)
- acceptance:
  - Rendering path uses bounded loop windows with validated maximum offset span.
  - Excessive `startOffset` values are rejected or saturated before build-time loops.
  - No out-of-range date math in week/calendar rendering on boundary inputs.
- validation:
  - kind: command; required: true; owner: worker; detail: widget tests for extreme offsets and calendar build stability.
  - kind: review; required: true; owner: reviewer; detail: UI performance/robustness review.

### Task_17: Treat native alarm operation failures in smoke as hard failure in available-run environments

- status: planned
- severity: low
- source: https://chatgpt.com/codex/cloud/security/findings/f6fa7112ac908191b22ce4a083d3502d
- commit_hash: 3ca67898e7f8700d2138ca5775ffe1de62933744
- owns:
  - `integration_test/native_alarm_smoke_test.dart`
- depends_on: [Task_11]
  (Task_11 is defined and tracked in `docs/coding-agent/plans/active/codebase-review-remediation-plan.md`
  — "Implement native inventory/stable identity on Android"; status there: complete.)
- acceptance:
  - `CALARM_NATIVE_SMOKE_OUTCOME` failure for schedule/cancel/test alarm in `NEAR_DEVICE` expected path fails CI check.
  - `integration_test/native_alarm_smoke_test.dart` emits an explicit non-zero outcome signal for timeout (exit 124) and native operation failures that the workflow can read.
  - The integration test does NOT attempt to edit `github/workflows/native-smoke.yml`; all workflow/guard logic (timeout detection, operation-failure detection, BLOCKED-vs-runtime-fail discrimination) is owned and consolidated by Task_11.
  - `BLOCKED` is only set by an explicit pre-run environment-unavailability gate before job launch; any failure after launch remains hard-fail.
  - Gate text and checks are unambiguous between environment-skipped and runtime failure modes.
- validation:
  - kind: command; required: true; owner: worker; detail: native smoke test updates + workflow condition coverage.
  - kind: review; required: true; owner: reviewer; detail: CI security gate review.

### Task_19: Bound persisted wake window values and planner loop caps

- status: planned
- severity: low
- source: https://chatgpt.com/codex/cloud/security/findings/d24d637d13648191a2d870b8be76e73f
- commit_hash: 5910c90dcc97ca05be9d2522510a209ad5a26dbc
- owns:
  - `lib/features/wake_plan/data/src/wake_plan_database.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart`
  - `lib/features/wake_plan/domain/src/wake_plan.dart`
  - `lib/features/wake_plan/application/occurrence_planner.dart`
- depends_on: [Task_28]
- acceptance:
  - Persisted wake window and interval values are bounded at domain/schema level.
  - Planner rejects or clamps extreme values that can create unbounded loops.
  - No UI freeze on deliberately inflated persisted timing rows.
- validation:
  - kind: command; required: true; owner: worker; detail: domain and repository tests for value bounds and planner saturation.
  - kind: review; required: true; owner: reviewer; detail: persistence hardening review.

### Task_20: Replace ambiguous correlation key encoding in native gateway

- status: planned
- severity: low
- source: https://chatgpt.com/codex/cloud/security/findings/1780c28030188191986a834b8e5e2ca0
- commit_hash: 10b48a5655b7ffddc7dee600df5b31449039021d
- owns:
  - `lib/core/platform/native_alarm_gateway.dart`
- depends_on: [Task_28]
- acceptance:
  - Correlation key construction is injective for `(first, second)` identifiers and robust to delimiter collisions.
  - Malformed identifiers cannot map different pairs to the same correlation key.
  - Use a deterministic injective encoding (percent-encoded fields or tuple/hash format) instead of delimiter-only concatenation.
  - Validation failure path is explicit and visible.
- validation:
  - kind: command; required: true; owner: worker; detail: gateway unit tests for delimiter/collision resistance.
  - kind: review; required: true; owner: reviewer; detail: protocol integrity review.

### Task_21: Fix release task status mismatch that misrepresents blocked evidence

- status: planned
- severity: informational
- source: https://chatgpt.com/codex/cloud/security/findings/3ec057b0bf1c8191afce97d3ae9828ff
- commit_hash: 1fcf26e44bf5384c24b19e1be0a16c127572b222
- owns:
  - `docs/coding-agent/plans/active/codebase-review-remediation-plan.md`
  - `docs/qa/release-readiness.md`
- depends_on: [Task_22]
- acceptance:
  - Task status does not transition to complete while hard blockers remain.
  - Release readiness artifact and plan state are internally consistent.
  - Completion requires explicit evidence paths (logs/videos) for hard blockers referenced by readiness artifacts before status is moved to complete.
  - As long as hard blockers remain, task status stays `blocked` or `in_progress`; completion by text-only update is disallowed.
  - Any waiver text is explicit and tied to a required owner.
- validation:
  - kind: command; required: true; owner: worker; detail: documentation consistency audit and gate-policy check.
  - kind: review; required: true; owner: reviewer; detail: process integrity review.

### Task_22: Correct Google Play track input key usage

- status: planned
- severity: informational
- source: https://chatgpt.com/codex/cloud/security/findings/7b23e29080d48191b3186c5b14679bf1
- commit_hash: df91afbaa4d47890cc6560ee8ce64b0338eb0d8f
- owns:
  - `github/workflows/release-distribution.yml`
  - `docs/qa/release-distribution.md`
- depends_on: [Task_03]
- acceptance:
  - Workflow uses the correct action input key for upload action version.
  - Published track behavior matches documentation and desired release lane.
- validation:
  - kind: command; required: true; owner: worker; detail: `actionlint github/workflows/release-distribution.yml`.
  - kind: command; required: true; owner: worker; detail: workflow config lint + action input assertion.
  - kind: review; required: true; owner: reviewer; detail: release config correctness review.

### Task_23: Protect draft handle layout under narrow constraints

- status: planned
- severity: informational
- source: https://chatgpt.com/codex/cloud/security/findings/103ffd7efe5c8191b272db85f6e95953
- commit_hash: e87ecbbf2f3984612819f82358c451c8fa9099cb
- owns:
  - `lib/features/week_calendar/presentation/week_calendar_view.dart`
- depends_on: [Task_12, Task_16, Task_24]
  (Task_12: see `docs/coding-agent/plans/active/codebase-review-remediation-plan.md`; status there: complete, PR #48.)
- acceptance:
  - Clamp range arguments are always valid under all widths.
  - Narrow-width draft UI no longer throws from geometry math.
- validation:
  - kind: command; required: true; owner: worker; detail: widget tests for narrow widths and tap/drag states.
  - kind: review; required: true; owner: reviewer; detail: UI robustness review.

### Task_24: Ensure one-finger drag cleanup always resets manipulating state

- status: planned
- severity: informational
- source: https://chatgpt.com/codex/cloud/security/findings/a6b5311abd908191bf5e886be609ea3c
- commit_hash: 87b33bb316ee0ac371094387330521c7505e5578
- owns:
  - `lib/features/week_calendar/presentation/week_calendar_view.dart`
- depends_on: []
- acceptance:
  - Unaccepted pointer gestures always reset `_manipulatingDraft`.
  - Scroll lock does not get permanently stuck after one-pointer drag.
  - Cross-day drag replacement does not leak gesture state.
- validation:
  - kind: command; required: true; owner: worker; detail: pointer-gesture regression tests around cancel/end rejection paths.
  - kind: review; required: true; owner: reviewer; detail: gesture state review.

### Task_25: Fix type inference issues in calendar tap helper

- status: planned
- severity: informational
- source: https://chatgpt.com/codex/cloud/security/findings/56d8a26add788191be6061c02352cb17
- commit_hash: 91d5a3b43512187c56b7e0bc42c94837dcf498d3
- owns:
  - `lib/features/week_calendar/model/week_calendar_interaction.dart`
- depends_on: []
- acceptance:
  - Helper returns strict int types where required by downstream APIs.
  - Build succeeds without inferred-num mismatch errors.
  - Tap target mapping still matches prior accepted behavior.
- validation:
  - kind: command; required: true; owner: worker; detail: compile-targeted test for week_calendar module and full analyzer run.
  - kind: review; required: true; owner: reviewer; detail: type-safety review.

### Task_26: Bound occurrence generation loops and resource usage

- status: planned
- severity: informational
- source: https://chatgpt.com/codex/cloud/security/findings/0d6038720e288191aa0850bad9f43883
- commit_hash: 3878b794d1f83ddd58f84b5fa1488417c161ca7b
- owns:
  - `lib/features/wake_plan/application/occurrence_planner.dart`
  - `lib/features/wake_plan/domain/src/wake_plan.dart`
- depends_on: [Task_19]
- acceptance:
  - Occurrence planning has explicit hard/soft maximums and short-circuits on excessive windows.
  - Planner handles malicious/extreme startOffset/end ranges safely.
  - No app-freeze risk from pathological persisted/corrupt schedule inputs.
- validation:
  - kind: command; required: true; owner: worker; detail: planner property tests / unit tests for large start windows.
  - kind: review; required: true; owner: reviewer; detail: availability/DoS hardening review.

### Task_28: Centralize empty-occurrence unscheduled rejection across wake-plan scheduling

- status: planned
- severity: medium
- source: https://chatgpt.com/codex/cloud/security/findings/bffaa98df85881918cfc0ff63b4047d8
- commit_hash: 50b0061ed2900dd9baec5889263acd0fa3e0273d
- depends_on: []
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `lib/core/platform/native_alarm_gateway.dart`
- acceptance:
  - `ScheduleResult.fromOccurrences` accepts a scheduling context (`create`, `edit`, `reconcile`, `cleanup`) and applies empty-batch policy per context.
  - For `create`/`edit`, return non-success (`isSuccess = false`) when `scheduledCount == 0` for both `requestCount == 0` and `requestCount > 0`.
  - For `reconcile`/`cleanup`, return success with explicit unscheduled-warning metadata when `scheduledCount == 0` reflects expected terminal state.
  - Create/edit callers inherit context-aware rejection and do not emit scheduled success without at least one native reservation.
  - Recovery metadata distinguishes between transient scheduling delay and impossible/invalid plan horizon.
  - `occurrence_planner` must correct weekly endExclusive boundary handling so next-week occurrence is generated when current-day time has passed.
- validation:
  - kind: command; required: true; owner: worker; detail: service tests for zero-occurrence and far-horizon inputs.
  - kind: review; required: true; owner: reviewer; detail: core scheduling semantic and alarm-availability integrity review.

### Task_27: Bound wake-plan duration and interval fields

- status: planned
- severity: informational
- source: https://chatgpt.com/codex/cloud/security/findings/306bf7fb9ed88191843f09342d0830d7
- commit_hash: 573a5e2f22d73dca6e27bc9289fe70d165be74be
- owns:
  - `lib/features/wake_plan/domain/src/wake_plan.dart`
  - `lib/features/wake_plan/domain/src/app_settings.dart`
- depends_on: [Task_19]
- acceptance:
  - Domain validation enforces practical maximum duration/interval values.
  - Scheduling and rendering paths do not process unbounded intervals.
  - Corrupted extreme values are classified and rejected before heavy planning.
- validation:
  - kind: command; required: true; owner: worker; detail: domain validation and repository ingest tests.
  - kind: review; required: true; owner: reviewer; detail: domain-model hardening review.

## Closeout Notes

- All high/medium findings are intentionally prioritized before low/informational hardening tasks.
- This file is a planning artifact only; no code changes were made in this turn.
- Plan approval is required before execution; current status remains open.
