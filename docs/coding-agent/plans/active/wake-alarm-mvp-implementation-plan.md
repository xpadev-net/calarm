# Plan: Wake Alarm MVP Implementation - Plan Index

- status: draft
- generated: 2026-07-05
- last_updated: 2026-07-05
- work_type: mixed

## Goal

- `requirements.md` と `implement-plan-draft.md` をもとに、逆算型・段階起床アラームアプリのMVPを段階実装する。
- 親プランは全体統制と依存関係の目次に限定し、実行可能な詳細計画は wave 単位の子プランへ分割する。
- 最小縦切りは「週カレンダーで起床目標を選ぶ → 逆算Wake Planを作る → 複数アラームが鳴る → 1回止めても次が鳴る」。

## Definition of Done

- 子プラン Wave 1-14 がすべて `done`、または明示的に waived されている。
- Wake Planを一回限り、曜日繰り返し、次回だけスキップ付きで作成・編集・削除できる。
- Wake Planから生成されるAlarm Occurrenceは開始時刻と起床目標時刻を含み、過去分、日跨ぎ、割り切れない間隔を正しく扱う。
- 鳴動中の主操作は「今のアラームを止める」のみで、「起きた」「残り全部停止」「スヌーズ」は表示しない。
- iOS 26以上ではAlarmKit、Android API 36ではAlarmManager系APIとfull-screen notificationで、実機上の予約・発火・停止・cancel・再予約が検証済み。
- 編集・削除・スキップ時に古いネイティブ予約や重複Occurrenceが残らない。
- 権限不足、予約失敗、OS設定上の問題をユーザーに明示でき、テストアラームを実行できる。

## Scope / Non-goals

- Scope:
  - Flutterプロジェクト雛形、ドメインモデル、Occurrence生成ロジック、永続化、週カレンダーUI。
  - NativeAlarmGateway、iOS AlarmKit Bridge、Android Alarm Bridge。
  - 一回限り、曜日繰り返し、次回だけスキップ、編集、削除、テストアラーム、権限チェック。
  - 実機スパイク、E2E/Visual確認、MVP QAログ。
- Non-goals:
  - 外部カレンダー連携、予定解析、AI提案、祝日スキップ、RRULE完全対応。
  - 睡眠トラッキング、ミッション解除、ウィジェット、独自ロック画面拡張。
  - 鳴動画面での「起きた」ボタン、残りアラーム一括停止、スヌーズ。

## Context (workspace)

- Related files/areas:
  - `requirements.md`
  - `implement-plan-draft.md`
  - `docs/coding-agent/plans/active/wake-alarm-mvp-wave-*.md`
- Existing patterns or references:
  - 現時点でFlutter/iOS/Androidの実装ファイルは未作成。
  - `docs/coding-agent/rules/` は未作成のため、リポジトリ固有ルールは未適用。
- Repo reference docs consulted:
  - `requirements.md`
  - `implement-plan-draft.md`
- Research waived:
  - この更新は既存要件・既存ドラフト・既存計画の文書分割であり、リポジトリ実装探索は不要。

## Open Questions (max 3)

- Q1: スパイク後に、3分間隔を詳細設定として解放するか。
- Q2: platform限定MVP判断が必要になった場合、対象platformと除外platformの説明をどう書くか。
- Q3: 実機調達やOS beta availabilityによりnative validationが遅れる場合の実施日程。

## Assumptions

