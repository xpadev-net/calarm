# Plan: Refresh the current-time line

- status: done
- generated: 2026-07-15
- last_updated: 2026-07-15
- work_type: code

## Goal
- Keep the calendar's red current-time line synchronized with the device clock while visible, including immediately after returning to the app, without moving the user's calendar scroll or page.

## Definition of Done
- The displayed current time refreshes at each local minute boundary while the app is active.
- App resume immediately refreshes the line and re-arms minute-boundary updates.
- Background states and widget disposal cancel timers safely.
- Minute updates never reset vertical scroll, visible day page, zoom, or an inline draft.
- Focused and full Flutter validation pass and an independent Reviewer approves lifecycle and UI-state preservation.

## Scope / Non-goals
- Scope: calendar placeholder clock ownership, lifecycle-aware minute timer, current-time repaint input, scroll/page preservation, and regression tests.
- Non-goals: auto-paging to today, auto-scrolling to now on every resume, changing the clock source contract, or altering calendar styling.

## Context (workspace)
- Related files/areas: `WeekCalendarPlaceholder`, `WeekCalendarView`, their widget tests, and injected `weekCalendarClockProvider`.
- Existing patterns or references: the inline draft already has timer/lifecycle cleanup tests; `_TimeGridPainter` already repaints correctly when a fresh `now` is supplied.
- Repo reference docs consulted: root `AGENTS.md`, `docs/coding-agent/lessons.md`; repository rule suite is absent.

## Open Questions (max 3)
- None blocking.

## Assumptions
- One-shot scheduling to the next minute boundary is preferred over `Timer.periodic` to avoid drift and recover cleanly from device clock changes.
- Resume updates the line in place but preserves the user's current page and scroll position.

## Tasks

### Task_1: Research current-time rendering and lifecycle
- type: research
- owns: []
- depends_on: []
- description: |
  Trace the injected clock, current-time painter, incidental rebuilds, lifecycle behavior, scroll initialization, and existing test seams.
- acceptance:
  - Root cause and exact symbols are identified.
  - Timer, lifecycle, scroll-preservation, and test requirements are specified.
- validation:
  - kind: review
    required: true
    owner: orchestrator
    detail: "Research explains why time passage does not rebuild and why now updates must not re-run initial scroll."

### Task_2: Implement lifecycle-aware minute refresh
- type: impl
- owns:
  - lib/features/week_calendar/presentation/week_calendar_placeholder.dart
  - lib/features/week_calendar/presentation/week_calendar_view.dart
  - test/features/week_calendar/presentation/week_calendar_placeholder_test.dart
  - test/features/week_calendar/presentation/week_calendar_view_test.dart
- depends_on: [Task_1]
- description: |
  Add a foreground-only next-minute one-shot timer and resume refresh, pass retained now into the view, and prevent now-only updates from reapplying initial scroll.
- acceptance:
  - A mutable injected clock proves boundary-before, first-boundary, and subsequent-minute updates.
  - Paused/inactive/hidden/detached states stop the timer; resumed refreshes immediately and re-arms it.
  - Dispose prevents delayed callbacks or setState-after-dispose.
  - Now-only rebuilds preserve vertical offset, PageView page, zoom, and draft state.
  - Existing calendar interactions remain passing.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "rtk dart format --output=none --set-exit-if-changed on the four owned files"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter analyze"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter test test/features/week_calendar/presentation/week_calendar_placeholder_test.dart test/features/week_calendar/presentation/week_calendar_view_test.dart with positive count"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter test"
  - kind: command
    required: true
    owner: worker
    detail: "rtk git diff --check"

### Task_3: Independently review timer and UI-state safety
- type: review
- owns: []
- depends_on: [Task_2]
- description: |
  Review timer/lifecycle correctness and independently execute minute-boundary, resume, disposal, and scroll/page preservation acceptance tests.
- acceptance:
  - Reviewer status is APPROVED with no blocking finding.
  - Evidence covers two consecutive minute updates, lifecycle pause/resume, disposal, and unchanged scroll/page/zoom/draft state.
- validation:
  - kind: e2e
    required: true
    owner: reviewer
    detail: "Run focused Flutter widget acceptance for time-line movement and UI-state preservation."
  - kind: review
    required: true
    owner: reviewer
    detail: "Review timer drift, lifecycle races, stale callbacks, scroll resets, and fake-clock determinism."

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]
- Wave 2 (parallel): [Task_2]
- Wave 3 (parallel): [Task_3]

## E2E / Visual Validation Spec

- provider: Flutter widget tests
- artifact_root: Flutter test output
- base_url: n/a
- app_start_command: n/a
- readiness_check: Calendar widget renders with an overridden mutable clock.
- flows: minute boundary before/after; second minute; paused time passage; resume immediate catch-up; dispose with pending timer; now-only rebuild while scrolled/paged/zoomed/drafting.
- viewports: existing calendar widget-test surface including compact phone constraints.
- evidence_requirements: positive executed-test counts, no Flutter exceptions, exact expected minute values, and unchanged scroll/page state.
- known_flakiness: tests must update the injected clock before pumping fake time so wall-clock and timer time remain deterministic.

