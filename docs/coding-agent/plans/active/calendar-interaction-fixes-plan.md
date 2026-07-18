# Plan: Calendar interaction and occurrence-control fixes

- status: in_progress
- generated: 2026-07-16
- last_updated: 2026-07-19
- work_type: code

## Goal
- Make calendar zooming, selection, scrolling, direct range editing, and per-occurrence alarm controls behave predictably without layout shifts.

## Definition of Done
- Pinch zoom works on a device without breaking one-finger scrolling, horizontal paging, or draft manipulation.
- Creating or editing a draft near 23:00 never changes the visible vertical offset or calendar geometry merely because the editor appears or the range crosses a day boundary.
- 5/10/15-minute selections render at their exact duration-derived heights at all supported zoom levels while resize handles remain usable.
- A tapped wake plan exposes its future concrete occurrences and each eligible occurrence can be disabled and re-enabled persistently without reconciliation resurrecting a disabled occurrence.
- The calendar scrolls to the current-time position on initial display and application foreground resume, but not on minute ticks, provider rebuilds, taps, draft changes, or editor visibility changes.
- Start and end date-times can be edited directly with the same snap, duration, cross-day, and validity rules as drag editing.
- All required Worker, Orchestrator, and Reviewer validation passes, every PR is independently reviewed, and all PRs are merged by the Orchestrator.

## Scope / Non-goals
- Scope:
  - Week-calendar gesture, layout, scrolling, draft geometry, and inline range editing.
  - Persistent per-occurrence enable/disable state and wake-plan detail controls.
  - Focused unit/widget tests, full Flutter validation, and device-level UI evidence.
- Non-goals:
  - Redesigning the calendar or wake-plan visual language.
  - Persisting timezone identifiers or solving ambiguous/nonexistent DST wall times beyond the app's current local `DateTime` semantics.
  - Adding new navigation routes solely for scroll restoration.

## Context (workspace)
- Related files/areas:
  - `lib/features/week_calendar/**`
  - `lib/features/wake_plan/**`
  - `test/features/week_calendar/**`
  - `test/features/wake_plan/**`
- Existing patterns or references:
  - Merged PR #50 (`2cfe207971bf0fc9729d1206be108d2bd0df892b`) introduced the current calendar interaction implementation.
  - `WeekCalendarDraft` is the shared 5-minute-snapped range model.
  - `WeekCalendarView` owns zoom, scrolling, paging, and draft rendering.
  - `WeekCalendarPlaceholder` owns lifecycle/current-time refresh and inline-editor visibility.
- Repo reference docs consulted:
  - Repository `AGENTS.md` instructions supplied in the task.
  - Repository rule suite under `docs/coding-agent/rules/` is absent; validation is derived from current Flutter tooling, focused tests, full tests, and independent UI review.

## Open Questions (max 3)
- None blocking. Assumptions below are used unless implementation evidence forces a replan.

## Assumptions
- "画面に戻った際" means foreground lifecycle resume for the current single-home-screen application; route-return behavior will be included only if an existing route-visibility signal is found without broadening ownership.
- Future scheduled occurrences, including the final occurrence, are toggleable; past/ringing/dismissed occurrences are shown only when useful and are not toggleable.
- Direct date-time input preserves current local wall-clock/elapsed-duration semantics and clearly rejects invalid ranges rather than attempting timezone disambiguation.
- The user's instruction to create a plan and proceed in parallel is explicit approval to execute this plan.

## Tasks

### Task_1: Restore device pinch zoom
- status: complete
- worker_thread: `019f6b02-c629-7463-a341-b9924932b3f9`
- worker_worktree: `<CODEX_HOME>/worktrees/137a/calarm`
- replaced_worker_thread: `019f693a-17e4-7090-b2fb-e4665e77961c` (archived rollout missing; replacement started)
- branch: `codex/task-1-calendar-pinch`
- pr: `https://github.com/xpadev-net/calarm/pull/51`
- head: `efe1b3826bb2998bac1748d8c7caac1173bd5b9c`
- merge_commit: `64eb66a227ded39eddc4d905e4718eb7bc25e5ae`
- merged_at: `2026-07-16T19:15:07Z`
- evidence: Focused view 24/24, full Flutter suite 330/330, analyze, diff-check, independent exact-head UI and tests/concurrency reviews with no findings, worker and orchestrator `gh-review-hook` exit 0, 5/5 green checks, CLEAN/APPROVED/current base, and isolated Android API 34 two-pointer probes at 07:30 and 23:00 with focal stability plus post-end vertical scroll and horizontal paging.
- worker_archived: true
- type: impl
- owns:
  - `lib/features/week_calendar/presentation/week_calendar_view.dart`
  - `test/features/week_calendar/presentation/week_calendar_view_test.dart`
