# Plan: Holiday-Aware Weekday Alarms

- status: completed
- generated: 2026-08-02
- last_updated: 2026-08-02
- work_type: mixed

## Goal

- 曜日繰り返しのWake Planに「祝日をスキップ」オプションを追加する。
- 祝日カレンダーは国・地域単位で選択・切り替え可能にする。第一弾は日本。
- 日本の祝日データは内閣府CSVを元に生成したICSを別リポジトリ (`xpadev-net/holidays-ical`) から `raw.githubusercontent.com` 経由で配信し、GitHub Actionsで月次更新する。

## Definition of Done

- `xpadev-net/holidays-ical` リポジトリが公開され、`holidays/JP.ics` を配信している。月次cron + `workflow_dispatch` の更新ワークフローと、PR/push時のユニットテストワークフローが動作する。
- 設定画面で祝日カレンダー（Off / Japan）を選択できる。
- Wake Plan編集画面で、曜日繰り返しを選んだ場合のみ「祝日をスキップ」トグルが表示され、保存されたWakePlanに反映される。
- `OccurrencePlanner` が選択済み祝日を考慮してoccurrenceを除外し、祝日が連続してもフォールバックの次回探索が機能する。
- 祝日データの取得・解析に失敗した場合はfail-open（何も除外しない）で、アラームのスケジューリングをブロックしない。
- 既存のテストスイート（581件）が全てパスし、`flutter analyze`/`dart format --set-exit-if-changed` がクリーン。

## Scope / Non-goals

- Scope:
  - `holidays-ical`（新規別リポジトリ）: CSV取得・ICS生成スクリプト、GitHub Actionsワークフロー、テスト。
  - `lib/features/wake_plan/domain/**`: `HolidayRegion`, `Holiday`, `WakePlan.skipHolidays`, `AppSettings.holidayRegion`。
  - `lib/features/wake_plan/data/**`: Driftスキーマ v3→v4マイグレーション、`HolidayIcsParser`、`HolidayRepository`。
  - `lib/features/wake_plan/application/**`: `OccurrencePlanner`の祝日対応、`WakePlanService`の`holidaysSnapshot`、`activeHolidaySetProvider`。
  - `lib/features/settings/**`: 地域選択UI。
  - `lib/features/wake_plan/ui/create_wake_plan_sheet.dart`: 祝日スキップトグル。
  - `test/features/wake_plan/**`。
- Non-goals:
  - 日本以外の地域データ（枠組みは拡張可能な設計だが、今回はJPのみ実装）。
  - GitHub Pagesでの配信（raw.githubusercontent.comのみ）。
  - 祝日データの手動アップロード・オフラインバンドル。

## Context (workspace)

- Related files/areas:
  - `lib/features/wake_plan/application/occurrence_planner.dart`（`WakePlan.occursOn`をラップするフック）
  - `lib/features/wake_plan/data/src/wake_plan_database.dart`（既存の追加専用マイグレーション規約）
  - `lib/features/settings/presentation/settings_placeholder.dart`
- Existing patterns or references:
  - `docs/coding-agent/plans/completed/wake-alarm-mvp-wave-12-repeat-skip-plan.md`（`skipNextDate`と同様のoccursOnフック方式）
- Repo reference docs consulted:
  - `requirements.md`（7.7節で祝日除外がMVP対象外と明記）

## Key design decisions

- `HolidayRegion`は列挙型（現状`japan`のみ）、`AppSettings.holidayRegion`はnullable（デフォルトOff、opt-in）。
- 祝日データはDriftの`HolidayCacheRows`/`HolidayFetchMetadataRows`にキャッシュし、`HolidayRepository.holidaysFor()`はキャッシュを即座に返しつつバックグラウンドで非同期リフレッシュする（stale-while-revalidate、既定7日）。
- `OccurrencePlanner.plan()`に`Set<CalendarDay> holidays`パラメータを追加。`WakePlan.skipHolidays`と組み合わせて判定し、`_nextWeeklyDay`のフォールバック探索は祝日スキップ有効時のみ7日→21日に拡大。
- `WakePlanService`は`holidaysSnapshot`をコンストラクタで受け取る同期クロージャとして持つ。Riverpodワイヤリングでは`wakePlanServiceProvider`内で`ref.watch(activeHolidaySetProvider)`ではなく`ref.read`をクロージャ内で遅延評価する設計に修正した（`ref.watch`で直接依存させると`activeHolidaySetProvider`の解決のたびに`wakePlanServiceProvider`自体が再構築され、進行中のservice状態を破棄してしまい、既存のwidgetテストが壊れることが判明したため）。
- ネットワーク/パース失敗時は例外を握りつぶし、`lastError`をメタデータに記録するのみで`holidaysFor`は空集合を返す（fail-open）。

## Progress Log (append-only)

- 2026-08-02 Implemented end-to-end in a single session (Claude Code, direct implementation, no sub-agent delegation):
  - Created and pushed `xpadev-net/holidays-ical` (public), generator (`scripts/generate_jp_ics.py` + `scripts/ics_writer.py`, Python stdlib only), fixtures/tests, and two GitHub Actions workflows (`update.yml` monthly cron + `workflow_dispatch`, `test.yml` on PR/push). Verified both workflows run green and `holidays/JP.ics` (1067 events) is served via raw.githubusercontent.com.
  - Implemented calarm app changes per Scope above; full local `flutter test` (581 tests), `flutter analyze`, and `dart format --set-exit-if-changed .` all pass.
  - Found and fixed a real regression during implementation: watching `activeHolidaySetProvider` from `wakePlanServiceProvider` caused rebuild-driven state loss that broke `week_calendar_placeholder_test.dart`'s detail/edit flow; fixed by reading it lazily inside the `holidaysSnapshot` closure instead.
  - Widened `test/app_scaffold_test.dart`'s compact-landscape drag budget (20→30 attempts) since the new Settings region picker legitimately increased scrollable content height.