- A1: iOSはiOS 26以上、AndroidはAPI 36以上をMVP対象にする。
- A2: アプリ本体はFlutterで作り、ネイティブ層はPlatform Channelで接続する。必要になった時点でPigeon化を検討する。
- A3: MVPでは5分間隔を標準かつ最小値とし、3分間隔はスパイク後の拡張候補にする。
- A4: 同時刻に複数Wake Planが重なることはMVPでは禁止せず、作成・編集時に警告する。
- A5: 繰り返しWake Planは無限にOccurrenceをDB化せず、表示範囲と7日分のネイティブ予約範囲に応じて生成する。
- A6: 週カレンダーの週開始曜日は日曜日に固定する。
- A7: タップ位置から定まる起床目標日時が過去の場合は作成不可にする。
- A8: Native alarm実機未検証はAPPROVEDにしない。Simulator/Emulatorのみの結果はBLOCKEDまたは条件付き扱いにする。
- A9: AndroidはFlutter起動失敗時でも停止できるnative fallback UIと、再起動後再予約をMVP必須にする。
- A10: テストアラームは1分後を標準にする。
- A11: MVP UI文言は日本語固定で開始する。
- A12: 発火、cancel、未来Occurrence維持、権限警告のいずれかがBLOCKEDならMVPリリース停止とする。
- A13: Flutter状態管理はRiverpodを採用する。
- A14: Flutter側のローカル永続化はDriftを採用する。
- A15: MVP scaffoldのapplication id/package nameは`dev.xpa.calarm`に固定する。
- A16: MethodChannel schemaは`docs/platform/native-alarm-channel.md`とcontract testsの両方で固定する。
- A17: QA artifact命名規約は`docs/qa/artifacts/<wave>-<platform>-<flow>-<YYYYMMDD-HHMM>.<ext>`に固定する。
- A18: エラー表示はinline warningを基本とし、操作結果の短い通知はsnackbar、破壊的確認だけdialogを使う。
- A19: Flutter SDK固定は`.fvmrc`で行う。
- A20: アプリ表示名は`Calarm`に固定する。
- A21: UIタップ位置の5分丸めはnearest 5分とし、丸め後の起床目標日時が過去なら作成不可にする。
- A22: 週カレンダー初期スクロールは、今日を含む週なら現在時刻付近、それ以外の週なら05:00にする。
- A23: 作成Sheetは基本項目を表示し、音/バイブなどの詳細設定は折りたたみにする。
- A24: 重複時間帯はinline warningを常時表示し、保存時の追加dialogは出さない。
- A25: Drift migrationはMVP中もschemaVersionを上げて同一PR/taskでmigrationを書く。破壊的resetはdev/debug限定にする。
- A26: MethodChannel payloadには`schemaVersion: 1`を含める。
- A27: QA artifactsはMVP中すべて保持し、MVP後の整理は別判断にする。
- A28: iOS/Androidの片方のみAPPROVEDの場合は通常MVPへ進めず、platform限定MVPとして別途明示判断する。
- A29: Drift/Riverpod関連packageはWave 4 scaffoldで追加する。
- A30: `.fvmrc`には実装時点のローカル`flutter --version`のstable versionを固定する。
- A31: nearest 5分丸めでちょうど中間の場合は未来側へ丸める。
- A32: 編集時のDB更新順序は`pendingChange`保存 → old cancel → new schedule → committed/failedとする。
- A33: `nextSkipDate`はtarget date基準にする。
- A34: MVPのアラーム音はOS/defaultのみとし、独自音源はMVP外にする。

## Child Plans

- Wave 1: [Spike Plan and Evidence Template](wake-alarm-mvp-wave-01-spike-evidence-plan.md)
- Wave 2: [Native Alarm Feasibility Spikes](wake-alarm-mvp-wave-02-native-feasibility-spikes-plan.md)
- Wave 3: [Platform Feasibility Decision](wake-alarm-mvp-wave-03-platform-decision-plan.md)
- Wave 4: [Flutter Project Scaffold](wake-alarm-mvp-wave-04-flutter-scaffold-plan.md)
- Wave 5: [Time Foundation](wake-alarm-mvp-wave-05-time-foundation-plan.md)
- Wave 6: [Domain and Gateway Contracts](wake-alarm-mvp-wave-06-domain-gateway-contracts-plan.md)
- Wave 7: [Planner, Repository, and MethodChannel Wiring](wake-alarm-mvp-wave-07-planner-repository-channel-plan.md)
- Wave 8: [Scheduling, Native Bridges, and Calendar Core](wake-alarm-mvp-wave-08-scheduling-native-calendar-plan.md)
- Wave 9: [Calendar Rendering and Settings Defaults](wake-alarm-mvp-wave-09-rendering-settings-plan.md)
- Wave 10: [Create Wake Plan Flow](wake-alarm-mvp-wave-10-create-flow-plan.md)
- Wave 11: [Edit, Ringing, and Health Checks](wake-alarm-mvp-wave-11-edit-ringing-health-plan.md)
- Wave 12: [Repeating Plans and Skip Next](wake-alarm-mvp-wave-12-repeat-skip-plan.md)
- Wave 13: [UI Harmonization and Accessibility](wake-alarm-mvp-wave-13-ui-harmonization-plan.md)
- Wave 14: [MVP End-to-End QA and Release Readiness](wake-alarm-mvp-wave-14-mvp-qa-release-plan.md)