- depends_on: []
- description: |
  Reproduce pinch behavior after syncing merged PR #50, then make the gesture path work with real two-pointer interaction while preserving the focal minute and restoring one-finger scroll/page behavior after pointer up or cancel.
- acceptance:
  - Pinch-in and pinch-out change hour height within the existing 36–92 px/hour bounds.
  - The time under the pinch focal point remains stable within test tolerance.
  - One-finger vertical scrolling and horizontal paging work after pinch completion/cancellation.
  - Draft move/resize gestures do not regress.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: `rtk fvm flutter test test/features/week_calendar/presentation/week_calendar_view_test.dart`
  - kind: command
    required: true
    owner: worker
    detail: `rtk fvm flutter analyze`
  - kind: ui_probe
    required: true
    owner: worker
    detail: Device/emulator two-finger pinch around 07:30 and 23:00; report focal-minute, page, scroll, and post-cancel behavior.
  - kind: review
    required: true
    owner: orchestrator
    detail: Deep review, gh-review-hook exit 0, PR merge-gate preflight, and focused rerun before merge.

### Task_2: Add persistent per-occurrence alarm toggles
- status: complete
- worker_thread: `019f6b02-c520-7601-a7f9-816e5b8112e7`
- worker_worktree: `<CODEX_HOME>/worktrees/dd05/calarm`
- resumed_worker_thread: `019f764b-6b12-7151-970b-8e49283635f0`
- resumed_worker_worktree: `<CODEX_HOME>/worktrees/f66b/calarm`
- replaced_worker_thread: `019f693a-17b1-78c3-8a0e-30a8ae7c911b` (archived rollout missing; replacement started)
- branch: `codex/task-2-occurrence-toggles`
- pr: `https://github.com/xpadev-net/calarm/pull/52`
- head: `3da78b84f8d20d0aee7485065f2da69e914191fb`
- merge_commit: `6c4a3d388cab40d3db5541f973c427af3560b80f`
- merged_at: `2026-07-18T19:31:21Z`
- evidence: Exact disable to resume/restart to re-enable probes passed with durable pre-cancel intent, authoritative inventory absence/active/unavailable/ambiguity handling, stable native identity, definite-versus-uncertain enable recovery, visible UI retryability, and duplicate/stranding prevention. Orchestrator focused suites passed 178/178, full Flutter passed 445/445, analyze/format/diff passed, the iOS simulator build and RunnerTests passed, three independent exact-head deep-review perspectives approved, `gh-review-hook 52` exited 0, all 5 hosted checks passed, and all 12 review threads were resolved. Physical-device AlarmKit authorization/delivery remains unverified and is not claimed as release evidence.
- worker_archived: true
- head_at_replacement: `381675108278333e08dfc12c739bec210936d308`
- stop_reason: Exact-head independent review proved that an iOS lost MethodChannel schedule reply can leave an id-less `userEnablePending` row permanently hidden while an unknown native alarm remains live; an in-scope service-only retry can duplicate alarms and rejecting re-enable would violate acceptance.
- prerequisite: satisfied by Task_12 / PR #48 merge commit `2d3ceb1c786aa0b44e6da90457c164df6afbe11e`, which provides stable reservation-to-platform identity plus authoritative iOS inventory.
- resume_action: Replacement worker normally integrates current master, reruns the exact restart/native-state probe and focused/full suites, obtains fresh independent review, runs the worker hook, and re-enters orchestrator merge preflight.
- stopped_worker_archived: true
- pr_dependency_note: Confirmed in PR #52 description; no code/history change accompanied the metadata update.
- type: impl
- owns:
  - `lib/features/wake_plan/domain/src/alarm_occurrence.dart`
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart`
  - `lib/features/wake_plan/data/src/wake_plan_database.dart`
  - `lib/features/wake_plan/data/src/wake_plan_database.g.dart`
  - `lib/features/wake_plan/ui/wake_plan_detail_sheet.dart`
  - `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`
  - `test/features/wake_plan/application/wake_plan_service_test.dart`
  - `test/features/wake_plan/data/wake_plan_repository_test.dart`
  - `test/features/wake_plan/ui/wake_plan_detail_sheet_test.dart`
  - `test/features/week_calendar/presentation/week_calendar_placeholder_test.dart`
- depends_on: []
- description: |
  Add a user-disabled occurrence state that survives restart/reconciliation, service-level enable/disable compensation around the native gateway, and switches for eligible concrete occurrences in the tapped plan detail sheet.
- acceptance:
  - Eligible future occurrences associated with the tapped plan are individually visible and toggleable.
  - Turning an occurrence off cancels the native alarm and persists suppression; relaunch/resume reconciliation does not recreate it.
  - Turning it on schedules the correct occurrence and persists the scheduled result.
  - Native or persistence failures leave repository/native state recoverable and surface a useful UI error.
  - Past/ringing/dismissed rows cannot be incorrectly toggled.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: `rtk fvm flutter test test/features/wake_plan/application/wake_plan_service_test.dart test/features/wake_plan/data/wake_plan_repository_test.dart test/features/wake_plan/ui/wake_plan_detail_sheet_test.dart test/features/week_calendar/presentation/week_calendar_placeholder_test.dart`
  - kind: command
    required: true
    owner: worker
    detail: `rtk fvm flutter analyze`
  - kind: ui_probe
    required: true
    owner: worker
    detail: Disable, resume/restart, and re-enable a future occurrence; verify displayed and native scheduling states.
  - kind: review
    required: true
    owner: orchestrator
    detail: Deep review emphasizing reconciliation/state-machine failure paths, gh-review-hook exit 0, and focused rerun before merge.

### Task_3: Prevent calendar layout shift and recenter only on lifecycle return
- status: complete
- worker_thread: `019f6c5b-8ed7-78f0-aa9d-9a4bcc957a73`
- worker_worktree: `<CODEX_HOME>/worktrees/8862/calarm`
- branch: `codex/task-3-calendar-lifecycle`
- pr: `https://github.com/xpadev-net/calarm/pull/53`
- head: `904480fec7f463b6a25d632f32e32decd33ea548`
- merge_commit: `36b2bb81b66faf66e6b352b9ba3032f9ca729c1f`
- merged_at: `2026-07-17T18:36:07Z`
- evidence: Focused calendar widget tests 56/56, full Flutter suite 337/337, analyze, format, and diff-check passed; same-day/cross-day near-23:00 geometry and offset probes plus 18:00 foreground exactly-once recenter passed; worker and orchestrator `gh-review-hook` exited 0; three exact-head orchestrator review perspectives found no actionable findings; PR was CLEAN, APPROVED, current-base, and 5/5 checks green.
- worker_archived: true
- type: impl
- owns:
  - `lib/features/week_calendar/presentation/week_calendar_view.dart`
  - `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`
  - `lib/app.dart`
  - `test/features/week_calendar/presentation/week_calendar_view_test.dart`
  - `test/features/week_calendar/presentation/week_calendar_placeholder_test.dart`
