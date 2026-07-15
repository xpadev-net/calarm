# Plan: Calendar view controls

- status: done
- generated: 2026-07-15
- last_updated: 2026-07-15
- work_type: code

## Goal
- Refine the calendar-first UI with a left tools drawer, silent empty weeks, bounded two-finger vertical pinch zoom, and three-day/week display switching.

## Definition of Done
- The unwanted empty-week message is absent while the empty grid remains usable.
- Secondary tools open from the left and remain reachable.
- Two-finger pinch zoom changes hour density within safe bounds without losing the viewed time context, with no zoom buttons shown.
- Three-day and seven-day modes render, page, tap, and place wake-plan blocks using the selected day count.
- Required Flutter checks pass and independent review approves compact layouts and interactions.

## Scope / Non-goals
- Scope: home drawer direction, calendar toolbar/state, variable-day layout/paging, vertical zoom, and focused tests.
- Non-goals: persistent user preferences, zoom buttons, arbitrary day counts, backend/domain/schema changes, or Google branding.

## Context (workspace)
- Related files/areas: home scaffold, week calendar placeholder/view/interaction model, and widget/model tests.
- Existing patterns or references: calendar-first uncommitted baseline and existing `WeekRange.visibleDays` support.
- Repo reference docs consulted: root `AGENTS.md`, `docs/coding-agent/lessons.md`; repository rule suite is absent.

## Open Questions (max 3)
- None blocking.

## Assumptions
- Zoom uses a two-finger pinch gesture; one-finger vertical scroll and horizontal paging must remain available.
- Switching between three-day and week views resets to the current period for deterministic behavior.
- Display settings remain local to the home calendar instance and are not persisted.

## Tasks

### Task_1: Research variable calendar presentation
- type: research
- owns: []
- depends_on: []
- description: |
  Map the current drawer, empty state, day-column assumptions, paging, scroll preservation, and relevant tests.
- acceptance:
  - Exact implementation points and variable-day assumptions are identified.
  - Zoom bounds, mode-switch semantics, responsive risks, and validation commands are specified.
- validation:
  - kind: review
    required: true
    owner: orchestrator
    detail: "Research cites concrete paths and covers all four requested behaviors."

### Task_2: Implement calendar presentation controls
- type: impl
- owns:
  - lib/app.dart
  - lib/features/week_calendar/presentation/week_calendar_placeholder.dart
  - lib/features/week_calendar/presentation/week_calendar_view.dart
  - lib/features/week_calendar/model/week_calendar_interaction.dart
  - test/app_scaffold_test.dart
  - test/features/week_calendar/presentation/week_calendar_placeholder_test.dart
  - test/features/week_calendar/presentation/week_calendar_view_test.dart
  - test/features/week_calendar/model/week_calendar_interaction_test.dart
- depends_on: [Task_1]
- description: |
  Move tools to a left drawer, suppress the empty-week message, add bounded vertical zoom controls, and support three-day/week rendering and paging.
- acceptance:
  - The tools affordance opens a left drawer and retains its key, tooltip, scroll container, and secondary panels.
  - `No wake plans scheduled for this week` is not rendered, while the empty calendar grid remains visible.
  - Two-finger pinch zoom adjusts hour height continuously from 36 through 92, preserves the viewed time context around the focal point, and exposes no zoom buttons.
  - Three-day mode uses three columns and three-day paging for headers, grid lines, blocks, and tap targets; week mode uses seven.
  - Switching modes returns to the current three-day or week period and existing create/detail/provider-error behavior remains intact.
  - Compact portrait and landscape tests complete without overflow or exceptions.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "rtk dart format --output=none --set-exit-if-changed on all owned Dart files"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter analyze"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter test for the four focused app/calendar test files"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter test"
  - kind: command
    required: true
    owner: worker
    detail: "rtk git diff --check"

### Task_3: Independently review UI and interaction behavior
- type: review
- owns: []
- depends_on: [Task_2]
- description: |
  Review the diff and independently execute focused widget/model acceptance flows.
- acceptance:
  - Reviewer status is APPROVED with no blocking findings.
  - Evidence covers left drawer, hidden empty message, zoom bounds/scroll preservation, three-day/week switching, paging, and compact layouts.
- validation:
  - kind: e2e
    required: true
    owner: reviewer
    detail: "Run the Flutter widget/model acceptance spec in compact portrait and landscape viewports."
  - kind: review
    required: true
    owner: reviewer
    detail: "Inspect current source and diff against UI, accessibility, state, paging, and regression risks."

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]
- Wave 2 (parallel): [Task_2]
- Wave 3 (parallel): [Task_3]

