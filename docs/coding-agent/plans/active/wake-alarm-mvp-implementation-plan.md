# Plan: Wake Alarm MVP Implementation - Plan Index

- status: in progress
- generated: 2026-07-05
- last_updated: 2026-07-07
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
- iOS 26以上ではAlarmKit、Android API 36ではAlarmManager系APIとfull-screen notificationで実装する。Wave 3でdeferされた実機上の予約・発火・停止・cancel・再予約 validation はrelease approval前に解決されている。
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
- A35: Wave 3 decision adopts rolling concrete native occurrence reservations for implementation planning, not OS recurrence as the MVP source of truth.
- A36: Wave 3 decision approves continuing implementation from API-surface feasibility only; iOS 26+ and Android API 36 runtime reliability remain unapproved.
- A37: iOS release approval still requires runtime evidence for wake delivery, lock/terminated behavior, authorization denial, Silent/Focus behavior, stop/dismiss, individual cancel, plan cancel, and 13-equivalent reservations.
- A38: Android release approval still requires runtime evidence for `setAlarmClock` delivery, lock/terminated behavior, exact alarm and notification denial, full-screen stop UI, stop/dismiss, individual cancel, plan cancel, 13-equivalent reservations, and reboot restore.
- A39: Android implementation must include a native minimal stop UI and BootReceiver restore path; Flutter startup from a terminated state is not the sole stop mechanism.
- A40: Any platform-limited MVP requires a later explicit product/release decision; Wave 3 does not approve one.
- A41: Parent Definition of Done permits implementation progress under Wave 3 deferment, but normal release approval remains BLOCKED until deferred iOS/Android runtime validation is resolved as pass evidence.
- A42: CI simulator/emulator smoke should be implemented as soon as native bridge code exists, but its results are NEAR_DEVICE or BLOCKED evidence and do not replace real-device runtime validation for release approval.
- A43: Ordinary GitHub Actions baseline CI for format, analyzer/lint, and unit tests should be added before native smoke CI, then kept intact through later workflow additions.

## Child Plans

- Wave 1: [Spike Plan and Evidence Template](../completed/wake-alarm-mvp-wave-01-spike-evidence-plan.md)
- Wave 2: [Native Alarm Feasibility Spikes](../completed/wake-alarm-mvp-wave-02-native-feasibility-spikes-plan.md)
- Wave 3: [Platform Feasibility Decision](../completed/wake-alarm-mvp-wave-03-platform-decision-plan.md)
- Wave 4: [Flutter Project Scaffold](../completed/wake-alarm-mvp-wave-04-flutter-scaffold-plan.md)
- Wave 5: [Time Foundation](../completed/wake-alarm-mvp-wave-05-time-foundation-plan.md)
- Wave 6: [Domain and Gateway Contracts](../completed/wake-alarm-mvp-wave-06-domain-gateway-contracts-plan.md)
- Wave 7: [Planner, Repository, and MethodChannel Wiring](../completed/wake-alarm-mvp-wave-07-planner-repository-channel-plan.md)
- Wave 8: [Scheduling, Native Bridges, and Calendar Core](../completed/wake-alarm-mvp-wave-08-scheduling-native-calendar-plan.md)
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

- Wave 1 (parallel): [../completed/wake-alarm-mvp-wave-01-spike-evidence-plan.md]
- Wave 2 (parallel): [../completed/wake-alarm-mvp-wave-02-native-feasibility-spikes-plan.md]
- Wave 3 (parallel): [../completed/wake-alarm-mvp-wave-03-platform-decision-plan.md]
- Wave 4 (parallel): [../completed/wake-alarm-mvp-wave-04-flutter-scaffold-plan.md]
- Wave 5 (parallel): [../completed/wake-alarm-mvp-wave-05-time-foundation-plan.md]
- Wave 6 (parallel): [../completed/wake-alarm-mvp-wave-06-domain-gateway-contracts-plan.md]
- Wave 7 (parallel): [../completed/wake-alarm-mvp-wave-07-planner-repository-channel-plan.md]
- Wave 8 (parallel): [../completed/wake-alarm-mvp-wave-08-scheduling-native-calendar-plan.md]
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

