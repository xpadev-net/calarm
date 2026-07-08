# Plan: Wake Alarm MVP Wave 14 - MVP End-to-End QA and Release Readiness

- status: in_progress
- generated: 2026-07-05
- last_updated: 2026-07-08
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
- A9: Waiver or platform-limited release decisions are separate product/release decisions; they do not convert unresolved deferred runtime validation into APPROVED.
- A10: CI simulator/emulator smoke can provide near-device implementation evidence for build, install, platform-channel, scheduling/cancel API paths, logs, and artifacts, but it does not replace iOS/Android real-device runtime validation for release approval.
- A11: Baseline CI for format, analyzer/lint, and unit tests is separate release hygiene evidence and must remain green alongside native smoke and real-device evidence.

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
  - Wave 3でdeferされたiOS 26+ and Android API 36 runtime validationがpassまたはBLOCKEDとして整理され、未検証・BLOCKEDのplatformはAPPROVEDになっていない。
  - Baseline CI for format, analyzer/lint, and unit tests is green or has an explicit release-blocking failure record.
  - waiverやplatform-limited scopeが必要な場合は、APPROVED条件ではなく別のproduct/release decision pathとして記録されている。
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
    detail: "MVP Definition of Doneに対する最終レビューを行い、deferred runtime validationがpassで解決していないplatformをAPPROVEDにしない。waiver/platform-limited判断は別decisionとして扱う"

### Task_2: CI Simulator/Emulator Native Smoke Release Evidence
- type: review
- owns:
  - `docs/qa/ci-native-smoke.md`
  - `docs/qa/artifacts/**`
- depends_on:
  - Wave 8 CI simulator/emulator native smoke harness
  - Wave 11 ringing/permission/test-alarm implementation
- description: |
  Re-run and summarize the Wave 8 CI-backed near-device smoke evidence as part of final release readiness, without treating simulator/emulator results as real-device approval.
- acceptance:
  - Wave 8 CI native smoke workflow exists and is runnable manually for release evidence.
  - Android job uses an emulator image closest to the MVP target available in CI, preferring API 36 when available and recording BLOCKED/unavailable evidence when not available.
  - iOS job uses a macOS runner and simulator/runtime closest to the MVP target available in CI, preferring an iOS 26+ runtime when available and recording BLOCKED/unavailable evidence when not available.
  - Release QA reruns or inspects the latest CI artifacts for Flutter test logs, Android `adb` logs, optional `dumpsys alarm`, iOS `simctl` logs, screenshots when available, and updates `docs/qa/ci-native-smoke.md`.
  - Release evidence labels simulator/emulator results as NEAR_DEVICE or BLOCKED, never as real-device APPROVED for wake delivery, lock/terminated behavior, Silent/Focus behavior, full-screen stop UI, or Android reboot restore.
  - If hosted runner SDK/runtime limitations prevent a meaningful iOS/Android smoke, the workflow still records the exact unavailable runner/runtime/toolchain fact and leaves the corresponding release gate BLOCKED.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter analyze"
  - kind: command
    required: true
    owner: worker
    detail: "flutter test"
  - kind: ci
    required: true
    owner: worker
    detail: "Wave 8 GitHub Actions native smoke workflow is rerun or latest artifacts are inspected, and release evidence is updated with NEAR_DEVICE or BLOCKED results"
  - kind: review
    required: true
    owner: reviewer
    detail: "Verify CI smoke evidence is clearly separated from real-device runtime approval and cannot mark deferred Wave 3 cases APPROVED"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (sequential): [Task_2]
- Wave 2 (sequential): [Task_1]

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
- Release readiness cannot be APPROVED for a platform while Wave 3 deferred runtime validation is pending or BLOCKED.
- A later explicit product/release decision may choose a waiver or platform-limited path, but that path must be recorded separately from APPROVED release readiness and must not relabel unresolved runtime validation as pass.
- Do not delete MVP QA artifacts before final release readiness is recorded.

