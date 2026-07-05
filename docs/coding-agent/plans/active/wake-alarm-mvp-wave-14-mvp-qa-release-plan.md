# Plan: Wake Alarm MVP Wave 14 - MVP End-to-End QA and Release Readiness

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-06
- work_type: review

## Goal

- MVP代表フローを通し、実機ログ、E2E/Visual evidence、未解決リスク、リリース可否を整理する。

## Definition of Done

- 最小縦切り「週カレンダーで07:00をタップ、06:00〜07:00のWake Plan作成、1回止めても次が鳴る」が通っている。
- 作成、編集、削除、繰り返し、次回スキップ、テストアラーム、権限不足警告のQAログがある。
- iOS/Androidそれぞれでロック中、アプリ終了中、再起動後の重要挙動が記録されている。
- MVP Definition of Doneに対してAPPROVEDまたはBLOCKEDが記録されている。

## Scope / Non-goals

- Scope:
  - `docs/qa/**`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-implementation-plan.md`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-wave-*.md`
- Non-goals:
  - 新機能追加。
  - 未承認のスコープ拡張。

## Context (workspace)

- Related files/areas:
  - All Wave 1-13 child plans.
  - `docs/qa/**`
- Existing patterns or references:
  - Parent Definition of Done.
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: Native validationがOS beta availabilityで遅れた場合のrelease scheduleをどう扱うか。
- Q2: MVP後にQA artifactsをどのタイミングで整理するか。
- Q3: platform限定MVP判断が必要になった場合、release notesへどう記載するか。

## Assumptions

- A1: Final QAではReviewer-owned evidenceを必須にする。
- A2: 実機で確認できないnative alarm挙動はwaiveせずBLOCKEDとして扱う。
- A3: 発火、cancel、未来Occurrence維持、権限警告のいずれかがBLOCKEDならMVPリリース停止とする。
- A4: QA artifact命名規約は`docs/qa/artifacts/<wave>-<platform>-<flow>-<YYYYMMDD-HHMM>.<ext>`に固定する。
- A5: QA artifactsはMVP中すべて保持し、MVP後の整理は別判断にする。
- A6: iOS/Androidの片方のみAPPROVEDの場合は通常MVPへ進めず、platform限定MVPとして別途明示判断する。
- A7: Wave 3 allowed implementation to continue without runtime approval; Wave 14 is the later gate that must resolve or explicitly block deferred runtime validation.
- A8: A platform cannot be marked release APPROVED while wake delivery, lock/terminated behavior, permission handling, stop UI, cancel semantics, 13-equivalent reservations, or Android reboot restore remain pending/BLOCKED.

## Tasks