- 2026-07-07 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness manually merged by user.
  - Summary: PR #17 `Add native smoke CI harness` was merged by the user at head `836bc62dbc17a26f5e96bd6f36de9b0066c3db43` with merge commit `3ca67898e7f8700d2138ca5775ffe1de62933744`.
  - Validation evidence: GitHub `Format, analyze, and test`, `Android emulator native smoke`, `iOS simulator native smoke`, Greptile Review, Socket Project Report, and Socket Pull Request Alerts were successful; worker evidence on the same head reported workflow YAML parse, extracted workflow bash syntax, mutable action/cache scan, `rtk git diff --check`, `rtk flutter analyze`, and `rtk flutter test` passed.
  - Merge-gate note: CodeRabbit remained `PENDING`, so worker `rtk gh-review-hook 17` could not exit 0; this was accepted by explicit user decision rather than orchestrator-owned full merge gate completion.
  - Runtime status: CI simulator/emulator evidence remains NEAR_DEVICE/BLOCKED only and does not approve deferred iOS 26+/Android API 36 real-device release gates.
  - Next action: proceed to Wave 8 Task_6 whole-codebase closeout review/fix loop on `master`.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness waiting on CodeRabbit.
  - Summary: PR #17 `Add native smoke CI harness` is at head `836bc62dbc17a26f5e96bd6f36de9b0066c3db43`; worker validation and GitHub Baseline CI/Native Smoke CI/Greptile/Socket evidence passed, but worker `rtk gh-review-hook 17` timed out because CodeRabbit remains pending.
  - Orchestrator state: PR #17 is open/non-draft with merge state `UNSTABLE`; no merge is permitted until CodeRabbit completes and worker-side final `rtk gh-review-hook 17` exits 0 on the final reviewed head.
  - Merge gate impact: PR #17 remains unmerged; Task_6 whole-codebase review must wait until Task_5 merges.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness returned after Android boot-timeout review.
  - Summary: PR #17 `Add native smoke CI harness` returned at head `738e96f1981879a04c0648ae1aa3027cb0273dba`, with worker validation, GitHub checks, final run-log scan, and worker `rtk gh-review-hook 17` passing after Android setup timeout handling.
  - Orchestrator validation: clean PR-head temp worktree confirmed expected PR files, workflow YAML parse, extracted bash syntax, mutable action/cache scan, final GitHub run-log scan, and `rtk git diff --check`; GitHub PR state was non-draft, `CLEAN`, with seven successful checks.
  - Review outcome: orchestrator/reviewer final review found one merge-blocking issue: Android emulator boot timeout paths (`adb wait-for-device` and boot-completion polling) write BLOCKED hosted-runner evidence but can exit successfully, allowing CI to go green after a hosted-runner timeout.
  - Action: worker thread `019f360f-e59c-7440-8c24-9ff9904c1e9d` was asked to make Android boot-timeout paths fail nonzero after writing BLOCKED evidence, preserve artifact upload behavior, then rerun validation, GitHub checks, and final worker `rtk gh-review-hook 17`.
  - Merge gate impact: PR #17 remains unmerged; Task_6 whole-codebase review must wait until Task_5 merges.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness returned after Android setup timeout review.
  - Summary: PR #17 `Add native smoke CI harness` returned at head `b88b4ff7d49b444499152445a9797b6f678c1f06`, with worker validation, GitHub checks, final run-log scan, and worker `rtk gh-review-hook 17` passing after Android build/test timeout handling.
  - Orchestrator validation: clean PR-head temp worktree passed workflow YAML parse, extracted bash syntax, mutable action/cache scan, final GitHub run-log scan, `rtk flutter pub get`, `rtk dart format --set-exit-if-changed .`, `rtk flutter analyze`, `rtk flutter test`, `rtk git diff --check`, and orchestrator `rtk gh-review-hook 17`.
  - Review outcome: orchestrator/reviewer final review found one merge-blocking issue: Android hosted setup commands (`sdkmanager --list`, license acceptance, package install, and `avdmanager create avd`) remain unbounded, so a setup hang can still prevent the `if: always()` artifact upload step from running.
  - Action: worker thread `019f360f-e59c-7440-8c24-9ff9904c1e9d` was asked to add process-level timeout handling around Android setup commands, write BLOCKED hosted-runner evidence on timeout, preserve artifact upload behavior, then rerun validation, GitHub checks, run-log scan, and final worker `rtk gh-review-hook 17`.
  - Merge gate impact: PR #17 remains unmerged; Task_6 whole-codebase review must wait until Task_5 merges.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness returned after Android timeout review.
  - Summary: PR #17 `Add native smoke CI harness` returned at head `7d5f074a62a5a30d068453251015235bd3585222`, with worker validation, GitHub checks, final run-log scan, and worker `rtk gh-review-hook 17` passing.
  - Orchestrator validation: clean PR-head temp worktree passed workflow YAML parse, extracted bash syntax, mutable action/cache scan, Flutter tag check, `rtk flutter pub get`, `rtk dart format --set-exit-if-changed .`, `rtk flutter analyze`, `rtk flutter test`, `rtk git diff --check`, final GitHub run-log scan, and orchestrator `rtk gh-review-hook 17`.
  - Review outcome: orchestrator/reviewer final review found one merge-blocking issue: Android native smoke has only a job-level timeout, so a hung `flutter build apk --debug` or Android `flutter test ... -d emulator-5554` can prevent the `if: always()` artifact upload step from running.
  - Action: worker thread `019f360f-e59c-7440-8c24-9ff9904c1e9d` was asked to add process-level Android build/test timeout handling that writes BLOCKED hosted-runner evidence before failing, then rerun validation, GitHub checks, run-log scan, and final worker `rtk gh-review-hook 17`.
  - Merge gate impact: PR #17 remains unmerged; Task_6 whole-codebase review must wait until Task_5 merges.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness continued after final hook evidence scan.
  - Summary: PR #17 reached worker `rtk gh-review-hook 17` exit 0 at head `2c71c39019f04b45446bb54cd4d71617b0d15481`, but worker log verification still found nested mutable `actions/cache@v5` usage through `subosito/flutter-action`.
  - Action: worker is replacing `subosito/flutter-action` with shell-based Flutter SDK setup pinned by `.fvmrc`, then must rerun validation, GitHub checks, and final worker `rtk gh-review-hook 17`.
  - Merge gate impact: PR #17 remains unmerged; orchestrator review/checks/hook must be rerun after the next final head.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness returned after final-head orchestrator review.
  - Summary: PR #17 `Add native smoke CI harness` returned at head `f419abaf7c44d42cda6975eca2802d0788526b88`, with worker validation, GitHub checks, and worker `rtk gh-review-hook 17` passing.
  - Orchestrator validation: clean PR-head temp worktree passed `rtk flutter pub get`, `rtk flutter analyze`, `rtk flutter test`, `rtk git diff --check`, `rtk dart format --set-exit-if-changed .`, workflow YAML parse, extracted bash syntax, mutable action scan, and `rtk gh-review-hook 17`.
  - Review outcome: orchestrator/reviewer final review found one merge-blocking issue: `subosito/flutter-action` is SHA-pinned, but `cache: true` causes its composite action to execute mutable `actions/cache@v5` internally at runtime in Baseline CI and Native Smoke CI.
  - Action: worker thread `019f360f-e59c-7440-8c24-9ff9904c1e9d` was asked to fix PR #17 and provide refreshed validation and hook evidence before merge.
  - Runtime status: CI simulator/emulator evidence remains NEAR_DEVICE/BLOCKED only and does not approve deferred real-device runtime release gates.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness returned after orchestrator review.
  - Summary: PR #17 `Add native smoke CI harness` reached merge-ready at head `304ad085e2390126bdca873f6caefbdc56d61508`, with worker validation, GitHub checks, and worker `rtk gh-review-hook 17` passing.
  - Orchestrator validation: clean PR-head temp worktree passed `rtk flutter pub get`, `rtk flutter analyze`, `rtk flutter test`, `rtk git diff --check`, workflow YAML parse, extracted bash syntax, mutable action scan, and `rtk gh-review-hook 17`.
  - Review outcome: orchestrator/reviewer final review found two merge-blocking issues: `NEAR_DEVICE` could be reported when iOS native schedule/test-alarm operations only failed with permission/unavailable paths, and Native Smoke CI path filters omitted `.fvmrc`, `pubspec.yaml`, and `pubspec.lock`.
  - Action: worker thread `019f360f-e59c-7440-8c24-9ff9904c1e9d` was asked to fix PR #17 and provide refreshed validation and hook evidence before merge.
  - Runtime status: CI simulator/emulator evidence remains NEAR_DEVICE/BLOCKED only and does not approve deferred real-device runtime release gates.

