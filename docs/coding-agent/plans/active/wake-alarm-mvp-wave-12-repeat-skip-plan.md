# Plan: Wake Alarm MVP Wave 12 - Repeating Plans and Skip Next

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-06
- work_type: code

## Goal

- 毎日、平日、土日、任意曜日の繰り返しWakePlanと、次回だけスキップ/解除をUI・service・予約ロジックへ接続する。

## Definition of Done

- 繰り返しWakePlanを作成・編集できる。
- 次回だけスキップすると次回分だけ予約対象から外れ、解除すると再予約対象になる。
- スキップ後もその次の対象日から通常通り鳴る。

## Scope / Non-goals

- Scope:
  - `lib/features/wake_plan/domain/**`
  - `lib/features/wake_plan/application/**`
  - `lib/features/wake_plan/ui/**`
  - `test/features/wake_plan/**`
- Non-goals:
  - 祝日スキップ、RRULE完全対応、隔週/月次繰り返し。

## Context (workspace)

- Related files/areas:
  - Wave 7 OccurrencePlanner.
  - Wave 11 edit/delete/health.
- Existing patterns or references:
  - `requirements.md` の7.7、7.8、12.6。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: スキップ済み表示はカレンダーブロック、詳細、一覧のどこに出すか。
- Q2: Native予約先読み期間外のskipを許可するか。
- Q3: target date基準のskipでtimezone/date変更が入った場合の扱い。

## Assumptions

- A1: MVPの繰り返しは毎日、平日、土日、任意曜日のみ。
- A2: 次回だけスキップは繰り返し設定を変更せず、次のWake Instanceだけを除外する。
- A3: `nextSkipDate`はtarget date基準にする。
- A4: Wave 3 decision uses rolling concrete occurrence reservations; OS recurrence is not the MVP source of truth for next-skip.

## Tasks

### Task_1: Repeating Plans and Skip Next UI
- type: impl
- owns:
  - lib/features/wake_plan/domain/**
  - lib/features/wake_plan/application/**
  - lib/features/wake_plan/ui/**
  - test/features/wake_plan/**
- depends_on: []
- description: |
  Original Task_19. 毎日、平日、土日、任意曜日と、次回だけスキップ/解除のUIとサービス接続を実装する。
- acceptance:
  - 繰り返し条件を作成・編集できる。
  - 次回だけスキップすると次回分だけ予約対象から外れる。
  - skip対象はtarget date基準の`nextSkipDate`で保存される。
  - スキップ解除で次回分が再び予約対象になる。
  - 一覧・詳細でスキップ済み状態が分かる。
  - スキップ後もその次の対象日から通常通り鳴る。
  - Native reservation changes are expressed by canceling/recreating concrete future occurrences, not by relying on unapproved OS recurrence exception behavior.
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/features/wake_plan"
  - kind: e2e
    required: true
    owner: reviewer
    detail: "E2E / Visual Validation Specの繰り返し・次回スキップフローを確認する"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]

## E2E / Visual Validation Spec

- provider: playwright-cli for Flutter web smoke where applicable; native manual evidence for schedule effects.
- artifact_root:
  - `.playwright-cli/`
  - `docs/qa/artifacts/`
- flows:
  - Create weekday WakePlan and verify next instance is visible.
  - Tap skip next and verify next instance is removed from reservation target.
  - Undo skip and verify next instance returns.
  - Verify following eligible day remains scheduled after skip.
- viewports:
  - Mobile compact: 390x844.
  - Mobile large: 430x932.
- evidence_requirements:
  - Screenshots of repeat picker, skip state, and schedule preview.

## Rollback / Safety

- Skip/undo must cancel/recreate only affected future occurrences.
- Do not implement broad "today all stop" from ringing UI.
- Do not introduce OS recurrence as the authoritative skip/cancel mechanism without a later Wave 3 replan or runtime evidence update.

## Handoff To Next Wave

- Wave 13 reviews all UI flows, including repeat and skip.
- Wave 14 includes repeat and skip in final QA matrix.

## Progress Log (append-only)

- 2026-07-06 Wave 3 decision integrated.
  - Repeat and skip implementation must use rolling concrete occurrence reservations as the authoritative schedule model.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-06 Decision: Model next-skip through concrete occurrences.
  - Trigger / new insight: Wave 3 found no runtime-approved OS recurrence exception semantics for MVP next-skip/cancel behavior.
  - Plan delta (what changed): Wave 12 must cancel/recreate concrete future occurrences for skip/undo behavior instead of relying on native recurrence exceptions.
  - Tradeoffs considered: Concrete occurrence management adds reconciliation work but keeps user-visible skip semantics deterministic.
  - User approval: yes, from Wave 3 rolling reservation decision.

- 2026-07-05 Decision: Keep repeating/skip after one-shot operational flow.
  - Trigger / new insight: 繰り返しはOccurrence生成・予約・編集削除が安定してから載せる方が安全。
  - Plan delta (what changed): Wave 12を単独feature waveにした。
  - Tradeoffs considered: MVP機能の一部が後ろ倒しになるが、基礎不具合の影響を減らせる。
  - User approval: pending.

- 2026-07-05 Decision: Key next-skip by target date.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 12 now requires `nextSkipDate` to be target-date based.
  - Tradeoffs considered: Target-date keying is simpler than generated WakeInstance ids and matches the user's "next occurrence day" mental model.
  - User approval: yes.

## Notes

- Risks:
  - Rolling concrete occurrence reconciliation must stay consistent with repeat/skip changes.
