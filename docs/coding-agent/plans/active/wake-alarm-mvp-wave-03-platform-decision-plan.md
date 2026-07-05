# Plan: Wake Alarm MVP Wave 3 - Platform Feasibility Decision

- status: complete
- generated: 2026-07-05
- last_updated: 2026-07-06
- work_type: design

## Goal

- Wave 2のスパイク結果を統合し、MVPで採用するnative alarm方式と後続計画の前提を確定する。

## Definition of Done

- iOS/Androidそれぞれの採用方式、権限方針、fallback方針が明記されている。
- ローリング予約を採用するか、OS繰り返しを使うかが決まっている。
- 後続子プランの前提に影響する変更がDecision Logへ記録されている。
- Runtime validation deferred statusが後続validation/release gateに残っている。

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
- A5: User approved deferring iOS 26+ and Android API 36 runtime validation; Wave 3 must decide under runtime-unapproved evidence and keep later validation/release gates explicit.
- A6: Wave 2 evidence is sufficient for API-surface implementation planning, but insufficient for runtime-approved release reliability.
- A7: Rolling concrete occurrence reservation is the MVP source of truth; OS recurrence is not used for next-skip, individual cancel, or plan cancel unless later evidence approves a safe optimization.
- A8: Android MVP implementation includes a native minimal stop UI and reboot restore path; iOS MVP implementation accepts AlarmKit presentation constraints but still records stop/dismiss and future occurrence state.

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
  - deferred runtime validationが後続waveとrelease gateで明示され、platform runtime approvalとして扱われていない。
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
- Wave 8/11/14は、iOS 26+ and Android API 36 runtime validationが未承認であることをQA checklistとrelease readinessに残す。
- 通常MVP release approvalは、各platformのrelease-blocking native runtime casesがpassするまでBLOCKEDにする。

## Progress Log (append-only)

- 2026-07-06 Task_1 completed.
  - Decision: continue MVP implementation planning under runtime-unapproved evidence.
  - Architecture: adopt rolling concrete native occurrence reservations; do not use OS recurrence as the MVP source of truth for repeating plans, next-skip, individual cancel, or plan cancel.
  - iOS adoption: AlarmKit bridge around UUID-backed concrete occurrences, authorization state handling, per-occurrence cancel, and plan cancel by iterating stored IDs.
  - Android adoption: AlarmManager with `setAlarmClock` as first candidate, distinct `PendingIntent` identities, permission/status checks, native minimal stop UI, and BootReceiver restore.
  - Permission policy: denied or unavailable alarm/notification/full-screen states are user-visible warning states and must not be reported as successful schedules.
  - Release gates: iOS/Android runtime reliability remains unapproved for wake delivery, lock/terminated behavior, permissions, stop UI, cancel semantics, 13-equivalent reservations, and Android reboot restore.

- 2026-07-06 Runtime validation deferment recorded for Wave 3.
  - User decision: iOS 26+ and Android API 36 runtime validation may be deferred.
  - Planning constraint: Wave 3 may proceed, but any platform decision must distinguish API-surface feasibility from runtime-approved alarm reliability.
  - Required output: downstream assumptions and release gates must retain the deferred validation risk.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-06 Decision: Adopt rolling concrete occurrence reservations for MVP implementation.
  - Trigger / new insight: Wave 2 local API evidence supports independent per-occurrence identities on both platforms, while OS recurrence does not prove next-skip or per-occurrence cancel semantics.
  - Plan delta (what changed): Later domain, gateway, native bridge, repeat/skip, and QA waves must treat one stored platform alarm identity per `AlarmOccurrence` as the implementation contract.
  - Tradeoffs considered: This increases scheduling/reconciliation work, but keeps Wake Plan semantics under app control and preserves skip/cancel correctness.
  - User approval: yes, through prior rolling reservation default and Wave 3 runtime-deferment decision.

- 2026-07-06 Decision: Adopt platform-specific implementation paths without runtime approval.
  - Trigger / new insight: iOS AlarmKit and Android AlarmManager evidence is API-surface feasible but runtime-blocked.
  - Plan delta (what changed): iOS implementation proceeds with AlarmKit concrete UUID alarms; Android implementation proceeds with `setAlarmClock`, native stop UI, permission/status checks, and BootReceiver restore. Release approval remains blocked until runtime validation passes.
  - Tradeoffs considered: This preserves implementation momentum while preventing documentation-only evidence from becoming a reliability claim.
  - User approval: yes.

- 2026-07-06 Decision: Proceed with Wave 3 under runtime-unapproved evidence.
  - Trigger / new insight: User approved deferring runtime validation after both Wave 2 platform spikes merged blocked evidence.
  - Plan delta (what changed): Wave 3 no longer waits for iOS 26+ or Android API 36 runtime evidence, but must not mark either platform runtime-approved.
  - Tradeoffs considered: This permits design and implementation planning to continue while preserving native alarm reliability as a later validation and release risk.
  - User approval: yes.

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