- 2026-07-06 Worker-side post-review gh-review-hook requirement clarified.
  - Summary: Worker merge-ready evidence must include `rtk gh-review-hook <PR_NUMBER>` run from the worker worktree after worker self-review, independent review, and any review-driven fixes are complete.
  - Merge gate impact: Orchestrator must verify hook evidence points at the final reviewed head SHA before merging.

- 2026-07-06 Baseline CI Node.js 20 deprecation warning added to Wave 8 Task_5.
  - Summary: The `Format, analyze, and test` workflow currently warns that `actions/upload-artifact@v4` targets Node.js 20 and is being forced to Node.js 24.
  - Action: Wave 8 Task_5 now includes fixing or precisely documenting this warning within `.github/workflows/**`, while preserving baseline CI artifact upload behavior.
  - Validation impact: Task_5 must verify the supported action/runtime path and show the warning is gone, or report a concrete upstream/action-version blocker.

- 2026-07-06 Wave 8 Task_5 CI Simulator/Emulator Native Smoke Harness delegated.
  - Summary: Task_5 was started after Task_1-Task_4 merged, with branch `codex/wave-08-ci-native-smoke` and pending worktree `local:d74c6506-5d51-4135-936d-0efe755d9012`.
  - Scope: Worker owns `.github/workflows/**`, `integration_test/**`, `test_driver/**`, `docs/qa/ci-native-smoke.md`, and `docs/qa/artifacts/**`; baseline CI must remain intact.
  - Runtime status: Simulator/emulator evidence must be labeled NEAR_DEVICE or BLOCKED and cannot approve deferred iOS 26+/Android API 36 real-device runtime validation.

- 2026-07-06 Wave 8 Task_3 Android Alarm Bridge merged.
  - Summary: PR #16 `Add Android alarm bridge` was squash-merged, adding Android MethodChannel native scheduling/cancel/test-alarm support, capability reporting, notification/full-screen stop fallback, boot/package-replace restore, and QA checklist evidence.
  - Merge commit: `c75be241db1bb2d1e4ae39144bbd439ad55186d7`.
  - Validation evidence: Worker checks passed (`rtk flutter build apk --debug`, `rtk flutter test`, `rtk flutter analyze`, `rtk git diff --check`) and worker `rtk gh-review-hook 16` exited 0; orchestrator reran the same checks and hook from a clean PR-head worktree after the final fix.
  - Review evidence: Worker deep-review self-review and independent reviewer approved after PendingIntent identity hardening; orchestrator final review initially found asynchronous native mirror writes and returned the PR, then re-reviewed the durable `commit()` fix and found no actionable findings before merge.
  - Runtime status: Android API 36 runtime alarm validation remains deferred and unapproved for release approval.

- 2026-07-06 Wave 8 Task_1 Wake Plan Scheduling Service merged.
  - Summary: PR #15 `Add wake plan scheduling service` was squash-merged, adding WakePlan create/edit/delete/skip scheduling orchestration, occurrence generation, NativeAlarmGateway schedule/cancel calls, platformAlarmId persistence, and warning-ready failure states.
  - Merge commit: `50b0061ed2900dd9baec5889263acd0fa3e0273d`.
  - Validation evidence: Worker checks passed (`rtk flutter test test/features/wake_plan/application/wake_plan_service_test.dart`, `rtk flutter analyze`, `rtk git diff --check`), PR Baseline CI passed, and worker `rtk gh-review-hook 15` exited 0; orchestrator reran the focused service test, analyzer, diff check, and hook from a clean PR-head worktree.
  - Review evidence: Worker deep-review self-review and independent reviewer approved; orchestrator performed a final merge-gate review of scheduling/cancel/rollback/platformAlarmId semantics and found no actionable findings.
  - Runtime status: iOS 26+ and Android API 36 runtime alarm validation remains deferred and unapproved for release approval.

- 2026-07-06 Wave 8 Task_3 Android Alarm Bridge returned after orchestrator review.
  - Summary: PR #16 passed worker validation and orchestrator local checks, but orchestrator final review found asynchronous native mirror writes could let canceled alarms be restored after process death.
  - Action: Worker thread `019f35da-44bb-7a30-bb40-9d7ea9fb36b6` was asked to make schedule/cancel mirror writes durable or return native failure, rerun checks and `rtk gh-review-hook 16`, and provide a refreshed merge-ready report.
  - Runtime status: Android API 36 runtime alarm validation remains deferred and unapproved for release approval.

- 2026-07-06 Wave 8 Task_4 Week Calendar Grid and Interaction Core merged.
  - Summary: PR #13 `Add week calendar interaction core` was squash-merged, adding the Wake Plan week calendar model helpers, grid rendering, current-time indicator, tap conversion, compact scaffold placeholder, and focused tests.
  - Merge commit: `91d5a3b43512187c56b7e0bc42c94837dcf498d3`.
  - Validation evidence: Worker checks passed (`rtk flutter test test/features/week_calendar`, `rtk flutter analyze`, `rtk git diff --check`) and PR Baseline CI passed; orchestrator reran the focused week-calendar tests, analyzer, diff check, and `rtk gh-review-hook 13` from a clean PR-head worktree.
  - Review evidence: Worker deep-review self-review and independent reviewer approved; orchestrator performed a final merge-gate review and found no actionable findings.
  - Runtime status: iOS 26+ and Android API 36 runtime alarm validation remains deferred and unapproved for release approval.

- 2026-07-06 Completed Wave 1-7 plans moved to completed lifecycle folder.
  - Summary: Wave 1-7 child plan files were moved from `docs/coding-agent/plans/active/` to `docs/coding-agent/plans/completed/` because their tasks and PR merge evidence were already complete.
  - Link update: Parent child-plan links for Wave 1-7 now point at `../completed/...`; Wave 8+ remains active.
  - New closeout default: future completed wave plans must move out of `active/` before the wave is considered closed.

- 2026-07-06 Wave 8 whole-codebase review closeout added.
  - Summary: Wave 8 child plan now includes Task_6, an integrated codebase-wide review/fix loop after scheduling, native bridge, calendar, and CI smoke tasks complete.
  - Closeout rule: Wave 8 must not move to `completed/` until final orchestrator/reviewer review reports no remaining in-scope findings or explicit deferrals.

