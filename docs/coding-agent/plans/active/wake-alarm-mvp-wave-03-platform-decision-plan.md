# Plan: Wake Alarm MVP Wave 3 - Platform Feasibility Decision

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-05
- work_type: design

## Goal

- Wave 2のスパイク結果を統合し、MVPで採用するnative alarm方式と後続計画の前提を確定する。

## Definition of Done

- iOS/Androidそれぞれの採用方式、権限方針、fallback方針が明記されている。
- ローリング予約を採用するか、OS繰り返しを使うかが決まっている。
- 後続子プランの前提に影響する変更がDecision Logへ記録されている。

## Scope / Non-goals

- Scope:
  - `docs/spikes/native-alarm-feasibility.md`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-implementation-plan.md`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-wave-*.md`
- Non-goals:
  - 本実装コード作成。
  - 新しいplatform API調査のやり直し。

## Context (workspace)

- Related files/areas:
  - Wave 1 and Wave 2 child plans.
  - `docs/spikes/native-alarm-feasibility.md`
- Existing patterns or references:
  - 後続waveはこの決定を前提にdispatchする。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: スパイク未完了項目がある場合、MVPを縮小して続行するか。
- Q2: スパイク結果により3分間隔を詳細設定として解放するか。
- Q3: platform限定MVP判断が必要になった場合、対象platformと除外platformのユーザー向け説明をどう書くか。

## Assumptions

- A1: Wave 2で実機証跡が不足した項目は、APPROVEDではなく条件付きまたはBLOCKEDとして扱う。
- A2: ネイティブ予約は7日分のローリングOccurrence予約を基本方針にする。
- A3: Android native fallback UIと再起動後再予約はMVP必須にする。
- A4: iOS/Androidの片方のみAPPROVEDの場合は通常MVPへ進めず、platform限定MVPとして別途明示判断する。

## Tasks

### Task_1: Platform Feasibility Decision
- type: design
- owns:
  - docs/spikes/native-alarm-feasibility.md
  - docs/coding-agent/plans/active/wake-alarm-mvp-implementation-plan.md
  - docs/coding-agent/plans/active/wake-alarm-mvp-wave-*.md
- depends_on: []
- description: |
  Original Task_4. iOS/Androidスパイク結果を統合し、本実装方式とMVPスコープを確定する。
- acceptance:
  - iOS/Androidそれぞれの採用方式、権限方針、fallback方針が明記されている。
  - ローリング予約を採用するか、OS繰り返しを使うかが決まっている。
  - MVP継続可否と、必要なスコープ調整がDecision Logに記録されている。
  - 後続子プランのacceptanceやvalidationがplatform決定と矛盾していない。
- validation:
  - kind: review
    required: true
    owner: reviewer
    detail: "スパイク結論と後続waveの依存・acceptance・validationが矛盾していないかレビューする"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]

## Rollback / Safety

- platform決定が誤っていた場合は、このwaveのDecision Logをreplanし、影響する子プランだけを更新する。

## Handoff To Next Wave

- Wave 4以降のimplementationは、このwaveの採用方式をsource of truthにする。

## Progress Log (append-only)

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Add explicit plan consistency check after platform spikes.
  - Trigger / new insight: Native feasibilityの結果は後続のdomain、gateway、UI、QAに波及する。
  - Plan delta (what changed): Platform decisionを単独gateにした。
  - Tradeoffs considered: 実装開始前に一拍置くが、間違ったnative前提で進むリスクを下げる。
  - User approval: pending.

- 2026-07-05 Decision: Use rolling native reservations as the default architecture.
  - Trigger / new insight: User accepted the recommended decisions unless explicitly overridden.
  - Plan delta (what changed): Wave 3 now treats 7-day rolling reservations, Android fallback UI, and Android reboot rescheduling as default MVP requirements.
  - Tradeoffs considered: OS recurrence can still be used as an implementation detail only if it does not weaken skip/cancel semantics.
  - User approval: yes.

## Notes

- Risks:
  - AlarmKitやAndroid exact alarmの制約がMVP定義を縮小させる可能性がある。