## Tasks

### Task_1: Execute Child Plans In Wave Order
- type: chore
- owns:
  - docs/coding-agent/plans/active/wake-alarm-mvp-implementation-plan.md
  - docs/coding-agent/plans/active/wake-alarm-mvp-wave-*.md
- depends_on: []
- description: |
  Parent coordination task. Execute the linked child plans in wave order, update each child plan's Progress Log and Decision Log, and keep this parent index current when replans affect cross-wave dependencies.
- acceptance:
  - Each child plan is executed, waived, or marked blocked with evidence.
  - Cross-wave dependency changes are recorded in this parent Decision Log.
  - Parent Definition of Done is checked only after Wave 14 has reviewer-owned final evidence.
- validation:
  - kind: review
    required: true
    owner: orchestrator
    detail: "Confirm every child plan has current status, Progress Log, Decision Log, and required validation evidence before marking the parent done"

## Task Waves (explicit parallel dispatch sets)

Interpretation:
- Tasks listed in the same wave are represented by one child plan.
- Child plans execute sequentially unless the parent Decision Log records a replan.
- Parallelism inside each child plan is defined in that child plan's Task Waves section.

- Wave 1 (parallel): [wake-alarm-mvp-wave-01-spike-evidence-plan.md]
- Wave 2 (parallel): [wake-alarm-mvp-wave-02-native-feasibility-spikes-plan.md]
- Wave 3 (parallel): [wake-alarm-mvp-wave-03-platform-decision-plan.md]
- Wave 4 (parallel): [wake-alarm-mvp-wave-04-flutter-scaffold-plan.md]
- Wave 5 (parallel): [wake-alarm-mvp-wave-05-time-foundation-plan.md]
- Wave 6 (parallel): [wake-alarm-mvp-wave-06-domain-gateway-contracts-plan.md]
- Wave 7 (parallel): [wake-alarm-mvp-wave-07-planner-repository-channel-plan.md]
- Wave 8 (parallel): [wake-alarm-mvp-wave-08-scheduling-native-calendar-plan.md]
- Wave 9 (parallel): [wake-alarm-mvp-wave-09-rendering-settings-plan.md]
- Wave 10 (parallel): [wake-alarm-mvp-wave-10-create-flow-plan.md]
- Wave 11 (parallel): [wake-alarm-mvp-wave-11-edit-ringing-health-plan.md]
- Wave 12 (parallel): [wake-alarm-mvp-wave-12-repeat-skip-plan.md]
- Wave 13 (parallel): [wake-alarm-mvp-wave-13-ui-harmonization-plan.md]
- Wave 14 (parallel): [wake-alarm-mvp-wave-14-mvp-qa-release-plan.md]

## Rollback / Safety

- 子プラン実行前は、この親プランと子プランファイルを戻せば文書分割だけを取り消せる。
- 実装着手後のrollbackは各子プランの `Rollback / Safety` を優先する。
- Native alarm実装を戻す場合は、既知の `platformAlarmId` をcancelしてからMethodChannel登録を外す。

## Progress Log (append-only)