- 2026-07-06 Wave 8 Task_2 iOS AlarmKit Bridge merged.
  - Summary: PR #14 `Add iOS AlarmKit native bridge` was squash-merged, adding the iOS native bridge and QA checklist evidence for the Wave 8 child plan.
  - Merge commit: `b2c6bc2abf181ef1613e5da76d6d5c2281b96dd0`.
  - Validation evidence: Worker checks passed (`rtk flutter test`, `rtk flutter analyze`, `rtk git diff --check`, focused Swift bridge typecheck); orchestrator reran `rtk flutter test`, `rtk flutter analyze`, `rtk git diff --check`, focused Swift bridge typecheck, and `rtk gh-review-hook 14` from a clean PR-head worktree, all passing.
  - Review evidence: Worker deep-review self-review and independent reviewer approved; orchestrator inspected PR metadata, diff scope, hosted checks, and checklist release-gate wording.
  - Runtime status: iOS 26+ runtime behavior remains unapproved and release-blocking until real runtime evidence passes; the merged Wave 8 implementation evidence does not approve release reliability.
  - Follow-up: Task_3 Android bridge and Task_4 week calendar PRs were returned to workers for a normal `origin/master` merge and refreshed hook evidence because PR #14 advanced `master`.

- 2026-07-06 Wave 8 Task_1-Task_4 delegated in parallel.
  - Task_1 Wake Plan Scheduling Service thread: `019f35cb-2642-7551-be9f-e35b60b5b1cf`; pending worktree `local:8d7aeb74-f56b-4b33-8bbb-cac5f548ad7c`; branch `codex/wave-08-wake-plan-scheduling-service`.
  - Task_1 startup follow-up: worker initially stopped because the owned service/test files did not exist; orchestrator clarified those files are Task_1-owned new files and instructed the worker to continue.
  - Task_2 iOS AlarmKit Bridge pending worktree: `local:12fa1eed-c1c5-4ee1-97d1-bd3f7ba3df0c`; branch `codex/wave-08-ios-alarmkit-bridge`.
  - Task_3 Android Alarm Bridge pending worktree: `local:96734e84-dcc8-4f8d-96dd-f1be47d01269`; branch `codex/wave-08-android-alarm-bridge`.
  - Task_4 Week Calendar Grid and Interaction Core pending worktree: `local:a1efcac4-d9ac-4d4c-9f57-e453358c73d2`; branch `codex/wave-08-week-calendar-core`.
  - Scope: Execute Wave 8 child plan Task_1-Task_4 in parallel with disjoint owns. Task_5 CI simulator/emulator native smoke remains dependent on Task_2 and Task_3.
  - Validation ownership: workers must provide focused tests/checks, analyzer/diff checks, independent review, PR hook evidence, and merge-ready or blocked reports; orchestrator owns final PR review, merge, ledger completion, and thread archival.
  - Runtime status: iOS 26+ and Android API 36 runtime alarm validation remains deferred and unapproved for release approval.

- 2026-07-06 Wave 7 Task_2 Wake Plan Repository merged; Wave 7 complete.
  - Summary: PR #12 `Add wake plan Drift repository` was squash-merged, adding Drift schema/version 1, WakePlanRepository persistence APIs, nullable per-occurrence `platformAlarmId` lifecycle support, calendar/list queries, soft delete, one-time retention, malformed-row isolation, and focused data tests.
  - Merge commit: `5910c90dcc97ca05be9d2522510a209ad5a26dbc`.
  - Validation evidence: Worker `rtk flutter test test/features/wake_plan/data`, `rtk flutter analyze`, and `rtk git diff --check` passed after hook-requested fixes; orchestrator reran `rtk flutter test test/features/wake_plan/data`, `rtk flutter analyze`, `rtk git diff --check`, and `rtk gh-review-hook 12` from a clean PR-head worktree, and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved; hook iterations hardened malformed persisted row isolation, cancel reservation filtering, repository indexes, SQL-side filters, defensive occurrence/settings mapping, and regression coverage.
  - Hook/check evidence: Worker final `rtk gh-review-hook 12` exited 0; orchestrator reran `rtk gh-review-hook 12`, verified hosted Baseline CI, CodeRabbit, Greptile, and Socket checks passed, and confirmed mergeState `CLEAN`.
  - PR state: #12 merged; branch head `01871fd654440338dd8cb4496202f3aa53315c40`; merge commit `5910c90dcc97ca05be9d2522510a209ad5a26dbc`.
  - Decision impact: Wave 7 is complete; Wave 8 scheduling/native/calendar integration may proceed. iOS 26+ and Android API 36 runtime alarm validation remains deferred and unapproved for release approval.

- 2026-07-06 Wave 7 Task_1 Occurrence Planner merged.
  - Summary: PR #11 `Add wake occurrence planner` was squash-merged, adding pure OccurrencePlanner application logic, WakeInstance/AlarmOccurrence draft result values, and focused planner tests.
  - Merge commit: `3878b794d1f83ddd58f84b5fa1488417c161ca7b`.
  - Validation evidence: Worker `rtk flutter test test/features/wake_plan/application/occurrence_planner_test.dart`, `rtk flutter analyze`, and `rtk git diff --check` passed; orchestrator reran the same checks from a clean PR-head worktree after updating the branch to current master, and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved; orchestrator inspected preview/scheduling candidate separation, repeat/skip semantics, day-crossing handling, target-time inclusion, and scoped ownership.
  - Hook/check evidence: Worker final `rtk gh-review-hook 11` exited 0; orchestrator reran `rtk gh-review-hook 11`, waited for refreshed hosted Baseline CI, CodeRabbit, Greptile, and Socket checks, and all passed.
  - PR state: #11 merged; branch head `dea80f19bbc7407f618c894ee438410bf7bc410d`; merge commit `3878b794d1f83ddd58f84b5fa1488417c161ca7b`.
  - Remaining Wave 7 work: Task_2 Wake Plan Repository remains active or pending orchestrator merge; Task_3 and Task_4 are already merged.