- depends_on: [Task_1]
- description: |
  Keep the calendar viewport geometry and vertical offset stable when the inline editor appears/disappears or a draft crosses midnight, and introduce an explicit scroll-to-now command emitted only for initial display and foreground resume.
- acceptance:
  - Tapping near 23:00 does not change the vertical scroll offset or grid global position.
  - Cross-day draft creation does not change page/date range or recenter the viewport.
  - Initial display and foreground resume recenter the current date/time once with the intended leading context.
  - Minute ticks, provider rebuilds, draft edits, editor visibility, and ordinary taps never trigger recentering.
  - Existing non-current-range behavior is deterministic and covered by tests.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: `rtk fvm flutter test test/features/week_calendar/presentation/week_calendar_view_test.dart test/features/week_calendar/presentation/week_calendar_placeholder_test.dart`
  - kind: command
    required: true
    owner: worker
    detail: `rtk fvm flutter analyze`
  - kind: ui_probe
    required: true
    owner: worker
    detail: At a scrolled 23:00 position, tap a same-day and cross-day slot and measure offset/geometry before and after; background/resume from 18:00 and verify a single recenter.
  - kind: review
    required: true
    owner: orchestrator
    detail: Deep review, gh-review-hook exit 0, focused rerun, and layout/scroll state evidence before merge.

