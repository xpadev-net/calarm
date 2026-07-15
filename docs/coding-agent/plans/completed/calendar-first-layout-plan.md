# Plan: Calendar-first home layout

- status: done
- generated: 2026-07-15
- last_updated: 2026-07-15
- work_type: code

## Goal

- Make the weekly calendar the full primary surface and move secondary controls into a header-accessible side drawer.

## Definition of Done

- The calendar fills the available body area in compact portrait and landscape layouts.
- Alarm, settings, and wake-plan surfaces remain reachable through an explicit AppBar action.
- Flutter analysis, targeted tests, and the full test suite pass.
- Independent review approves the layout and interaction evidence.

## Scope / Non-goals

- Scope: home scaffold information architecture, calendar height behavior, and affected widget tests.
- Non-goals: copying Google branding, adding week navigation controls, changing calendar event behavior, or adding a permanent desktop sidebar.

## Context (workspace)

- Related files/areas: `lib/app.dart`, `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`, and their widget tests.
- Existing patterns or references: Material 3 Scaffold/AppBar and the existing feature placeholder panels.
- Repo reference docs consulted: root `AGENTS.md`; repository rule suite is absent.

## Open Questions (max 3)

- None blocking.

## Assumptions

- An overlay end drawer is preferable to a permanent sidebar because compact widths must preserve seven calendar columns.
- Existing secondary panels should remain intact and scroll together inside the drawer.

## Tasks

### Task_1: Research the current layout

- type: research
- owns: []
- depends_on: []
- description: |
  Map the current Flutter layout, relevant tests, and responsive constraints.
- acceptance:
  - Relevant layout and test files are identified.
  - A bounded implementation recommendation and validation commands are documented.
- validation:
  - kind: review
    required: true
    owner: orchestrator
    detail: "Research report cites concrete files and responsive constraints."

### Task_2: Implement the calendar-first scaffold

- type: impl
- owns:
  - lib/app.dart
  - lib/features/week_calendar/presentation/week_calendar_placeholder.dart
  - test/app_scaffold_test.dart
  - test/features/week_calendar/presentation/week_calendar_placeholder_test.dart
- depends_on: [Task_1]
- description: |
  Expand the calendar to the full body, move secondary panels into an AppBar-accessible end drawer, and update focused widget coverage.
- acceptance:
  - The calendar is the only primary body surface and uses the available height without a 720px cap.
  - Alarm, settings, and wake-plan panels remain reachable in a scrollable end drawer.
  - The drawer affordance has a stable key and accessible tooltip.
  - Compact portrait and landscape widget tests cover the new interaction.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "rtk dart format --set-exit-if-changed on changed Dart files"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter analyze"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter test test/app_scaffold_test.dart test/features/week_calendar/presentation/week_calendar_placeholder_test.dart"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter test"

### Task_3: Independently review UI behavior

- type: review
- owns: []
- depends_on: [Task_2]
- description: |
  Review the diff and run focused widget-based visual/layout acceptance checks.
- acceptance:
  - Reviewer status is APPROVED.
  - Calendar prominence and drawer reachability are evidenced at compact portrait and landscape sizes.
- validation:
  - kind: e2e
    required: true
    owner: reviewer
    detail: "Run Flutter widget acceptance flows for compact portrait and landscape layouts and inspect the rendered hierarchy."
  - kind: review
    required: true
    owner: reviewer
    detail: "Review the diff against all acceptance criteria and regression risks."

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]
- Wave 2 (parallel): [Task_2]
- Wave 3 (parallel): [Task_3]

## E2E / Visual Validation Spec

- provider: Flutter widget test harness (Playwright is not applicable to the native Flutter widget surface)
- artifact_root: Flutter test output; reviewer may add screenshots under `artifacts/ui/` if useful
- base_url: n/a
- app_start_command: `rtk flutter test test/app_scaffold_test.dart`
- readiness_check: Widget tests pump the loaded home surface to a settled state.
- flows: verify the calendar is visible as the primary surface; open the AppBar drawer action; verify alarm, settings, and wake-plan panels are reachable by scrolling.
- viewports: compact portrait 320x568 and compact landscape 568x320 (or the repository's existing equivalent fixtures).
- evidence_requirements: exact test commands, executed-test result, and reviewer diff inspection notes.
- known_flakiness: provider-backed loading requires existing test overrides and settling helpers.

## Rollback / Safety

- Revert the scaffold/drawer and height calculation changes; no persistence, schema, or API behavior is modified.

## Progress Log (append-only)

- 2026-07-15 Wave 1 completed: [Task_1]
  - Summary: Mapped the current scaffold, calendar sizing, secondary panels, responsive constraints, and tests.
  - Validation evidence: Research report cited `lib/app.dart`, calendar presentation files, and focused widget tests.
  - Notes: Selected an overlay end drawer to preserve compact calendar width.
- 2026-07-15 Wave 2 completed: [Task_2]
  - Summary: Made the weekly calendar the sole body surface, moved secondary panels into a scrollable end drawer, removed the 720px height cap, and updated focused widget coverage.
  - Validation evidence: Formatting check passed; `rtk flutter analyze` passed; 19 focused tests passed; all 266 repository tests passed.
  - Notes: All edits stayed inside Task_2 ownership. Initial test-fixture assumptions were corrected before the passing reruns.
- 2026-07-15 Wave 3 completed: [Task_3]
  - Summary: Independent review approved the calendar-first hierarchy, drawer accessibility, responsive behavior, and regression coverage with no findings.
  - Validation evidence: Reviewer reran 19 focused tests, static analysis, all 266 repository tests, and `git diff --check`; all passed.
  - Notes: Compact portrait 320x568 and landscape 568x320 flows were explicitly covered. No blockers remain.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-15 Decision: Proceed without a separate plan-approval pause.
  - Trigger / new insight: The user directly requested a clear calendar-first layout and the research found a bounded, reversible implementation.
  - Plan delta (what changed): Use an AppBar-accessible end drawer and remove the calendar's 720px height cap.
  - Tradeoffs considered: A permanent sidebar would reduce the seven-column grid on phones; an overlay drawer preserves width.
  - User approval: waived by Orchestrator based on explicit implementation intent and low-risk reversible scope.

## Notes

- Risks: An active alarm becomes less prominent inside the drawer; retain a permanently visible AppBar affordance.
- Edge cases: compact landscape height, provider error state, and drawer control width.
- Quality routing note: L1, low-risk localized Flutter UI change; security, data integrity, migration, concurrency, external dependency, contract, and backend concerns are out of scope.