- 2026-07-06 Wave 7 Task_4 Baseline GitHub Actions CI merged.
  - Summary: PR #9 `Add baseline Flutter CI` was squash-merged, adding pull_request/workflow_dispatch baseline CI for Flutter dependency resolution, Dart format, Flutter analyze, Flutter test, log artifacts, and QA documentation.
  - Merge commit: `962dbc5da24ae6447efc436be2464d9c8a922b42`.
  - Validation evidence: Worker `rtk flutter pub get`, `rtk dart format --set-exit-if-changed .`, `rtk flutter analyze`, `rtk flutter test`, and `rtk git diff --check` passed; hosted GitHub Actions Baseline CI passed; orchestrator reran the same local checks plus workflow YAML parse from a clean PR-head worktree after updating the branch to current master, and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved; hook-requested `.fvmrc` alternate key support was fixed; orchestrator inspected workflow triggers, Flutter setup, commands, artifact upload, and scope separation from native smoke/runtime validation.
  - Hook/check evidence: Worker final `rtk gh-review-hook 9` exited 0; orchestrator reran `rtk gh-review-hook 9`, waited for refreshed hosted checks, and verified Baseline CI, CodeRabbit, Greptile, and Socket checks passed.
  - PR state: #9 merged; branch head `c9f75b0fccad1edb979163a827beb3425f1bd64d`; merge commit `962dbc5da24ae6447efc436be2464d9c8a922b42`.
  - Decision impact: Baseline CI is now active for later PRs; it remains ordinary CI evidence and does not approve iOS/Android runtime alarm behavior.

- 2026-07-06 Wave 7 Task_3 MethodChannel Gateway Wiring merged.
  - Summary: PR #10 `Wave 7: Wire native alarm MethodChannel gateway` was squash-merged, adding the MethodChannelNativeAlarmGateway adapter, schema documentation, and contract tests for all native alarm gateway methods.
  - Merge commit: `3167325907868816a04482e358d44b4b707daf9c`.
  - Validation evidence: Worker `rtk flutter test test/core/platform`, `rtk flutter analyze`, and `rtk git diff --check` passed; orchestrator reran `rtk flutter test test/core/platform`, `rtk flutter analyze`, and `rtk git diff --check` from a clean PR-head worktree and all passed.
  - Review evidence: Worker deep-review self-review and independent reviewer approved after a compatibility fix for omitted `supportsTestAlarm`; orchestrator inspected schemaVersion enforcement, cancel identity semantics, PlatformException mapping, and docs/test alignment.
  - Hook/check evidence: Worker final `rtk gh-review-hook 10` exited 0; orchestrator marked PR ready and reran `rtk gh-review-hook 10`, which exited 0; GitHub CodeRabbit and Socket checks passed.
  - PR state: #10 merged; branch head `678fb2c9e8326058cca0ccf06ba2a63243d17f3a`; merge commit `3167325907868816a04482e358d44b4b707daf9c`.
  - Remaining Wave 7 work: Task_1 Occurrence Planner, Task_2 Wake Plan Repository, and Task_4 Baseline GitHub Actions CI remain active or pending orchestrator merge.

- 2026-07-06 Wave 7 planner, repository, MethodChannel, and baseline CI delegated.
  - Task_1 Worker thread: `019f33d4-a600-7462-96ef-26c49e67a936`; pending worktree `local:4503e9d0-f2d6-4bf8-98de-c839dbad3111`; branch `codex/wave-07-occurrence-planner`.
  - Task_2 Worker thread: `019f33d4-a5fc-7ba0-8f14-f974af181e28`; pending worktree `local:8fe1664a-241c-44a9-b5af-6da9c8d272bf`; branch `codex/wave-07-wake-plan-repository`.
  - Task_3 Worker thread: `019f33d4-a978-7b32-8aa5-c9c67e531f6a`; pending worktree `local:140e55b3-2943-487f-9b05-06f15194ac54`; branch `codex/wave-07-method-channel-gateway`.
  - Task_4 Worker thread: `019f33d4-aeca-7053-89b3-8041f60a3f64`; pending worktree `local:6966b4b3-034f-49e2-a2df-4113c90f2439`; branch `codex/wave-07-baseline-ci`.
  - Scope: Execute Wave 7 child plan tasks in parallel with disjoint owns, preserving Wave 8 native runtime validation as deferred and unapproved.
  - Validation ownership: workers must provide task-specific tests/checks, analyzer/diff checks, independent review, PR hook evidence, and merge-ready or blocked reports; orchestrator owns final PR review, merge, ledger completion, and thread archival.

- 2026-07-06 Wave 6 Task_2 Native Alarm Gateway Contract merged; Wave 6 complete.
  - Summary: PR #8 `Wave 6 Task 2: Native alarm gateway contract` was squash-merged, adding pure Dart NativeAlarmGateway contract, fake gateway, request-aware schedule/cancel/test result models, per-occurrence platformAlarmId correlation, and focused platform tests.
  - Merge commit: `10b48a5655b7ffddc7dee600df5b31449039021d`.
  - Validation evidence: Worker `rtk flutter test test/core/platform`, `rtk flutter analyze`, and `rtk git diff --check` passed; orchestrator reran `rtk flutter test test/core/platform`, `rtk flutter analyze`, and `rtk git diff --check` from a clean PR-head worktree and all passed.
  - Review evidence: Worker deep-review and independent review approved after fixes for schedule request/result composite correlation, fake unsupported test-alarm behavior, fake failure naming, shared request/result correlation helper, dominant all-failure status selection, and regression tests; orchestrator inspected the final scoped diff.
  - Hook/check evidence: Worker final `rtk gh-review-hook 8` exited 0; orchestrator reran `rtk gh-review-hook 8` from a clean PR-head worktree and it exited 0; GitHub CodeRabbit, Greptile, and Socket checks passed.
  - PR state: #8 merged; branch head `bd501231535de49edf3b3aaff224d689d35de0a5`; merge commit `10b48a5655b7ffddc7dee600df5b31449039021d`.
  - Decision impact: Wave 7 can consume the domain model and native gateway contract; iOS 26+ and Android API 36 alarm runtime validation remains deferred and unapproved.