### Task_4: Render and resize short ranges exactly
- status: complete
- worker_thread: `019f7160-b4bb-76e1-8008-dda5ac52fb57`
- worker_worktree: `<CODEX_HOME>/worktrees/40d4/calarm`
- replacement_worker_thread: `019f764b-bebe-7ff3-847d-0681414a3b1e`
- replacement_worker_worktree: `<CODEX_HOME>/worktrees/7f05/calarm`
- replacement_reason: Prior worker could be unarchived but could not resume because its archived rollout file was missing; replacement continues the unchanged PR branch without history rewrite.
- branch: `codex/task-4-short-range-geometry`
- pr: `https://github.com/xpadev-net/calarm/pull/54`
- head: `2a2c7b5ed0db4e5e353f57461dab210d6d32a912`
- merge_commit: `e87ecbbf2f3984612819f82358c451c8fa9099cb`
- merged_at: `2026-07-18T19:05:54Z`
- evidence: Focused calendar view tests 53/53 and full Flutter suite 384/384 passed at the exact head; analyze, no-change format, diff-check, 5/5 hosted checks, complete review-thread audit, and orchestrator `gh-review-hook 54` all passed. Three independent exact-head review perspectives approved the zero/start-only/end-only/both hit-target arbitration. The corrected 390px cross-midnight regression proves its start/end probes are inside the body, measured 48x48 handle, and visual-dot radius, and mutation testing proved removal of end-only visual precedence fails the test.
- worker_archived: true
- type: impl
- owns:
  - `lib/features/week_calendar/presentation/week_calendar_view.dart`
  - `test/features/week_calendar/presentation/week_calendar_view_test.dart`
- depends_on: [Task_3]
- description: |
  Decouple visible draft geometry from accessible gesture hit targets so 5/10/15-minute ranges render at duration-derived pixel heights at every zoom while start/end handles remain operable.
- acceptance:
  - 5/10/15/30-minute visible outline height equals the duration-to-pixel mapping at minimum, default, and maximum zoom.
  - Start and end handle hit targets remain accessible even when their transparent interaction regions overlap.
  - Overlapping handles resolve deterministically and can produce exact 10- and 15-minute drafts.
  - Saved duration matches the visible selection outline.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: `rtk fvm flutter test test/features/week_calendar/presentation/week_calendar_view_test.dart`
  - kind: command
    required: true
    owner: worker
    detail: `rtk fvm flutter analyze`
  - kind: ui_probe
    required: true
    owner: worker
    detail: Resize to exact 10 and 15 minutes at minimum/default/maximum zoom and verify geometry plus both handles.
  - kind: review
    required: true
    owner: orchestrator
    detail: Deep review, gh-review-hook exit 0, geometry assertions, and focused rerun before merge.

### Task_5: Add direct start/end date-time editing
- status: complete
- worker_thread: `019f7160-b55e-7de3-a090-4939aecb3e55`
- worker_worktree: `<CODEX_HOME>/worktrees/291e/calarm`
- branch: `codex/task-5-direct-datetime-editing`
- pr: `https://github.com/xpadev-net/calarm/pull/55`
- head: `976458798d539565bccfc7caf6746a85c3be7e99`
- merge_commit: `47eb07a7ef8cf66cbc07e0c417bb622f891aa588`
- merged_at: `2026-07-18T07:32:14Z`
- evidence: Focused model/editor/placeholder suites 71/71, full Flutter suite 354/354 with concurrency 1, analyze, format, diff-check, worker review-hook iteration 2 and orchestrator `gh-review-hook 55` exit 0, three independent exact-head orchestrator reviews with no findings, Greptile Confidence 5/5, 5/5 green checks, CLEAN/APPROVED/current base, and widget instrumentation for same-day, 23:55→00:10, reversed, over-3-hour, past-end, cross-month/year, timezone semantics, picker flow, and scroll stability.
- worker_archived: true
- type: impl
- owns:
  - `lib/features/week_calendar/model/week_calendar_interaction.dart`
  - `lib/features/wake_plan/ui/inline_wake_plan_editor.dart`
  - `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`
  - `test/features/week_calendar/model/week_calendar_interaction_test.dart`
  - `test/features/week_calendar/presentation/week_calendar_placeholder_test.dart`
  - `test/features/wake_plan/ui/inline_wake_plan_editor_test.dart`