### Task_1: MVP End-to-End QA and Release Readiness
- type: review
- owns:
  - docs/qa/**
  - docs/coding-agent/plans/active/wake-alarm-mvp-implementation-plan.md
  - docs/coding-agent/plans/active/wake-alarm-mvp-wave-*.md
- depends_on: []
- description: |
  Original Task_24. MVP代表フローを通し、実機ログ、E2E/Visual evidence、未解決リスク、リリース可否を整理する。
- acceptance:
  - 最小縦切り「週カレンダーで07:00をタップ、06:00〜07:00のWake Plan作成、1回止めても次が鳴る」が通っている。
  - 作成、編集、削除、繰り返し、次回スキップ、テストアラーム、権限不足警告のQAログがある。
  - iOS/Androidそれぞれでロック中、アプリ終了中、再起動後の重要挙動が記録されている。
  - MVPで残す制約と次リリース候補がdocsに整理されている。
  - 親プランと子プランのProgress LogとDecision Logが最新化されている。
  - Wave 3でdeferされたiOS 26+ and Android API 36 runtime validationがpass/BLOCKED/explicit release decisionとして整理され、未検証のままAPPROVEDになっていない。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter analyze"
  - kind: command
    required: true
    owner: worker
    detail: "flutter test"
  - kind: e2e
    required: true
    owner: reviewer
    detail: "E2E / Visual Validation SpecのMVP主要フローをiOS/Android対象で実行し、Wave 3 deferred runtime casesをrelease gateとして確認する"
  - kind: review
    required: true
    owner: reviewer
    detail: "MVP Definition of Doneに対する最終レビューを行い、deferred runtime validationが残るplatformをAPPROVEDにしない"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]

## E2E / Visual Validation Spec

- provider: playwright-cli for Flutter web smoke where applicable; iOS/Android simulator or実機 manual evidence for native alarm behavior.
- artifact_root:
  - `.playwright-cli/`
  - `docs/qa/artifacts/`
- base_url:
  - Flutter web validation: local dev server URL.
  - Native validation: not applicable.
- app_start_command:
  - Flutter web validation: `flutter run -d chrome` or project-defined equivalent.
  - Native validation: `flutter run -d <device-id>`.
- readiness_check:
  - Home week calendar is visible.
  - Native validation device has required OS version and permissions state documented.
- flows:
  - Week calendar renders current week, time grid, current time line, and empty state.
  - Tap a day/time cell, open create sheet, verify default 60分/5分 and preview count.
  - Create one-shot Wake Plan, verify block spans `targetAt - window` to `targetAt`.
  - Edit target time, verify old Occurrences are cancelled and new preview/block is shown.
  - Delete Wake Plan, verify block disappears and future native alarms are cancelled.
  - Create repeating weekday Wake Plan, skip next, verify next instance is skipped and following instance remains.
  - Trigger test alarm, stop current alarm, verify future Occurrence remains scheduled.
  - Deny or revoke relevant permissions, verify warning appears and app does not silently claim scheduling success.
- viewports:
  - Mobile compact: 390x844.
  - Mobile large: 430x932.
  - Tablet: 768x1024 if supported.
- evidence_requirements:
  - Screenshot or recording of week calendar, create sheet preview, detail/edit/delete flow, settings health warning, alarm ringing UI.
  - iOS/Android logs showing schedule/cancel results and platformAlarmId mapping.
  - Manual notes for lock screen, app terminated, Focus/silent, notification denied, exact alarm denied, and reboot behavior.
  - Explicit pass/BLOCKED status for all Wave 3 deferred runtime cases: wake reliability, lock/terminated behavior, permissions, full-screen stop UI, cancel semantics, 13-equivalent reservations, and Android reboot restore.
  - Artifact filenames follow `docs/qa/artifacts/<wave>-<platform>-<flow>-<YYYYMMDD-HHMM>.<ext>`.
- known_flakiness:
  - Real alarm firing depends on simulator/device capabilities, OS permissions, and power settings.
  - AlarmKit availability requires iOS 26+.
  - Android full-screen behavior can differ between lock state, notification permission state, and OEM policy.

## Rollback / Safety

- Final QA must include cleanup/cancel of known test alarms.
- Release readiness cannot be APPROVED if native alarms remain scheduled unintentionally after tests.
- Release readiness cannot be APPROVED for a platform while Wave 3 deferred runtime validation is pending or BLOCKED, unless a later explicit product/release decision records the waiver or platform-limited scope.
- Do not delete MVP QA artifacts before final release readiness is recorded.

## Progress Log (append-only)

- 2026-07-06 Wave 3 decision integrated.
  - Final QA owns the later gate for deferred iOS 26+ and Android API 36 runtime validation.
  - Runtime-unapproved implementation evidence is not enough for release approval.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-06 Decision: Keep Wave 3 deferred runtime validation as final release gate.
  - Trigger / new insight: Wave 3 permits implementation from API-surface feasibility only.
  - Plan delta (what changed): Wave 14 final review must explicitly resolve all deferred runtime cases before marking a platform APPROVED.
  - Tradeoffs considered: Implementation momentum is preserved, but release confidence still depends on platform runtime evidence.
  - User approval: yes, from Wave 3 deferment.

- 2026-07-05 Decision: Keep final QA as its own wave.
  - Trigger / new insight: MVP Definition of Done spans UI, domain, persistence, native behavior, and docs.
  - Plan delta (what changed): Wave 14 owns final evidence and release readiness.
  - Tradeoffs considered: It duplicates some validation from earlier waves, but provides release-level confidence.
  - User approval: pending.

- 2026-07-05 Decision: Define release-blocking native alarm criteria.
  - Trigger / new insight: User accepted the recommended release quality bar.
  - Plan delta (what changed): Final QA now treats firing, cancel, future occurrence preservation, and permission warning failures as release blockers.
  - Tradeoffs considered: This may delay MVP, but these criteria are core to an alarm app's trustworthiness.
  - User approval: yes.

- 2026-07-05 Decision: Fix QA artifact naming.
  - Trigger / new insight: User requested applying the recommended QA artifact convention.
  - Plan delta (what changed): Wave 14 now requires artifact filenames under `docs/qa/artifacts/` to follow the wave/platform/flow/timestamp pattern.
  - Tradeoffs considered: The convention is simple enough for manual evidence while still sortable by wave and platform.
  - User approval: yes.

- 2026-07-05 Decision: Keep MVP QA artifacts and require explicit platform-limited release decision.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 14 now keeps all QA artifacts during MVP and blocks normal MVP if only one platform is approved.
  - Tradeoffs considered: Retaining artifacts costs repository/storage space, but preserves release evidence while native behavior is still being validated.
  - User approval: yes.

## Notes

- Risks:
  - Device availability can block native validation.
  - Final QA may expose cross-wave integration issues requiring replan.