- 2026-07-06 Wave 6 Task_1 Wake Plan Domain Models merged.
  - Summary: PR #7 `Add wake plan domain models` was squash-merged, adding pure Dart WakePlan, AlarmOccurrence, RepeatRule, AppSettings, status enums, nullable platformAlarmId support, and focused domain tests.
  - Merge commit: `573a5e2f22d73dca6e27bc9289fe70d165be74be`.
  - Validation evidence: Worker `rtk flutter test test/features/wake_plan/domain` passed with 15 tests, `rtk flutter analyze` passed, and `rtk git diff --check` passed; orchestrator reran `rtk flutter test test/features/wake_plan/domain`, `rtk flutter analyze`, and `rtk git diff --check` from a clean PR-head worktree and all passed.
  - Review evidence: Worker deep-review self-review and independent review found and fixed set hash consistency, nullable settings copy behavior, skip-state consistency, minimum interval, and occurrence timestamp/status issues before merge; orchestrator inspected implementation and tests.
  - Hook/check evidence: Worker `rtk gh-review-hook 7` exited 0 from a clean PR-head worktree; orchestrator reran `rtk gh-review-hook 7` from a clean PR-head worktree and it exited 0; GitHub CodeRabbit, Greptile, and Socket checks passed.
  - PR state: #7 merged; branch head `3be2d61a5820d7311f08db85e795987928c9032d`; merge commit `573a5e2f22d73dca6e27bc9289fe70d165be74be`.
  - Remaining Wave 6 work: completed by PR #8 on 2026-07-06.

- 2026-07-06 Baseline CI task inserted into Wave 7.
  - Summary: Add ordinary GitHub Actions PR CI for Dart format, Flutter analyzer/lints, and Flutter unit tests before the later Wave 8 simulator/emulator native smoke workflow.
  - Timing: Wave 7 is the earliest upcoming wave that can own CI workflow implementation after the Flutter scaffold is available.
  - Scope separation: Wave 7 baseline CI does not claim native alarm runtime evidence; Wave 8 native smoke CI must extend or coexist with it.

- 2026-07-06 Wave 6 domain and gateway contracts delegated.
  - Task_1 Worker pending worktree: `local:ba19222c-bbe3-4305-b41f-f8baa6b1c93a`.
  - Task_1 Branch: `codex/wave-06-wake-plan-domain`.
  - Task_1 Scope: Wave 6 child plan Task_1 only; owns wake plan domain model files.
  - Task_2 Worker pending worktree: `local:dc234667-dde3-4405-b6b1-6ebbbad63e9e`.
  - Task_2 Branch: `codex/wave-06-native-alarm-gateway-contract`.
  - Task_2 Scope: Wave 6 child plan Task_2 only; owns native alarm gateway contract/fake/test files.
  - Validation ownership: each worker must provide focused tests, analyzer/diff checks, independent review, PR hook evidence, and a merge-ready or blocked report.

- 2026-07-06 Wave 5 time foundation merged.
  - Summary: PR #6 `Add time foundation value objects` was squash-merged, adding pure Dart calendar-day, minute-of-day, date+minute, week range, rounding, past-target, and day-crossing helpers with focused tests.
  - Merge commit: `3866a72fd798e677ab813e5cb80f2d44ee069e35`.
  - Validation evidence: Worker `rtk flutter test test/core/time` passed with 17 tests, `rtk flutter analyze` passed, and `rtk git diff --check` passed; orchestrator reran `rtk flutter test test/core/time`, `rtk flutter analyze`, and `rtk git diff --check` from a clean PR-head worktree and all passed.
  - Review evidence: Worker deep-review self-review and independent review found and fixed date-normalization, hidden local `DateTime`, DST-adjacent elapsed-duration, UTC rounding, release-safe validation, and day-rollover rounding issues before merge; orchestrator inspected implementation and tests.
  - Hook/check evidence: Worker final `rtk gh-review-hook 6` exited 0 after fixes; orchestrator reran `rtk gh-review-hook 6` from a clean PR-head worktree and it exited 0; GitHub CodeRabbit, Greptile, and Socket checks passed.
  - PR state: #6 merged; branch head `ee2389a8e48f6e6d746e6794d00d4e7e47491ec8`; merge commit `3866a72fd798e677ab813e5cb80f2d44ee069e35`.
  - Decision impact: Wave 6+ may use `lib/core/time/**` for Wake Plan domain and calendar logic; unresolved DST-depth remains an explicit future/open-question risk, not release approval.

- 2026-07-06 Wave 5 time foundation delegated.
  - Worker pending worktree: `local:1a752aa1-4554-4f5f-97b3-e49a62e72e88`.
  - Branch: `codex/wave-05-time-foundation`.
  - Scope: Wave 5 child plan Task_1 only; parent thread must not implement product code.
  - Validation ownership: worker must provide time foundation tests, analyzer/diff checks, independent review, PR hook evidence, and a merge-ready or blocked report.

- 2026-07-06 Wave 4 Flutter scaffold merged.
  - Summary: PR #5 `Scaffold Flutter app` was squash-merged, creating the Flutter app scaffold, iOS/Android targets, Riverpod/Drift bootstrap, feature/core boundaries, `.fvmrc`, and placeholder tests for later waves.
  - Merge commit: `d59d3c4c8d2912f29e9bf6cfcb4265b8f3dd188b`.
  - Validation evidence: Worker `rtk git diff --check`, `rtk flutter analyze`, `rtk flutter test`, and `rtk flutter build apk --debug` passed; orchestrator reran `rtk git diff --check`, `rtk flutter analyze`, and `rtk flutter test` from a clean PR-head worktree and all passed.
  - Review evidence: Worker deep-review self-review completed; independent reviewer approved with residual note that iOS build/runtime was not included; orchestrator inspected PR diff, app identity, platform identifiers, `.fvmrc`, tests, and directory boundaries.
  - Hook/check evidence: Worker `rtk gh-review-hook 5` exited 0; orchestrator reran `rtk gh-review-hook 5` from a clean PR-head worktree and it exited 0; GitHub CodeRabbit, Greptile, and Socket checks passed.
  - PR state: #5 merged; branch head `f733607d7f06a9bbaa843bdcc4284faca8ae44ff`; merge commit `d59d3c4c8d2912f29e9bf6cfcb4265b8f3dd188b`.
  - Decision impact: Wave 5+ may proceed on the merged Flutter scaffold; iOS 26+ and Android API 36 alarm runtime validation remains deferred and unapproved.

- 2026-07-06 Wave 4 Flutter scaffold delegated.
  - Worker pending worktree: `local:1c694580-6c47-4f8a-bea9-226aad1c2c09`.
  - Branch: `codex/wave-04-flutter-scaffold`.
  - Scope: Wave 4 child plan Task_1 only; parent thread must not implement product code.
  - Validation ownership: worker must provide scaffold validation, independent review, PR hook evidence, and a merge-ready or blocked report.