- depends_on: [Task_3]
- description: |
  Add editable start/end date and time controls to the inline editor and route valid changes through shared WeekCalendarDraft range logic so direct input and drag obey the same invariants.
- acceptance:
  - Start and end date-times can be changed directly, including same-day and cross-day ranges.
  - Valid changes update the draft outline without changing the calendar scroll position.
  - Ranges must be ordered, snapped to 5 minutes, between 5 minutes and 3 hours, and end in the future before save.
  - Invalid or transient picker selections show inline guidance and never construct/save an invalid draft.
  - Cross-month/year ranges and current timezone behavior are covered; ambiguous DST times are not falsely presented as disambiguated.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: `rtk fvm flutter test test/features/week_calendar/model/week_calendar_interaction_test.dart test/features/week_calendar/presentation/week_calendar_placeholder_test.dart test/features/wake_plan/ui/inline_wake_plan_editor_test.dart`
  - kind: command
    required: true
    owner: worker
    detail: `rtk fvm flutter analyze`
  - kind: ui_probe
    required: true
    owner: worker
    detail: Direct same-day and 23:55→00:10 input plus reversed, >3-hour, past-end, cross-month/year cases; measure scroll stability.
  - kind: review
    required: true
    owner: orchestrator
    detail: Deep review, gh-review-hook exit 0, model/widget reruns, and focused UI evidence before merge.

### Task_6: Integrated independent UI and regression review
- status: in_progress
- reviewer_thread: `019f76b7-e24a-7342-aee4-8fc775f104fc`
- reviewer_worktree: `<CODEX_HOME>/worktrees/c48d/calarm`
- started_after_master: pending ledger commit following Task_2 merge evidence
- type: review
- owns: []
- depends_on: [Task_2, Task_4, Task_5]
- description: |
  Independently inspect the integrated implementation and run the E2E/visual specification after all implementation PRs are merged.
- acceptance:
  - Reviewer status is APPROVED with no unresolved in-scope findings.
  - Required evidence exists under the declared artifact root.
  - Full Flutter tests and analysis pass on the integrated master branch.
- validation:
  - kind: command
    required: true
    owner: orchestrator
    detail: `rtk fvm flutter analyze`
  - kind: command
    required: true
    owner: orchestrator
    detail: `rtk fvm flutter test --concurrency=1`
  - kind: command
    required: true
    owner: orchestrator
    detail: `rtk git diff --check`
  - kind: e2e
    required: true
    owner: reviewer
    detail: Run the device-level specification below and verify every referenced artifact exists.
  - kind: review
    required: true
    owner: reviewer
    detail: Independent integrated diff/behavior review against all acceptance criteria.

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1, Task_2]
- Wave 2 (parallel): [Task_3]
- Wave 3 (parallel): [Task_4, Task_5]
- Wave 4 (parallel): [Task_6]

## E2E / Visual Validation Spec

- provider: Flutter integration/widget instrumentation plus Reviewer-controlled Android/iOS device or emulator interaction; real multitouch evidence is required for pinch acceptance.
- artifact_root: `artifacts/calendar-interaction-fixes/`
- base_url: Not applicable (native Flutter app).
- app_start_command: `rtk fvm flutter run -d <review-device>`
- readiness_check: Home week calendar is rendered, current-time indicator is present, and no startup exception appears.
- flows:
  - Pinch in/out around 07:30 and 23:00; verify focal minute/page stability and restored one-finger scroll.
  - Scroll near 23:00, capture offset/grid geometry, tap same-day and cross-day ranges, and prove no offset or geometry shift.
  - Resize at minimum/default/maximum zoom to exact 10- and 15-minute ranges; compare outline pixels with duration.
  - Direct-edit same-day, 23:55→00:10, cross-month/year, reversed, >3-hour, and past-end ranges.
  - Scroll to 18:00, background/foreground the app, and prove one recenter to the current-time position; prove ordinary rebuilds do not recenter.
  - Disable a future occurrence, resume/restart and prove it remains disabled/not scheduled, then re-enable and prove it is scheduled once.
