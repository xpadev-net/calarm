# Plan: Calendar interaction and occurrence-control fixes

- status: in_progress
- generated: 2026-07-16
- last_updated: 2026-07-16
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
- type: impl
- owns:
  - `lib/features/wake_plan/domain/src/alarm_occurrence.dart`
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart`
  - `lib/features/wake_plan/data/src/wake_plan_database.dart`
  - `lib/features/wake_plan/data/src/wake_plan_database.g.dart`
  - `lib/features/wake_plan/ui/wake_plan_detail_sheet.dart`
  - `test/features/wake_plan/application/wake_plan_service_test.dart`
  - `test/features/wake_plan/data/wake_plan_repository_test.dart`
  - `test/features/wake_plan/ui/wake_plan_detail_sheet_test.dart`
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
    detail: `rtk fvm flutter test test/features/wake_plan/application/wake_plan_service_test.dart test/features/wake_plan/data/wake_plan_repository_test.dart test/features/wake_plan/ui/wake_plan_detail_sheet_test.dart`
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