- 2026-07-06 Wave 3 platform decision merged.
  - Summary: PR #4 `Record Wave 3 platform decision` was squash-merged after orchestrator review as the source of truth for MVP native alarm implementation planning under deferred runtime approval.
  - Merge commit: `86c9631ed0cd351beb513f218919b9d66f3e1932`.
  - Validation evidence: Worker `rtk git diff --check` passed; no markdown/docs lint config or script was discoverable; orchestrator `rtk git diff --check master..origin/codex/wave-03-platform-decision` passed; orchestrator reran `rtk gh-review-hook 4` from the clean worker worktree and it exited 0.
  - Review evidence: Worker deep-review self-review completed; independent focused reviews approved after fixing Wave 8/11 runtime gate handling, Wave 6/7 platform identity contracts, PR hook findings, and follow-up hook findings; GitHub CodeRabbit, Greptile, and Socket checks passed.
  - Decision impact: Wave 4+ may proceed from API-surface feasibility, rolling concrete native occurrence reservations are the MVP implementation model, and Wave 14 retains release-blocking runtime validation for iOS 26+ and Android API 36 behavior.
  - PR state: #4 merged; branch head `502eca4466b67068c74d85bd273e188a5d19b0db`; merge commit `86c9631ed0cd351beb513f218919b9d66f3e1932`.

- 2026-07-06 Wave 3 platform feasibility decision recorded.
  - Summary: MVP implementation planning may continue from iOS/Android API-surface feasibility, but neither platform is runtime-approved.
  - Architecture decision: use rolling concrete native occurrence reservations with one stored platform alarm identity per `AlarmOccurrence`; do not use OS recurrence as the MVP source of truth for repeating plans, next-skip, individual cancel, or plan cancel.
  - iOS adoption: implement an AlarmKit bridge around concrete UUID-backed occurrences and authorization state, with runtime validation still required before release approval.
  - Android adoption: implement AlarmManager using `setAlarmClock` as the first candidate, distinct `PendingIntent` identities, permission/status checks, native minimal stop UI, and BootReceiver restore, with runtime validation still required before release approval.
  - Release gate: Wave 14 must keep deferred runtime validation blocking for wake reliability, lock/terminated behavior, permissions, full-screen stop UI, cancel semantics, and reboot restore.

- 2026-07-06 Runtime validation deferred; Wave 3 may proceed with runtime-unapproved platform evidence.
  - Summary: User approved deferring iOS 26+ and Android API 36 runtime validation.
  - Scope of deferment: iOS AlarmKit and Android alarm runtime behavior remain unverified for wake reliability, lock/terminated behavior, permissions, full-screen stop UI, cancel semantics, and reboot restore.
  - Plan impact: Wave 2 closes as merged blocker/API-surface evidence; Wave 3 must decide MVP scope and downstream assumptions without claiming platform runtime approval.
  - Validation evidence: user decision in orchestration thread; existing Wave 2 PR evidence remains the source for what is known and unknown.

- 2026-07-06 Wave 2 Android spike blocker evidence merged; Wave 2 blocked on external runtime evidence.
  - Summary: PR #3 `Record Android alarm spike blocker evidence` was squash-merged after orchestrator review as a blocked evidence update, not as Android MVP approval.
  - Merge commit: `d07086e6951aa0f2b2eae787e56d152d45fac7f4`.
  - Validation evidence: Worker `rtk git diff --check` passed; Android build/compile was not run because no `android/**` project exists and no Android API 36 SDK/runtime is installed; independent Worker reviewer approved; `gh-review-hook 3` exited 0 after the Worker clarified readiness wording; GitHub checks passed.
  - Blocker: no Android API 36 device/emulator/runtime was available; `adb devices -l` found no attached devices or running emulators; `emulator -list-avds` found no AVDs; installed SDK platforms were android-30, android-33, and android-34 only; no installable Android target exists in the repository.
  - Orchestrator review evidence: PR diff, `rtk git diff --check`, PR metadata, and GitHub checks were inspected; Android runtime cases remain explicitly pending/blocked and the document does not approve Android MVP alarm reliability.
  - PR state: #3 merged; branch head `a1af0266505850bf99c55ab68e570914a9320bb5`; merge commit `d07086e6951aa0f2b2eae787e56d152d45fac7f4`.
  - Next decision needed: resolved on 2026-07-06 by user-approved runtime-validation deferment; Wave 3 may proceed but must not claim runtime approval.

- 2026-07-06 Wave 2 Android spike delegated to Worker.
  - Summary: Wave 2 Task_2 was dispatched after iOS blocked evidence was merged, preserving single-writer ownership of `docs/spikes/native-alarm-feasibility.md`.
  - Worker branch: `codex/wave-02-android-alarm-spike`.
  - Worker state: pendingWorktreeId `local:19d896f0-cf7c-4471-8110-403527fcfc38`.
  - Validation evidence: pending Android API 36 real-device/emulator evidence or concrete blocked report, Worker validation, independent review, optional PR hook, and orchestrator merge gate.

- 2026-07-06 Wave 2 iOS spike blocker evidence merged.
  - Summary: PR #2 `Record iOS AlarmKit spike blocker evidence` was squash-merged after orchestrator review as a blocked evidence update, not as iOS MVP approval.
  - Merge commit: `1dd4b7ef91cff1f2db12a1d0a2875bfaf93d28d6`.
  - Validation evidence: Worker `rtk git diff --check` passed; bounded AlarmKit SDK `swiftc -typecheck` probe passed; independent Worker reviewer approved; `gh-review-hook 2` exited 0; GitHub checks passed.
  - Blocker: no iOS 26+ real device or compatible runtime was available; `xcrun devicectl list devices` found no devices; available simulator runtime was iOS 18.0 only; no repository `ios/` app target exists for install/terminated-app validation.
  - Orchestrator review evidence: PR diff and final `docs/spikes/native-alarm-feasibility.md` were inspected; iOS runtime cases remain explicitly pending/blocked and the document does not approve iOS MVP alarm reliability.
  - PR state: #2 merged; branch head `6e5da033c8e640acf648ac5139482d5ad5e7e041`; merge commit `1dd4b7ef91cff1f2db12a1d0a2875bfaf93d28d6`.