- viewports:
  - Phone portrait approximately 390×844.
  - Tablet or landscape device class.
- evidence_requirements:
  - Before/after screenshots for stable geometry, short-range sizing, direct input, resume recenter, and occurrence toggles.
  - Screen recording for physical pinch and 23:00 no-layout-shift behavior.
  - Captured ScrollController offset/global geometry assertions from tests or debug instrumentation.
  - Console exception/error notes and native alarm inventory notes.
  - Artifact existence check before Reviewer approval.
- known_flakiness:
  - Widget-level synthetic pointer tests do not replace real multitouch evidence.
  - Native alarm scheduling availability varies by platform/permission and must be reported rather than silently skipped.

## Rollback / Safety
- Each behavior slice is isolated in its own PR and merged sequentially by dependency wave; revert individual merge commits if a later device check exposes a regression.
- Never rewrite history or force-push an open PR.
- Workers never merge; the Orchestrator owns merge gates and merge actions.

## Progress Log (append-only)

- 2026-07-16 Wave 0 completed: [research, plan]
  - Summary: Synced merged PR #50, mapped six requested behaviors, and split work to avoid simultaneous ownership of central calendar files.
  - Validation evidence: Read-only Researcher report with file/symbol anchors, current PR state from `gh`, clean tracked master after fast-forward.
  - Notes: Existing untracked `artifacts/` and completed-plan/report files belong to the user and are excluded from this plan commit.
- 2026-07-16 Wave 1 started: [Task_1, Task_2]
  - Summary: Created two separate Codex worktree workers with disjoint calendar-view and wake-plan occurrence ownership.
  - Validation evidence: Both worker threads remained active after startup/onboarding and reported clean worktrees at the plan baseline.
  - Notes: Task_1 thread `019f693a-17e4-7090-b2fb-e4665e77961c`; Task_2 thread `019f693a-17b1-78c3-8a0e-30a8ae7c911b`.
- 2026-07-16 Task_2 ownership expanded: [Task_2]
  - Summary: Added the existing calendar placeholder wiring file and its focused test so the detail sheet can receive concrete occurrences and service toggle callbacks.
  - Validation evidence: Worker baseline focused suite passed 84 tests; investigation showed the production service is owned and callbacks are wired only by `WeekCalendarPlaceholder`.
  - Notes: No Task_2 product files had been changed before this decision; Task_1 owns only the calendar view, and Task_3/5 remain unstarted, so no active ownership conflict is introduced.
- 2026-07-16 Task_1 stopped on physical-device evidence: [Task_1]
  - Summary: PR #51 passed code review, worker/orchestrator-visible automation, focused/full validation, and all remote merge-state gates, but the plan-required real two-finger probe could not be executed.
  - Validation evidence: Head `8c04b077d62a337c429a3bd8dcb5f7240fb66338`; focused view 24/24; placeholder 25/25; analyze/diff-check/full CI pass; independent Reviewer `APPROVED_CODE`; worker `gh-review-hook` exit 0; PR CLEAN/MERGEABLE/not behind with 5/5 checks green.
  - Notes: No touch-capable device/emulator is visible; synthetic widget gestures are not accepted as physical evidence. PR remains open and unmerged. Task_3 cannot start until Task_1 merges.
- 2026-07-16 open-PR workers replaced after archived rollout loss: [Task_1, Task_2]
  - Summary: Existing worker threads could be unarchived but could not be resumed because their archived rollout files were missing; replacement Codex worktree workers were started on the existing open-PR branches.
  - Validation evidence: Task_1 replacement thread `019f6b02-c629-7463-a341-b9924932b3f9` is active in `<CODEX_HOME>/worktrees/137a/calarm`; Task_2 replacement thread `019f6b02-c520-7601-a7f9-816e5b8112e7` is active in `<CODEX_HOME>/worktrees/dd05/calarm`.
  - Notes: Task_1 must update its behind branch and still satisfy physical multitouch evidence. Task_2 must produce exact-head Worker validation, independent review, hook, probe, and cleanliness evidence. Neither worker may merge.