## Progress Log (append-only)

- 2026-07-08 Wave 14 started after Wave 13 completion.
  - Trigger: Wave 13 PR #26 merged with merge commit `abfb5a58c1311a4537338c102ee340bb7baef8cd`.
  - Orchestrator decision: although the original Task Waves section listed Task_1 and Task_2 together, Task_1 owns broad `docs/qa/**` while Task_2 owns `docs/qa/ci-native-smoke.md` and `docs/qa/artifacts/**`, so running them in parallel would create overlapping documentation ownership. Execute Task_2 first, then Task_1 final QA review.
  - Worker requirement: Codex thread/worktree worker, not multi-agent subagent; use `gpt-5.5` with medium reasoning for implementation-bearing or documentation-producing work.
  - Task_2 worker started: thread `019f4034-355b-7311-b785-f50d2e305760`; worktree `/Users/xpadev/.codex/worktrees/272b/calarm`; pending worktree `local:2a395fb2-d18c-471f-adf9-2ee3089f584d`; branch `codex/wave-14-ci-native-smoke-release`; requested model `gpt-5.5`; reasoning `medium`.
  - Task_2 owned paths: `docs/qa/ci-native-smoke.md`, `docs/qa/artifacts/**`, and Wave 14 ledger status only if needed.
  - Current status: Task_2 worker is active and gathering current `master` Baseline CI and Native Smoke CI evidence.

- 2026-07-06 Wave 3 decision integrated.
  - Final QA owns the later gate for deferred iOS 26+ and Android API 36 runtime validation.
  - Runtime-unapproved implementation evidence is not enough for release approval.

- 2026-07-06 CI near-device smoke task added.
  - Summary: Add final QA evidence requirements for Android Emulator / iOS Simulator smoke while preserving real-device runtime validation as release-blocking.
  - Decision impact: Wave 8 owns implementing the CI smoke harness earlier; Wave 14 reruns or summarizes it for release readiness.

- 2026-07-06 Baseline CI release evidence added.
  - Summary: Final QA now checks that ordinary format, analyzer/lint, and unit-test CI remains green or records a release-blocking failure.
  - Decision impact: Baseline CI is release hygiene evidence, distinct from native smoke and real-device runtime approval.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-06 Decision: Keep Wave 3 deferred runtime validation as final release gate.
  - Trigger / new insight: Wave 3 permits implementation from API-surface feasibility only.
  - Plan delta (what changed): Wave 14 final review must explicitly resolve all deferred runtime cases as pass before marking a platform APPROVED; waiver/platform-limited decisions are separate release paths and do not convert unresolved validation into approval.
  - Tradeoffs considered: Implementation momentum is preserved, but release confidence still depends on platform runtime evidence.
  - User approval: yes, from Wave 3 deferment.

- 2026-07-06 Decision: Add CI simulator/emulator smoke without relaxing release approval.
  - Trigger / new insight: User asked whether CI can run tests close to real-device validation while real-device validation remains deferred.
  - Plan delta (what changed): Wave 14 now includes Task_2 to rerun or summarize hosted CI Android Emulator / iOS Simulator smoke evidence with explicit NEAR_DEVICE/BLOCKED labels before final QA review.
  - Tradeoffs considered: CI smoke can catch build, install, platform-channel, and some scheduling/cancel regressions earlier, but hosted simulator/emulator behavior is not sufficient evidence for alarm wake reliability or OS policy behavior.
  - User approval: yes.

- 2026-07-06 Decision: Treat ordinary baseline CI as release hygiene evidence.
  - Trigger / new insight: User asked to add ordinary CI checks in addition to near-device CI.
  - Plan delta (what changed): Wave 14 final QA now checks baseline CI status for format, analyzer/lint, and unit tests without conflating it with native runtime approval.
  - Tradeoffs considered: This keeps normal regressions visible at release time while preserving real-device runtime checks as a separate alarm reliability gate.
  - User approval: yes.

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