- 2026-07-06 Wave 2 iOS spike delegated to Worker.
  - Summary: Wave 2 Task_1 was dispatched first because Wave 2 Task_1 and Task_2 both update `docs/spikes/native-alarm-feasibility.md`.
  - Worker branch: `codex/wave-02-ios-alarmkit-spike`.
  - Worker state: pendingWorktreeId `local:e1f9aad7-06a0-4aed-b5be-fedd6a1cc42a`.
  - Validation evidence: pending iOS 26+ device/compatible-environment evidence or concrete blocked report, Worker validation, independent review, optional PR hook, and orchestrator merge gate.

- 2026-07-06 Wave 1 merged.
  - Summary: PR #1 `Add native alarm spike evidence template` was squash-merged after orchestrator merge gate.
  - Merge commit: `79ac0480c15a577edb7c2f38268686b7fdb393b6`.
  - Validation evidence: Worker acceptance inspection passed; `rtk git diff --check` passed; no markdown/docs lint target was present; independent Worker reviewer approved twice; `gh-review-hook 1` exited 0 after the Worker added iOS Silent/Focus and Android reboot-restore coverage.
  - Orchestrator review evidence: PR diff and `docs/spikes/native-alarm-feasibility.md` were inspected against Wave 1 acceptance; required iOS/Android environment fields, verification case fields, required cases, failure decision points, explicit `pending` placeholders, and release-readiness criteria were present.
  - PR state: #1 merged; branch head `144bdeb38ebdebd437e91b8e1c11996606c87c16`; merge commit `79ac0480c15a577edb7c2f38268686b7fdb393b6`.

- 2026-07-06 Wave 1 delegated to Worker.
  - Summary: Wave 1 Task_1 was dispatched in a separate worktree for branch `codex/wave-01-spike-evidence-template`.
  - Worker state: pendingWorktreeId `local:0e4f82c0-42d9-4b75-8069-cad1fe412deb`.
  - Validation evidence: pending Worker PR, independent review, `gh-review-hook`, and orchestrator merge gate.

- 2026-07-05 Draft split: Wave 1-14 child plans created.
  - Summary: 元の24タスク計画を wave 単位の14個の独立プランへ分割し、親プランを目次と全体統制に変更した。
  - Validation evidence: 各子プランがGoal、Definition of Done、Task_X、Task Waves、validation、handoff、logsを持つ。
  - Notes: repo-specific rule suite was absent; validation was selected from project documents and general Flutter/native app expectations.

- 2026-07-07 Wave 8 closeout review entered delegated fix loop.
  - Summary: After Task_5 PR #17 was manually merged, Task_6 review found one in-scope scheduling-service recovery gap: edit replacement schedule failure after successful old-alarm cancellation can leave the edited WakePlan persisted without durable failed/pending state.
  - Action: Delegated narrow fix to worker agent `019f3c45-17e0-7220-a6f2-3ce36049f9b6` on branch `codex/wave-08-task6-edit-schedule-failure`; Wave 8 remains active until the worker PR, required checks, independent review, and orchestrator merge gate pass.
  - Runtime status: Real iOS 26+ and Android API 36 alarm validation remains deferred/unapproved and release-blocking.

## Decision Log (append-only; re-plans and major discoveries)

- 2026-07-06 Decision: Add CI near-device smoke early without relaxing runtime approval.
  - Trigger / new insight: User asked whether CI can run tests close to real-device validation and then clarified it should be done as early as practical.
  - Plan delta (what changed): Wave 8 now includes a Task_5 CI simulator/emulator native smoke harness after iOS/Android bridge tasks; Wave 14 keeps final CI smoke rerun/evidence integration for release readiness.
  - Tradeoffs considered: Early CI can catch build/install/platform-channel/schedule/cancel regressions soon after native bridge work, but hosted simulators/emulators still cannot approve wake delivery, lock/terminated, Silent/Focus, full-screen stop, or Android reboot restore behavior.
  - User approval: yes.

- 2026-07-06 Decision: Add ordinary baseline CI before native smoke CI.
  - Trigger / new insight: User asked to add ordinary CI validation in addition to near-device CI, specifically formatting, lint/analyzer, and unit tests.
  - Plan delta (what changed): Wave 7 now owns a baseline GitHub Actions CI task; Wave 8 native smoke CI must preserve that ordinary PR validation path.
  - Tradeoffs considered: Baseline CI can run on normal hosted runners immediately after scaffold, while native smoke remains later because it depends on bridge code and simulator/emulator availability.
  - User approval: yes.

- 2026-07-06 Decision: Continue MVP implementation with rolling native occurrence reservations under deferred runtime approval.
  - Trigger / new insight: Wave 2 evidence shows API-surface feasibility but no iOS 26+ or Android API 36 runtime proof; user approved deferring runtime validation.
  - Plan delta (what changed): Wave 4+ may proceed, Wave 8/11 must implement/check the native paths without claiming platform approval, and Wave 14 retains release-blocking runtime gates.
  - Tradeoffs considered: Rolling concrete reservations preserve next-skip and cancel semantics across platforms; the tradeoff is more reconciliation and QA burden than relying on OS recurrence.
  - User approval: yes.

- 2026-07-06 Decision: Defer native runtime validation and continue planning under explicit risk.
  - Trigger / new insight: User approved deferring runtime validation.
  - Plan delta (what changed): Wave 2 is no longer an active blocker; Wave 3 may proceed as a platform decision under unverified runtime evidence, and later QA/release gates must retain the deferred runtime validation risk.
  - Tradeoffs considered: This keeps implementation planning moving from API-surface evidence while avoiding a false reliability claim for native alarms.
  - User approval: yes.

- 2026-07-06 Decision: Block Wave 2 and pause platform approval until runtime validation path is available.
  - Trigger / new insight: iOS and Android spike evidence has been merged, but both platforms lack required runtime validation environments for release-quality alarm reliability decisions.
  - Plan delta (what changed): Wave 2 remained blocked until the user-provided external device/API validation decision; superseded on 2026-07-06 by user-approved runtime-validation deferment.
  - Tradeoffs considered: Continuing with product implementation from documentation-only alarm evidence would risk building on unproven native wake behavior; pausing platform approval keeps the blocker visible while preserving the useful API feasibility notes.
  - User approval: superseded by deferment approval.

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