- 2026-07-17 Task_2 stopped for native recovery prerequisite: [Task_2]
  - Summary: Exact-head review of PR #52 found that iOS reply loss can strand id-less `userEnablePending` state while a live native alarm may exist; Task_2 cannot satisfy recoverability without stable native identity and authoritative inventory.
  - Validation evidence: Head `381675108278333e08dfc12c739bec210936d308` remained clean/local-remote matched; focused four-suite validation passed 161 tests, analyze passed, and restart/reconciliation probe passed. Worker intentionally did not run the hook or claim merge-ready after the blocker was confirmed.
  - Decomposition: PR #52 stays stopped without iOS edits. The prerequisite is assigned to the existing non-overlapping native owner, codebase-remediation Task_12 / PR #48; Task_2 resumes only after that PR merges and all exact-head gates are rerun.
  - Closeout: PR description now records the dependency and required post-prerequisite gates. Branch/local/remote remained exactly `381675108278333e08dfc12c739bec210936d308`, no hook or merge occurred, and replacement worker `019f6b02-c520-7601-a7f9-816e5b8112e7` was archived.
- 2026-07-17 Task_1 merged and Task_3 started: [Task_1, Task_3]
  - Summary: PR #51 merged after exact-head orchestrator preflight, deep review, hook, full validation, and isolated two-pointer device evidence; the completed worker was archived and the now-unblocked Task_3 worker was started from the merge result.
  - Validation evidence: PR #51 head `efe1b3826bb2998bac1748d8c7caac1173bd5b9c`; merge commit `64eb66a227ded39eddc4d905e4718eb7bc25e5ae`; focused 24/24 and full 330/330 tests; analyze/diff-check pass; worker and orchestrator hook exit 0; two independent orchestrator review perspectives found no actionable issues; API 34 probes passed at 07:30 and 23:00 with scroll/page recovery.
  - Notes: Task_1 worker `019f6b02-c629-7463-a341-b9924932b3f9` archived. Task_3 worker `019f6c5b-8ed7-78f0-aa9d-9a4bcc957a73` is active in `<CODEX_HOME>/worktrees/8862/calarm` on planned branch `codex/task-3-calendar-lifecycle`; it must report before stopping and may not merge.
- 2026-07-17 Task_3 merged and archived: [Task_3]
  - Summary: PR #53 merged after exact-head orchestrator preflight, deep review, review hook, focused/full validation, and instrumented lifecycle/layout probes.
  - Validation evidence: Head `904480fec7f463b6a25d632f32e32decd33ea548`; merge commit `36b2bb81b66faf66e6b352b9ba3032f9ca729c1f`; focused 56/56 and full 337/337 tests; analyze/format/diff-check pass; worker and orchestrator hook exit 0; three orchestrator review perspectives approved with no findings; PR CLEAN/APPROVED/current base with 5/5 checks green.
  - Notes: Same-day and cross-day near-23:00 interactions preserved page, vertical offset, and grid position; foreground resume recentered exactly once while minute ticks, provider rebuilds, and draft edits did not. Worker `019f6c5b-8ed7-78f0-aa9d-9a4bcc957a73` archived.
- 2026-07-17 Wave 3 started: [Task_4, Task_5]
  - Summary: Started separate worktree workers for exact short-range geometry and direct date-time editing after Task_3 merged.
  - Validation evidence: Both workers remained active after startup and loaded their bounded ownership, acceptance, validation, review, and PR lifecycle instructions.
  - Notes: Task_4 thread `019f7160-b4bb-76e1-8008-dda5ac52fb57` uses `<CODEX_HOME>/worktrees/40d4/calarm`; Task_5 thread `019f7160-b55e-7de3-a090-4939aecb3e55` uses `<CODEX_HOME>/worktrees/291e/calarm`. Their planned file ownership is disjoint, and both are disjoint from active native Task_12.
- 2026-07-18 Task_5 merged and archived: [Task_5]
  - Summary: PR #55 merged after exact-head orchestrator preflight, deep review, review hook, focused/full validation, and direct-edit boundary instrumentation.
  - Validation evidence: Head `976458798d539565bccfc7caf6746a85c3be7e99`; merge commit `47eb07a7ef8cf66cbc07e0c417bb622f891aa588`; focused 71/71 and full 354/354 tests; analyze/format/diff-check pass; worker and orchestrator hook exit 0; three orchestrator review perspectives approved with no findings; PR CLEAN/APPROVED/current base with 5/5 checks green.
  - Notes: Canonical snapped endpoints govern display and Save validity, invalid transient ranges remain repairable, and direct input preserves the documented local DateTime semantics. Worker `019f7160-b55e-7de3-a090-4939aecb3e55` archived.
