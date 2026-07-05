# Plan: Wake Alarm MVP Wave 13 - UI Harmonization and Accessibility

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-05
- work_type: review

## Goal

- MVP UI全体の文言、導線、レイアウト、禁止操作の不在、アクセシビリティを横断確認し、リリース前のUI品質を揃える。

## Definition of Done

- 作成、詳細、編集、削除、スキップ、設定、鳴動の文言が一貫している。
- 鳴動画面に禁止導線がない。
- モバイル幅でテキストがボタンやカードからはみ出さない。
- UIレビュー結果が`docs/qa/ui-review.md`に記録されている。

## Scope / Non-goals

- Scope:
  - `lib/features/week_calendar/**`
  - `lib/features/wake_plan/ui/**`
  - `lib/features/alarm_ringing/**`
  - `lib/features/settings/**`
  - `docs/qa/ui-review.md`
- Non-goals:
  - 新機能追加。
  - 大規模デザインリブランド。

## Context (workspace)

- Related files/areas:
  - Wave 10 create flow.
  - Wave 11 edit/ringing/health.
  - Wave 12 repeat/skip.
- Existing patterns or references:
  - `requirements.md` の誤操作防止と画面要件。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: Accessibility minimumとしてsemantic labelsまで必須にするか。
- Q2: Tablet viewportをMVP必須にするか、advisoryにするか。
- Q3: 日本語文言の敬体/常体や用語表記をどこまで統一するか。

## Assumptions

- A1: MVP UIはモバイルfirstで検証する。
- A2: 禁止導線の不在はvisual/e2eだけでなくコードレビューでも確認する。
- A3: MVP UI文言は日本語固定で開始する。

## Tasks

### Task_1: UI Harmonization and Accessibility Pass
- type: review
- owns:
  - lib/features/week_calendar/**
  - lib/features/wake_plan/ui/**
  - lib/features/alarm_ringing/**
  - lib/features/settings/**
  - docs/qa/ui-review.md
- depends_on: []
- description: |
  Original Task_23. MVP UI全体の文言、導線、レイアウト、禁止操作の不在、アクセシビリティを横断確認する。
- acceptance:
  - 作成、詳細、編集、削除、スキップ、設定、鳴動の文言が一貫している。
  - 鳴動画面に禁止導線がない。
  - モバイル幅でテキストがボタンやカードからはみ出さない。
  - 重要操作には確認または明確な導線がある。
  - UIレビュー結果がdocs/qa/ui-review.mdに記録されている。
- validation:
  - kind: e2e
    required: true
    owner: reviewer
    detail: "E2E / Visual Validation Specの全UI主要画面をモバイル幅で確認する"
  - kind: review
    required: true
    owner: reviewer
    detail: "UI文言、禁止導線、アクセシビリティ、レスポンシブ崩れをレビューする"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]

## E2E / Visual Validation Spec

- provider: playwright-cli for Flutter web smoke where applicable; native screenshots for alarm UI if required.
- artifact_root:
  - `.playwright-cli/`
  - `docs/qa/artifacts/`
- flows:
  - Week calendar empty and populated states.
  - Create, detail, edit, delete, repeat, skip, settings, health warning, alarm ringing.
  - Verify no "起きた", "残り全部停止", "スヌーズ" equivalent appears in ringing UI.
- viewports:
  - Mobile compact: 390x844.
  - Mobile large: 430x932.
  - Tablet: 768x1024 if supported.
- evidence_requirements:
  - Screenshot set and `docs/qa/ui-review.md` findings table.

## Rollback / Safety

- UI polish must not weaken scheduling/cancel semantics.
- If copy changes affect tests, update tests in the same task.

## Handoff To Next Wave

- Wave 14 uses `docs/qa/ui-review.md` as final QA input.

## Progress Log (append-only)

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Add a dedicated UI harmonization gate before final QA.
  - Trigger / new insight: Feature waves can produce inconsistent text and layout even when individually correct.
  - Plan delta (what changed): Wave 13 becomes the cross-feature UI review.
  - Tradeoffs considered: Adds one review step, but reduces final QA churn.
  - User approval: pending.

## Notes

- Risks:
  - Native AlarmKit UI may not be fully controllable from Flutter.
