# Plan: Inline calendar draft creation

- status: done
- generated: 2026-07-15
- last_updated: 2026-07-15
- work_type: code

## Goal
- Replace immediate create-modal opening with a Google Calendar-style provisional block that can be adjusted directly on the calendar before explicit save or cancel.

## Definition of Done
- Tapping an empty slot creates a local draft block and compact bottom editor without opening a modal.
- The draft can be moved and resized on the calendar with five-minute snapping and safe duration bounds.
- Save uses existing wake-plan defaults/service semantics, and failures retain a retryable draft without duplicate identity or metadata drift.
- Existing calendar paging, scrolling, pinch zoom, persisted-block detail, provider-error, three-day/week, and compact layouts remain correct.
- Required Flutter checks pass and independent review approves gesture/state evidence.

## Scope / Non-goals
- Scope: inline draft state/model, on-calendar overlay and gestures, compact save/cancel editor, service submission/retry, and focused tests.
- Non-goals: title editing, attendee fields, arbitrary recurrence editing, automatic modal opening, persistent unsaved drafts, or pixel-identical Google UI.

## Context (workspace)
- Related files/areas: week calendar interaction/view/placeholder, wake-plan creation defaults/service, and focused widget/model tests.
- Existing patterns or references: attached Google Calendar screenshot with outlined provisional block, resize handles, and bottom save/cancel panel.
- Repo reference docs consulted: root `AGENTS.md`, `docs/coding-agent/lessons.md`; repository rule suite is absent.

## Open Questions (max 3)
- None blocking.

## Assumptions
- A tapped slot is the draft start; its target/end defaults to the configured start-offset duration, normally 60 minutes.
- Draft duration is clamped from 5 minutes through 3 hours and snapped to five-minute boundaries.
- The compact editor shows the selected date/time range plus Save and Cancel; detailed fields remain at existing defaults for this first inline flow.
- While a draft exists, horizontal page changes and 3/7-day switching are disabled; ordinary vertical scrolling and pinch zoom remain available when the draft itself is not being manipulated.

## Tasks

### Task_1: Research the existing create transition and gesture model
- type: research
- owns: []
- depends_on: []
- description: |
  Map empty-slot input, create-sheet/service semantics, block rendering, gesture arbitration, and tests.
- acceptance:
  - Current state transitions and persistence/retry invariants are identified.
  - A bounded inline draft interaction and implementation scope are specified from concrete source evidence.
- validation:
  - kind: review
    required: true
    owner: orchestrator
    detail: "Research covers draft defaults, move/resize, save/cancel/retry, past/provider errors, and gesture conflicts."

### Task_2: Implement inline draft creation
- type: impl
- owns:
  - lib/features/week_calendar/model/week_calendar_interaction.dart
  - lib/features/week_calendar/presentation/week_calendar_view.dart
  - lib/features/week_calendar/presentation/week_calendar_placeholder.dart
  - lib/features/wake_plan/ui/inline_wake_plan_editor.dart
  - test/features/week_calendar/model/week_calendar_interaction_test.dart
  - test/features/week_calendar/presentation/week_calendar_view_test.dart
  - test/features/week_calendar/presentation/week_calendar_placeholder_test.dart
  - test/features/wake_plan/ui/create_wake_plan_sheet_test.dart
- depends_on: [Task_1]
- description: |
  Add a transient draft interval, direct manipulation overlay, compact bottom editor, and existing-service save/retry path without automatic modal presentation.
- acceptance:
  - Empty-slot tap creates one visible outlined draft using the configured default duration and never automatically opens `CreateWakePlanSheet`.
  - Draft body movement and top/bottom resize handles support day/time adjustment, five-minute snapping, 5-minute minimum, 3-hour maximum, and cross-midnight absolute times.
  - Save is disabled with inline guidance when the target/end is not in the future; cancel removes only an unsubmitted draft.
  - Save success persists/schedules once, invalidates providers, removes the draft, and renders the resulting plan; save failure retains stable retry identity/metadata and an inline error.
  - Draft manipulation exclusively owns conflicting one-pointer scroll/page gestures, pinch safely interrupts manipulation without discarding the draft, and normal gestures restore on end/cancel.
  - Existing persisted block detail, provider error, pinch zoom, three-day/week, compact portrait/landscape, and create-sheet unit behavior remain passing.
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
    detail: "rtk flutter test for focused interaction/view/placeholder/create-sheet test files"
  - kind: command
    required: true
    owner: worker
    detail: "rtk flutter test"
  - kind: command
    required: true
    owner: worker
    detail: "rtk git diff --check"

### Task_3: Independently review draft UX and state safety
- type: review
- owns: []
- depends_on: [Task_2]
- description: |
  Inspect the diff and independently execute model/widget acceptance flows for inline creation, gesture arbitration, and retry state.
- acceptance:
  - Reviewer status is APPROVED with no blocking findings.
  - Evidence covers tap-to-draft, move, both resize handles, cross-day bounds, save/cancel/retry, modal absence, pinch/scroll recovery, and compact layouts.
