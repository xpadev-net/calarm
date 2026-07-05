# Plan: Wake Alarm MVP Wave 1 - Spike Evidence Template

- status: done
- generated: 2026-07-05
- last_updated: 2026-07-06
- work_type: docs

## Goal

- Native alarm feasibilityを検証する前に、実機条件、検証項目、記録フォーマット、合否基準を固定する。

## Definition of Done

- iOS/Androidそれぞれの対象OS、端末、権限状態、検証ケースを記録できる。
- 1分後、短間隔3件、5分間隔13件相当、cancel、ロック中、アプリ終了中、権限拒否を記録できる。
- 失敗時に設計を見直す判断基準が明記されている。

## Scope / Non-goals

- Scope:
  - `docs/spikes/native-alarm-feasibility.md`
  - `docs/qa/artifacts/.gitkeep`
- Non-goals:
  - iOS/Android実装コード作成。
  - スパイク実施そのもの。

## Context (workspace)

- Related files/areas:
  - `requirements.md`
  - `implement-plan-draft.md`
- Existing patterns or references:
  - まだスパイク文書とQA artifact directoryは存在しない前提。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`

## Open Questions (max 3)

- Q1: スパイクで使う実機のOSバージョンと端末名は何にするか。
- Q2: 13件相当の検証を実時間65分で行うか、短縮間隔で代替するか。
- Q3: Focus/サイレント/省電力の全組み合わせをMVP前に必須にするか。

## Assumptions

- A1: iOSはiOS 26以上、AndroidはAPI 36以上を対象にする。
- A2: 実機検証できない項目はBLOCKEDとして明示し、Simulator/EmulatorだけでAPPROVEDにしない。

## Tasks

### Task_1: Native Alarm Spike Evidence Template
- type: docs
- owns:
  - docs/spikes/native-alarm-feasibility.md
  - docs/qa/artifacts/.gitkeep
- depends_on: []
- description: |
  Original Task_1. Native alarm feasibility検証の入力条件、手順、期待結果、実測結果、判定、follow-upを記録するテンプレートを作る。
- acceptance:
  - iOS/Android別に端末、OS、build、権限、通知設定、ロック状態、アプリ状態を記録できる。
  - 検証ケースごとに手順、期待結果、実結果、pass/fail、証跡パスを記録できる。
  - 1分後、短間隔3件、5分間隔13件相当、個別cancel、plan cancel、ロック中、アプリ終了中、権限拒否が含まれる。
  - 失敗時の設計見直し観点としてローリング予約、OS繰り返し、不採用機能、MVP延期条件がある。
- validation:
  - kind: review
    required: true
    owner: orchestrator
    detail: "docs/spikes/native-alarm-feasibility.mdに検証ケース、合否基準、artifact記録欄が揃っているか確認する"

## Task Waves (explicit parallel dispatch sets)

- Wave 1 (parallel): [Task_1]

## Rollback / Safety

- 文書と`.gitkeep`のみの変更なので、問題があればこのwaveで追加したdocsファイルを戻す。

## Handoff To Next Wave

- Wave 2はこのテンプレートを唯一のスパイク記録先として使う。
- Wave 2開始前に、未検証項目が「未記録」ではなく「pending」として表現できることを確認する。

## Progress Log (append-only)

- 2026-07-06 Task_1 delegated to Worker.
  - Worker branch: `codex/wave-01-spike-evidence-template`.
  - Worker state: pendingWorktreeId `local:0e4f82c0-42d9-4b75-8069-cad1fe412deb`.
  - Scope: `docs/spikes/native-alarm-feasibility.md`, `docs/qa/artifacts/.gitkeep`.
  - Validation evidence: pending Worker docs review, `rtk git diff --check`, independent review, `gh-review-hook`, and orchestrator-owned review before merge.

- 2026-07-06 Task_1 completed and merged.
  - PR: #1 https://github.com/xpadev-net/calarm/pull/1
  - Branch head: `144bdeb38ebdebd437e91b8e1c11996606c87c16`.
  - Merge commit: `79ac0480c15a577edb7c2f38268686b7fdb393b6`.
  - Changed files: `docs/spikes/native-alarm-feasibility.md`, `docs/qa/artifacts/.gitkeep`.
  - Worker validation evidence: acceptance inspection passed; `rtk git diff --check` passed; no markdown/docs lint target was present.
  - Review evidence: independent Worker reviewer approved twice; `gh-review-hook 1` exited 0 after the Worker fixed missing iOS Silent/Focus and Android reboot-restore coverage; GitHub checks passed.
  - Orchestrator validation evidence: PR diff and final template were inspected against the Wave 1 acceptance criteria; all required recording fields, cases, `pending` placeholders, failure decision points, and release-readiness criteria were present.

- 2026-07-05 Draft created.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Put evidence template before platform spikes.
  - Trigger / new insight: 実機スパイクは再現条件が重要で、後から形式を揃えると証跡が欠けやすい。
  - Plan delta (what changed): Wave 1をdocs-onlyの準備waveにした。
  - Tradeoffs considered: 実装開始は遅れるが、Wave 2の判断品質が上がる。
  - User approval: pending.

## Notes

- Risks:
  - 実機やOS条件が揃わずWave 2がBLOCKEDになる可能性がある。
