# Plan: Wake Alarm MVP Wave 5 - Time Foundation

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-05
- work_type: code

## Goal

- Wake Plan、Occurrence生成、週カレンダーが共有する時間計算の純粋ロジックを実装する。

## Definition of Done

- 分単位時刻、日付+分、週範囲、5分丸め、日跨ぎ計算がテスト済み。
- タイムゾーン依存処理が境界に閉じ込められ、domain/application層で再利用できる。

## Scope / Non-goals

- Scope:
  - `lib/core/time/**`
  - `test/core/time/**`
- Non-goals:
  - WakePlan domain model本体。
  - UI描画。

## Context (workspace)

- Related files/areas:
  - Wave 4 scaffold.
- Existing patterns or references:
  - `requirements.md` の日跨ぎ、過去分除外、5分丸め要件。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: DST境界をMVPでどこまでテストするか。
- Q2: 将来、週開始曜日をsettings化する必要が出た場合にどの層で吸収するか。
- Q3: DST境界でnearest丸めが存在しない/重複するローカル時刻をどう扱うか。

## Assumptions

- A1: 内部時刻は00:00からの分を基本表現にする。
- A2: UIタップ位置はnearest 5分に丸める。
- A3: 週開始曜日は日曜日に固定する。
- A4: 丸め後の起床目標日時が過去の場合は作成不可にする。
- A5: nearest 5分丸めでちょうど中間の場合は未来側へ丸める。

## Tasks

### Task_1: Time Value Objects and Date Math
- type: impl
- owns:
  - lib/core/time/**
  - test/core/time/**
- depends_on: []
- description: |
  Original Task_6. 日付、時刻、週範囲、分単位時刻、5分丸め、日跨ぎを扱う純粋ロジックを実装する。
- acceptance:
  - 00:00からの分、Date + minutes、weekStart、visibleRangeを扱える。
  - weekStartは日曜日開始で計算される。
  - タップ位置変換に使うnearest 5分丸めがテストされている。
  - nearest丸めでちょうど中間の場合は未来側へ丸める。
  - 丸め後の日時が過去かどうかを判定できる。
  - 日跨ぎの `targetAt - startOffset` が正しく計算される。
  - タイムゾーンに依存する処理が境界に閉じ込められている。
  - Wake Plan domainとweek calendarが同じtime helperを参照できる。
- validation:
  - kind: command
    required: true
    owner: worker
    detail: "flutter test test/core/time"
  - kind: review
    required: true
    owner: reviewer
    detail: "時間計算がWake Planドメインから再利用可能な粒度かレビューする"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]

## Rollback / Safety

- Pure Dart logicに限定し、nativeやUIには影響させない。

## Handoff To Next Wave

- Wave 6のWakePlan domainはこのtime foundationを利用する。
- Wave 8/9のcalendar interactionも同じ丸め・週範囲ロジックを利用する。

## Progress Log (append-only)

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Implement time math before domain models.
  - Trigger / new insight: Occurrence生成とカレンダーUIの両方が時間計算に依存する。
  - Plan delta (what changed): Time foundationを単独waveにした。
  - Tradeoffs considered: Domain実装前の抽象化になるが、重複計算を避けられる。
  - User approval: pending.

- 2026-07-05 Decision: Fix week start to Sunday for MVP.
  - Trigger / new insight: User specified Sunday as the start of the week.
  - Plan delta (what changed): Time foundation acceptance now requires Sunday-based weekStart.
  - Tradeoffs considered: Locale/settings-based week starts are deferred to a future settings enhancement.
  - User approval: yes.

- 2026-07-05 Decision: Use nearest 5-minute rounding for UI taps.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 5 now fixes tap rounding to nearest 5 minutes and requires past-target detection after rounding.
  - Tradeoffs considered: nearest rounding best matches user tap intent; rejecting rounded-past targets keeps scheduling semantics simple.
  - User approval: yes.

- 2026-07-05 Decision: Round exact nearest-midpoints forward.
  - Trigger / new insight: User requested applying the recommended values.
  - Plan delta (what changed): Wave 5 now requires exact 2m30s-style midpoint cases to round to the future 5-minute boundary.
  - Tradeoffs considered: Future rounding avoids creating a target earlier than an exactly-between user tap.
  - User approval: yes.

## Notes

- Edge cases:
  - 深夜目標時刻で前日に跨るwake window。
  - intervalで割り切れないwindow。