- 2026-07-05 Draft split: Wave 1-14 child plans created.
  - Summary: 元の24タスク計画を wave 単位の14個の独立プランへ分割し、親プランを目次と全体統制に変更した。
  - Validation evidence: 各子プランがGoal、Definition of Done、Task_X、Task Waves、validation、handoff、logsを持つ。
  - Notes: repo-specific rule suite was absent; validation was selected from project documents and general Flutter/native app expectations.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-05 Decision: Lock MVP defaults and product constraints before implementation.
  - Trigger / new insight: User confirmed the recommended direction and specified Sunday week start plus rejecting past target taps.
  - Plan delta (what changed): Parent assumptions now fix 5-minute minimum interval, rolling 7-day native reservations, Sunday week start, past target rejection, real-device validation requirements, Android fallback/reboot requirements, 1-minute test alarm, Japanese MVP copy, and release-blocking criteria.
  - Tradeoffs considered: These defaults reduce implementation ambiguity while keeping platform-limited MVP and 3-minute interval as explicit post-spike decisions.
  - User approval: yes.

- 2026-07-05 Decision: Lock implementation defaults that affect scaffolding and data boundaries.
  - Trigger / new insight: User requested applying the recommended values for remaining implementation decisions.
  - Plan delta (what changed): Parent assumptions now fix Riverpod, Drift, `dev.xpa.calarm`, MethodChannel schema documentation, QA artifact naming, and error-display policy.
  - Tradeoffs considered: These are implementation defaults that can be changed later through explicit replan, but fixing them now prevents early scaffold/repository churn.
  - User approval: yes.

- 2026-07-05 Decision: Lock remaining pre-implementation defaults.
  - Trigger / new insight: User requested applying the recommended values for remaining planning decisions.
  - Plan delta (what changed): Parent assumptions now fix `.fvmrc`, `Calarm`, nearest 5-minute rounding, week calendar initial scroll, collapsed advanced create settings, inline-only overlap warning, Drift migration discipline, MethodChannel `schemaVersion: 1`, QA retention, and platform-limited MVP handling.
  - Tradeoffs considered: These decisions can still be changed through replan, but fixing them now keeps scaffold, UI, persistence, and native contract work aligned.
  - User approval: yes.

- 2026-07-05 Decision: Lock final implementation-detail defaults before coding.
  - Trigger / new insight: User requested applying the recommended values for the remaining minor implementation decisions.
  - Plan delta (what changed): Parent assumptions now fix package-add timing, `.fvmrc` version source, midpoint rounding, edit DB state order, target-date skip keying, and default-only alarm sound.
  - Tradeoffs considered: These choices keep early implementation deterministic while leaving native/API-specific behavior to the planned spikes.
  - User approval: yes.

- 2026-07-05 Decision: Split by wave, not individual task.
  - Trigger / new insight: 既存計画は24タスクまで分解済みで、Task単位にすると共通コンテキストとQA仕様の重複が大きい。
  - Plan delta (what changed): 親プランをindex化し、14 waveをそれぞれ実行計画ファイルとして作成した。
  - Tradeoffs considered: Task単位はより細かいが、実行時の依存関係とレビューゲートが散らばる。Wave単位は並列実行境界を保ちつつ詳細化しやすい。
  - User approval: requested by user as plan split/detailing.

## Notes

- Risks:
  - AlarmKit/Android exact alarm limits may force a rolling reservation model instead of long-lived repeated native alarms.
  - Simulators may not represent lock screen, Focus, power, and notification behavior accurately enough;実機 validation is required.
  - Flutter project scaffold may reveal package, state management, persistence, or build constraints that require replanning.
- Edge cases:
  - 起床目標が深夜で、起床ウィンドウが前日に跨るケース。
  - startOffsetがintervalで割り切れず、最後だけ短い間隔になるケース。
  - 作成時点で既に起床ウィンドウ途中にいるケース。
  - 権限変更、再起動、アプリ再インストール後にnative予約とDB状態がずれるケース。