- validation:
  - kind: e2e
    required: true
    owner: reviewer
    detail: "Run Flutter model/widget acceptance flows in compact portrait and landscape plus 3-day/week modes."
  - kind: review
    required: true
    owner: reviewer
    detail: "Review draft lifecycle, persistence/retry identity, gesture cleanup, and regression coverage against acceptance."

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]
- Wave 2 (parallel): [Task_2]
- Wave 3 (parallel): [Task_3]

## E2E / Visual Validation Spec

- provider: Flutter widget test harness; physical-device touch feel is optional follow-up when ADB is available
- artifact_root: Flutter test output; optional screenshots under `artifacts/ui/`
- base_url: n/a
- app_start_command: `rtk flutter test test/features/week_calendar/model/week_calendar_interaction_test.dart test/features/week_calendar/presentation/week_calendar_view_test.dart test/features/week_calendar/presentation/week_calendar_placeholder_test.dart test/features/wake_plan/ui/create_wake_plan_sheet_test.dart`
- readiness_check: Tests pump provider-backed calendar surfaces to a settled state.
- flows: tap an empty slot; observe draft/editor and no modal; move draft; resize start/end; test min/max/cross-midnight; cancel; save success; save failure/retry; pinch interruption; scroll recovery; persisted-block detail.
- viewports: 320x568 portrait, 568x320 landscape, three-day mode, and seven-day mode.
- evidence_requirements: exact commands, positive executed-test counts, no overflow/exception, state/identity assertions, and reviewer source/diff notes.
- known_flakiness: raw pointer drag/pinch tests require explicit pointer-up/cancel cleanup and floating-point tolerance.

## Rollback / Safety
- Restore the immediate create-sheet callback and remove transient draft/editor code; no schema or persisted-format changes are planned.

## Progress Log (append-only)

- 2026-07-15 Wave 1 completed: [Task_1]
  - Summary: Mapped immediate modal creation, persistence-before-scheduling retry invariants, block projection, gestures, and relevant tests.
  - Validation evidence: Research cited exact source paths and proposed bounded tap/move/resize/save/cancel behavior.
  - Notes: Selected a compact editor without title/details fields to keep the first inline flow coherent and avoid misleading unused metadata.
- 2026-07-15 Wave 2 completed: [Task_2]
  - Summary: Implemented local tap-to-draft creation, outlined cross-day block rendering, body move, top/bottom resize, compact Save/Cancel/Retry editor, and stable service retry state.
  - Validation evidence: Formatting and analysis passed; after review fixes 68 focused tests passed; all 290 repository tests passed; `git diff --check` passed.
  - Notes: All Worker changes stayed within Task_2 ownership. Review fixes separated corner handle/body hit surfaces down to the exact 5-minute minimum at both zoom bounds, clamped 3/7-day edges, added timer/resume expiry, and proved one save call under delayed double taps.
- 2026-07-15 Wave 3 completed: [Task_3]
  - Summary: Independent review approved inline draft interaction and all review-driven geometry, range, timer, lifecycle, retry, and double-save fixes with no remaining findings.
  - Validation evidence: Reviewer reran 68 focused tests, static analysis, all 290 repository tests, and `git diff --check`; all passed.
  - Notes: Compact portrait/landscape, 3/7-day modes, exact 5-minute drafts at both zoom bounds, cross-midnight, and partial-failure retry were explicitly covered.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-15 Decision: Treat tapped time as draft start and defer persistence until explicit Save.
  - Trigger / new insight: The requested Google Calendar-style reference shows spatial interval selection before form submission, unlike the current target-time-to-modal transition.
  - Plan delta (what changed): Create a default-duration local interval, allow direct manipulation, and expose compact save/cancel controls without automatic modal opening.
  - Tradeoffs considered: Keeping tap as target time would preserve the old semantic but conflict with the visible interval-selection model; adding full title/details editing would expand scope beyond the requested adjustment flow.
  - User approval: waived by Orchestrator because the user explicitly requested this interaction model and supplied a visual reference.
- 2026-07-15 Decision: Harden physical hit geometry, visible-range bounds, and autonomous deadline updates.
  - Trigger / new insight: Independent review found callback-level tests did not prove usable body drag geometry, edge recovery, or idle clock rollover.
  - Plan delta (what changed): Separate body/handle hit surfaces, clamp draft movement to the current range, and add timer/lifecycle plus delayed double-Save regressions.
  - Tradeoffs considered: Edge paging could preserve free movement but adds paging-state complexity while a draft intentionally locks pages; clamping keeps the draft recoverable.
  - User approval: not separately required; these are in-scope correctness fixes for the requested direct manipulation.

## Notes
- Risks: nested gesture arbitration, cross-midnight segment projection, past-target validation, persistence-before-scheduling partial failure, stable retry identity, compact editor height, and unsaved-draft loss on mode/page changes.
- Edge cases: 23:55 tap, min/max resize, body drag across days, two-pointer takeover, pointer cancel, provider/service failure, repeated Save, and persisted block overlap.
- Quality routing note: L2 due to UI gesture and persistence/retry boundary changes; security, migration, external dependency, and backend contract concerns remain out of scope.