- 2026-07-19 Task_12 dependency merged; Task_2 resumed and Task_4 worker replaced: [Task_2, Task_4]
  - Summary: PR #48 merged the native stable-identity and authoritative-inventory prerequisite, so Task_2 restarted on its existing PR branch. Task_4's archived worker rollout was missing and could not accept the dependency-release handoff, so a replacement worker continued PR #54 from the same branch.
  - Validation evidence: PR #48 merge commit `2d3ceb1c786aa0b44e6da90457c164df6afbe11e`; Task_2 replacement thread `019f764b-6b12-7151-970b-8e49283635f0` active in `<CODEX_HOME>/worktrees/f66b/calarm`; Task_4 replacement thread `019f764b-bebe-7ff3-847d-0681414a3b1e` active in `<CODEX_HOME>/worktrees/7f05/calarm`.
  - Notes: Both replacements must normally merge current master, preserve open-PR history, refresh exact-head validation/review/check/hook evidence, and never merge. The old Task_4 worker `019f7160-b4bb-76e1-8008-dda5ac52fb57` was archived again after the rollout-path failure.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-16 Decision: Execute after plan creation.
  - Trigger / new insight: User explicitly requested planning followed by parallel `task-pr-orchestrator` execution.
  - Plan delta (what changed): User approval gate is satisfied by the direct execution instruction.
  - Tradeoffs considered: Parallelize only disjoint wake-plan/calendar ownership and serialize all `week_calendar_view.dart` changes.
  - User approval: yes.
- 2026-07-16 Decision: Add direct date-time editing.
  - Trigger / new insight: User added direct date-time input after initial research dispatch.
  - Plan delta (what changed): Added Task_5 and shared range-model validation; placed it parallel to short-range rendering only after shared placeholder work completes.
  - Tradeoffs considered: Separate the UI/model slice from view rendering to preserve disjoint ownership.
  - User approval: yes.
- 2026-07-16 Decision: Preserve current timezone semantics.
  - Trigger / new insight: Current persistence uses local `DateTime`/calendar-day data without timezone IDs.
  - Plan delta (what changed): Require DST-aware tests/documented limitation without broad timezone migration.
  - Tradeoffs considered: Full timezone disambiguation would materially broaden schema and product scope.
  - User approval: no additional approval needed; non-goal recorded.
- 2026-07-16 Decision: Expand Task_2 for caller wiring instead of splitting.
  - Trigger / new insight: `WakePlanDetailSheet` has no service access, while `_openDetailSheet` in `WeekCalendarPlaceholder` owns `WakePlanService` and all production callback wiring.
  - Plan delta (what changed): Added `week_calendar_placeholder.dart` and its focused test to Task_2 ownership and validation.
  - Tradeoffs considered: A separate integration PR would temporarily land an unusable service/UI contract and add dependency/merge overhead; keeping the single caller seam atomic is smaller and safer. Global/circular imports and test-only callbacks were rejected.
  - User approval: covered by the approved orchestration scope; no product behavior or acceptance criteria changed.

## Notes
- Risks:
  - Gesture-arena behavior may pass widget tests while failing on physical touch hardware.
  - Disabled occurrence state must be explicitly preserved by reconciliation; reusing `cancelled` would resurrect alarms.
  - Layout stability and lifecycle recenter share scroll ownership and therefore must remain in one sequential task.
- Edge cases:
  - Cross-day/month/year ranges, short ranges at all zoom bounds, repeated occurrence identity, native scheduling failure, and foreground resume while viewing a non-current date range.
- Quality routing note:
  - Routing level: L2 because gesture arbitration, persistent state reconciliation, and native scheduling cross UI/domain/platform boundaries.
  - In-scope docs: Flutter/Dart language, frontend state, persistence, native integration, validation/evidence, latent-risk review.
  - Out-of-scope docs: backend services, auth/security boundaries, migrations unless Task_2 proves a schema change is required.
  - Top risks: data-integrity, concurrency/ordering, external-deps, performance/state churn.
  - Required checks: focused tests, analyze, full test suite, deep review, gh-review-hook, device UI evidence.
  - Residual risk / follow-up: DST wall-time disambiguation remains outside scope.