## Rollback / Safety
- Remove the placeholder minute timer/observer and restore now-triggered initial scrolling; no persistence, native alarm, or schema rollback is needed.

## Progress Log (append-only)

- 2026-07-15 Wave 3 completed: [Task_3]
  - Summary: Reviewer approved the minute-boundary timer, lifecycle cleanup, repeated-resume uniqueness, and simultaneous UI-state preservation after the requested evidence revision.
  - Validation evidence: Reviewer reran analysis, 41 focused calendar tests, all 313 Flutter tests with concurrency one, and `git diff --check`; all passed.
  - Notes: The only residual risk is dynamic replacement of the production-fixed clock provider taking up to one minute to appear, which is outside this plan's clock-source contract.
- 2026-07-15 Wave 2 completed: [Task_2]
  - Summary: Added a foreground-only next-minute one-shot timer, immediate resume catch-up, lifecycle/dispose cancellation, and removed now-only initial-scroll reapplication.
  - Validation evidence: Formatting and analysis passed; focused calendar tests increased from 37 to 39 and passed; all 311 Flutter tests passed with concurrency one; `git diff --check` passed.
  - Notes: Initial full-suite attempts exhausted the macOS temporary volume without assertion failures. Removing 2.1GB of regenerable Flutter build output via `flutter clean` restored 2.6GB and the required suite then passed.
- 2026-07-15 Wave 3 requested revision: [Task_3]
  - Summary: Reviewer found no proven runtime defect but rejected the evidence as incomplete for non-default zoom/draft preservation, all non-active lifecycle states, and repeated-resume timer uniqueness.
  - Validation evidence: Existing tests directly proved page/vertical offset, paused/resumed/dispose, and two minute boundaries but did not exercise every acceptance branch.
  - Notes: Return to Task_2 for focused regression tests, then repeat the independent review gate.
- 2026-07-15 Wave 2 revision completed: [Task_2]
  - Summary: Added direct regression evidence for simultaneous draft, 80px/hour zoom, next-week page, and 600px vertical-offset retention; all four non-active lifecycle states; and repeated-resume timer uniqueness.
  - Validation evidence: Focused calendar tests increased to 41 and passed; analysis passed; all 313 Flutter tests passed with concurrency one; `git diff --check` passed.
  - Notes: Expanded tests exposed no production implementation defect, so source behavior remained unchanged after the initial timer/scroll fix.
- 2026-07-15 Wave 1 completed: [Task_1]
  - Summary: Confirmed that `clock()` is sampled only during incidental rebuilds and that the painter already reacts correctly to a fresh `now`.
  - Validation evidence: Research mapped placeholder/view symbols and ran the 37 existing focused calendar tests successfully.
  - Notes: Implementation must remove now-only initial-scroll reapplication or the new minute timer would jump the user's viewport every minute.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-15 Decision: Refresh on each minute boundary and immediately on resume while preserving navigation.
  - Trigger / new insight: The user observed that the red current-time line moves only occasionally because unrelated rebuilds are the only refresh source.
  - Plan delta (what changed): Add a lifecycle-aware one-shot minute timer and stop treating every now change as an initial-scroll trigger.
  - Tradeoffs considered: `Timer.periodic` is simpler but drifts and behaves poorly across suspension or wall-clock changes; auto-scrolling on resume would override user context.
  - User approval: yes; the user proposed reopening refresh and approximately one-minute updates.
- 2026-07-15 Decision: Require direct state-preservation and lifecycle-branch evidence.
  - Trigger / new insight: Reviewer showed that green broad suites did not directly prove every state named in Task_2/Task_3 acceptance.
  - Plan delta (what changed): Add tests with a real draft and non-default zoom across now updates, cover inactive/hidden/detached timer cancellation, and prove repeated resume does not create duplicate ticks.
  - Tradeoffs considered: Treating existing zoom/draft tests as indirect coverage is cheaper but cannot refute timer-driven rebuild resets.
  - User approval: implicit within the requested reliable minute refresh and existing accepted plan.

## Notes
- Risks: timer lifecycle leaks, stale callback races, fake-clock boundary churn, and unintended scroll/page resets.
- Edge cases: exact minute boundary, pause immediately before a tick, resume after multiple minutes or midnight, dispose with a pending callback, and off-today pages.
- Quality routing note: L2 for Flutter/Dart UI lifecycle and timer ordering; security, persistence, platform channels, and native Android are out of scope. Required checks are focused/full Flutter tests, analysis, formatting, diff hygiene, and independent timer/state review.