## E2E / Visual Validation Spec

- provider: Flutter widget test harness
- artifact_root: Flutter test output; optional screenshots under `artifacts/ui/`
- base_url: n/a
- app_start_command: `rtk flutter test test/app_scaffold_test.dart test/features/week_calendar/presentation/week_calendar_placeholder_test.dart test/features/week_calendar/presentation/week_calendar_view_test.dart test/features/week_calendar/model/week_calendar_interaction_test.dart`
- readiness_check: Tests pump provider-backed home/calendar surfaces to a settled state.
- flows: open the left drawer and reach all secondary sections; verify empty grid without the removed copy; use two-pointer scale gestures to zoom to both bounds and preserve time context while retaining one-finger scrolling/paging; switch to three-day mode, page by three days, exercise tap/block layout, then return to week mode.
- viewports: 320x568 portrait, 568x320 landscape, and a tall viewport for vertical-density behavior.
- evidence_requirements: exact commands, positive executed-test counts, no overflow/exception, and reviewer source/diff notes.
- known_flakiness: provider-backed tests require existing overrides; scroll-position assertions should allow normal floating-point tolerance.

## Rollback / Safety
- Revert view-state and drawer changes; no persisted data, schema, native alarm scheduling, or API behavior changes.

## Progress Log (append-only)

- 2026-07-15 Wave 1 completed: [Task_1]
  - Summary: Mapped fixed seven-day assumptions, empty-state rendering, drawer direction, zoom scroll behavior, and affected tests.
  - Validation evidence: Research cited source symbols and specified bounds, paging semantics, compact risks, and commands.
  - Notes: `WeekRange.visibleDays` already supports variable day counts; display-mode changes can remain presentation-local.
- 2026-07-15 Wave 2 completed: [Task_2]
  - Summary: Implemented the left drawer, silent empty grid, pinch-only bounded vertical zoom, and three-day/week modes across paging, headers, blocks, grid lines, and tap mapping.
  - Validation evidence: Formatting and analysis passed; after review fixes 42 focused tests passed; all 272 repository tests passed; `git diff --check` passed.
  - Notes: All Worker edits stayed within Task_2 ownership. Review-driven fixes suspend both nested scroll axes during pinch, restore them after release/cancel, and clear stale focal transaction state.
- 2026-07-15 Wave 3 completed: [Task_3]
  - Summary: Independent re-review approved all four requested behaviors after the nested gesture-arbitration fixes, with no remaining actionable findings.
  - Validation evidence: Reviewer reran 42 focused tests, static analysis, all 272 repository tests, production absence searches, and `git diff --check`; all passed.
  - Notes: Compact portrait/landscape and two-pointer diagonal/release/cancel flows are covered. Latest debug build could not be installed to the physical device because it disconnected from ADB after code validation.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-15 Decision: Use two-finger pinch zoom and reset mode switches to the current period.
  - Trigger / new insight: The user explicitly rejected zoom buttons and required pinch-in/pinch-out interaction.
  - Plan delta (what changed): Replace planned ± controls with bounded multi-pointer scale gestures while preserving one-finger scrolling/paging; keep deterministic current-period reset for three-day/week switching.
  - Tradeoffs considered: Gesture arbitration is more complex than buttons, but the interaction method is an explicit product requirement.
  - User approval: yes; explicitly corrected during implementation.
- 2026-07-15 Decision: Expand pinch arbitration to the parent pager.
  - Trigger / new insight: Independent review found diagonal two-pointer movement could zoom and page simultaneously, and no-scale cancellation could retain stale focal state.
  - Plan delta (what changed): Disable both vertical and horizontal scrolling during active pinch, clear terminal transaction state, and add diagonal/release/cancel recovery tests.
  - Tradeoffs considered: Local-only gesture handling was simpler but did not provide exclusive two-pointer ownership across nested scrollables.
  - User approval: not separately required; this is an in-scope correctness fix for the explicitly requested pinch behavior.

## Notes
- Risks: hard-coded seven-day divisors, paging stride, scroll reprojection, compact toolbar overflow, and API compatibility of empty-state fields.
- Edge cases: zoom bounds, provider error, empty calendar, future pages, compact landscape, and floating-point scroll offsets.
- Quality routing note: L1, low-to-medium localized Flutter presentation risk; security, data integrity, migration, concurrency, external dependency, backend, and persisted-contract concerns are out of scope.
