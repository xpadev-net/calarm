# Plan: Codebase Deep-Review Remediation

- status: approved
- generated: 2026-07-10
- last_updated: 2026-07-14
- work_type: code
- orchestrator_model_policy: `gpt-5.6-luna` / `high` for every worker start, resume, and replacement

## Goal

- Remediate every confirmed actionable finding from the 2026-07-10 whole-codebase deep review without implementing product code in the parent thread.
- Deliver small, independently reviewed PRs, merged only after worker and orchestrator validation gates pass.
- Restore reliable alarm scheduling across Dart, Android, and iOS while preserving explicit failure semantics and release-blocking real-device gates.

## Definition of Done

- Tasks 1-14 and Task 17 are merged with current validation, independent review, worker `gh-review-hook` exit 0, orchestrator deep-review, orchestrator hook exit 0, and clean merge state.
- Task 15 harmonization passes full format/analyze/test and Android build checks; iOS compile validation is pass or explicitly blocked only by a recorded local platform limitation with remote CI evidence.
- No confirmed deep-review finding remains unowned.
- Existing real-device iOS 26+ and Android API 36 release gates remain truthfully BLOCKED until Task 16 receives user-owned device evidence.
- Every worker thread is archived after merge or an explicit stopped/split decision.

## Scope / Non-goals

- Scope:
  - iOS AlarmKit authorization configuration.
  - Android alarm identity, permission, vibration, reboot, and Direct Boot behavior.
  - Flutter home responsiveness and deterministic clock injection.
  - Rolling schedule replenishment, mutation compensation, idempotent retry, native/Drift reconciliation, and ringing state.
  - Repository-generated-file ignore hygiene.
- Non-goals:
  - New alarm features, custom sounds, snooze, stop-all, calendar integrations, or release-signing setup.
  - Relabeling simulator/emulator evidence as real-device approval.
  - Broad refactors not required by a confirmed finding.

## Context

- Source review: parent thread whole-codebase `$deep-review` on 2026-07-10.
- Existing release gate: `docs/qa/release-readiness.md` is BLOCKED for real-device evidence.
- Repository rules: `docs/coding-agent/rules/**` is absent; validation is inferred from `.github/workflows/baseline-ci.yml`, `.github/workflows/native-smoke.yml`, and repository QA docs.
- Research waived: the immediately preceding deep review mapped the architecture, reproduced the two failing tests, verified Android build, and grounded every task below to current source.
- Repository owner: `xpadev-net`; autonomous worker PR creation and orchestrator merge are allowed.
- Parent implementation boundary: the parent may mutate only this ledger/plan and perform orchestrator-owned GitHub merge/archive actions.

## Quality Routing

- Routing level: L3.
- In scope: Flutter/Dart, Kotlin/Android, Swift/AlarmKit, MethodChannel contracts, SQLite/Drift state, lifecycle/retry/idempotency, UI layout, platform permissions.
- Out of scope quality docs: Rust, TypeScript/JavaScript, Python, Go, and web-framework gates because those stacks are absent.
- Top risks: data integrity, ordering/concurrency, cross-platform contract drift, untracked native side effects, permission/reboot recovery, user-visible alarm failure.

## Tasks

### Task_1: Add required iOS AlarmKit usage description

- status: complete
- worker_thread: `019f4a5e-02ad-79b3-b0e3-d8c3bc7a4975`
- worker_branch: `codex/reviewfix-ios-alarmkit-usage`
- worker_runtime: `gpt-5.6-luna` / `xhigh`
- pr: `#38` — https://github.com/xpadev-net/calarm/pull/38
- worker_head: `73e03c1b5a2a139f63e76981e7edfc5d6a200320`
- merge_commit: `d97e245195d9f8f8f1f0bcb30f89214d13d65a76`
- worker_thread_archived: true
- type: impl
- owns:
  - `ios/Runner/Info.plist`
  - `ios/RunnerTests/**` only for configuration regression coverage
- depends_on: [Task_4]
- acceptance:
  - `NSAlarmKitUsageDescription` is non-empty, user-facing, and consistent with Calarm's wake-alarm purpose.
  - A deterministic plist/configuration check fails when the key is missing or blank.
  - No unrelated iOS project or signing changes are included.
- validation:
  - kind: command; required: true; owner: worker; detail: `plutil -lint ios/Runner/Info.plist` plus focused configuration test.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: independent review plus `$deep-review` of the final diff.

### Task_2: Separate Android alarm detail and firing intents; honor vibration

- status: complete
- worker_thread: `019f4a5e-02b3-7ee1-9651-24f8ba408ca8`
- worker_branch: `codex/reviewfix-android-alarm-intents-vibration`
- worker_runtime: `gpt-5.6-luna` / `xhigh`
- pr: `#40` — https://github.com/xpadev-net/calarm/pull/40
- worker_head: `01c7380c42d00287310249dfc4508d8648c7069b`
- merge_commit: `c3d1986321cedfecf7936d848e8ad3f5cc0abfbb`
- worker_thread_archived: true
- type: impl
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt`
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmReceiver.kt`
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmStopActivity.kt`
  - `android/app/src/test/**`
  - `android/app/build.gradle.kts` only if narrowly required for native tests
- depends_on: [Task_4]
- acceptance:
  - `AlarmClockInfo.showIntent` opens a non-ringing detail surface and cannot start sound/vibration or mutate the scheduled alarm.
  - The operation PendingIntent remains the only time-triggered firing path.
  - Firing reads the persisted request and never vibrates when `vibrationEnabled` is false.
  - Early detail display does not remove mirror state or leave a second scheduled firing path.
  - Regression tests cover early showIntent send, scheduled fire, stop, and vibration on/off.
- validation:
  - kind: command; required: true; owner: worker; detail: focused Android native tests.
  - kind: command; required: true; owner: worker; detail: `flutter build apk --debug`, `flutter analyze`, `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: Android lifecycle/security review and `$deep-review`.

### Task_3: Make the Flutter home layout responsive after async load

- status: complete
- worker_thread: `019f4a5e-055b-71a1-9303-822c6f507a14`
- worker_branch: `codex/reviewfix-responsive-home`
- worker_runtime: `gpt-5.6-luna` / `xhigh`
- pr: `#41` — https://github.com/xpadev-net/calarm/pull/41
- worker_head: `3a481d39b923798fe09ea72915636481e4297183`
- merge_commit: `0e3b4f5df3e1eeb279e98d0f2a74db1ccfe48ac2`
- worker_thread_archived: true
- type: impl
- owns:
  - `lib/app.dart`
  - `lib/features/settings/presentation/settings_placeholder.dart`
  - `test/app_scaffold_test.dart`
  - `test/features/settings/presentation/settings_placeholder_test.dart`
- depends_on: [Task_4]
- acceptance:
  - The loaded home screen has no vertical RenderFlex overflow on compact portrait and landscape constraints.
  - Calendar, ringing, settings, and wake-plan surfaces remain reachable through an intentional scroll/flex structure.
  - Async loading, error, and loaded states have regression tests that call `pumpAndSettle` and assert no framework exception.
  - Existing settings save/error behavior remains unchanged.
- validation:
  - kind: command; required: true; owner: worker; detail: focused app/settings widget tests at compact portrait and landscape sizes.
  - kind: command; required: true; owner: worker; detail: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`.
  - kind: e2e; required: true; owner: reviewer; detail: bounded Flutter widget visual/layout evidence; native/browser screenshot waiver must be explicit if no runnable harness exists.

### Task_4: Propagate the injected clock into wake-plan sheets

- status: complete
- worker_thread: `019f4a0e-0e34-7193-b3ec-f42d6216acfb`
- worker_branch: `codex/reviewfix-clock-injection`
- worker_runtime: `gpt-5.6-luna` / `xhigh`
- pr: `#35` — https://github.com/xpadev-net/calarm/pull/35
- worker_head: `7681cecc3abd4c4c131e0e7d418d1a6182b8f528`
- merge_commit: `a783c5d06d744b13ea981497e2bacfe28652575f`
- worker_thread_archived: true
- type: test
- owns:
  - `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`
  - `lib/features/wake_plan/ui/wake_plan_detail_sheet.dart`
  - `test/features/week_calendar/presentation/week_calendar_placeholder_test.dart`
  - `test/features/wake_plan/ui/wake_plan_detail_sheet_test.dart`
- depends_on: []
- acceptance:
  - Create/edit sheets use the same injected clock as the calendar and `WakePlanService` for validation.
  - The two currently failing tests pass regardless of wall-clock date.
  - Tests explicitly prove the provider clock, not `DateTime.now`, controls future/past save eligibility.
- validation:
  - kind: command; required: true; owner: worker; detail: run both previously failing tests individually and the full week-calendar test file.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: clock-boundary and test-hermeticity review.

### Task_5: Restore Flutter generated-file ignore hygiene

- status: complete
- worker_thread: `019f4a5e-0636-7351-b735-bbe84d41370e`
- worker_branch: `codex/reviewfix-flutter-gitignore`
- worker_runtime: `gpt-5.6-luna` / `xhigh`
- pr: `#39` — https://github.com/xpadev-net/calarm/pull/39
- worker_head: `87c9ffd644ee05c1ff8b74180d4bb5123aca21fb`
- merge_commit: `826628fa7324222f4fb578ab60f2a2d5c67ce46b`
- worker_thread_archived: true
- type: chore
- owns:
  - `.gitignore`
- depends_on: [Task_4]
- acceptance:
  - Standard Flutter/Dart build, tool, IDE, and platform-generated artifacts are ignored without ignoring tracked source/configuration.
  - Existing `.serena` exclusion remains.
  - The change does not remove or rewrite any user-owned untracked file.
- validation:
  - kind: command; required: true; owner: worker; detail: `git check-ignore -v` for `.dart_tool/`, `.flutter-plugins-dependencies`, `build/`, and generated SwiftPM configuration paths.
  - kind: review; required: true; owner: reviewer; detail: verify no source or intended lockfile is over-ignored.

### Task_6: Repair Android exact-alarm, full-screen, and Direct Boot recovery

- status: complete
- stopped_cli_session: `019f4cd9-8741-75d3-9944-2fb899e496c5`
- stopped_cli_session_archived: true
- worker_thread: `019f4d61-3a43-7a90-97f9-0f78d1a14124`
- replacement_worker_thread: `019f4dd2-951f-7551-b0a1-0995ed137340`
- branch: `codex/reviewfix-android-recovery-thread`
- worker_runtime: `gpt-5.6-luna` / `high`
- pr: `#42` — https://github.com/xpadev-net/calarm/pull/42
- final_head: `779daec2eb288c5d0fed5e6d93c2e84d3a87f06e`
- merge_commit: `67df3f795879f7dabf1c820d169f7627807f24d4`
- worker_thread_archived: true
- type: impl
- owns:
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt`
  - `android/app/src/main/kotlin/dev/xpa/calarm/BootReceiver.kt`
  - `android/app/src/test/**`
  - `android/app/build.gradle.kts` only if required for tests
  - `docs/qa/android-alarm-checklist.md` only for changed recovery evidence
- depends_on: [Task_2]
- acceptance:
  - Full-screen access uses `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT` with package URI and a safe fallback.
  - `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` triggers idempotent restore after re-grant.
  - `LOCKED_BOOT_COMPLETED` is actually executable before unlock and reads only device-protected mirror state.
  - Boot, package replacement, permission re-grant, and duplicate broadcasts restore each future alarm once and drop expired entries safely.
  - Tests cover missing permission, re-grant, locked boot, unlocked boot, duplicate delivery, and corrupt mirror rows.
- validation:
  - kind: command; required: true; owner: worker; detail: focused native recovery tests and manifest inspection.
  - kind: command; required: true; owner: worker; detail: `flutter build apk --debug`, `flutter analyze`, `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: Android permission/direct-boot security review.

### Task_7: Add rolling schedule replenishment

- status: complete
- stopped_cli_session: `019f4cd9-8755-7283-8189-f870a3fb92d8`
- stopped_cli_session_archived: true
- worker_thread: `019f4d61-3a43-7a90-97f9-0f50eb5366d9`
- branch: `codex/reviewfix-rolling-replenishment-thread`
- worker_runtime: `gpt-5.6-luna` / `high`
- authority_gap_follow_up: Task_13 owns native-success/database-write crash-window recovery after Task_10-12 provide stable identity and native inventory
- pr: `#43` — https://github.com/xpadev-net/calarm/pull/43
- final_head: `7c8432cdb25c905a0120960b90d160227d86f89d`
- merge_commit: `dfaaf927d5b15858202f1fc6668fe32e757acef7`
- worker_thread_archived: true
- worker_hook: exit 0 after four invocations; the first returned two actionable findings and the final invocation explicitly captured exit 0
- orchestrator_hook: exit 0
- type: impl
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `lib/features/wake_plan/application/occurrence_planner.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart`
  - `lib/core/bootstrap/app_bootstrap.dart`
  - `lib/app.dart`
  - corresponding `test/features/wake_plan/**` and `test/app_scaffold_test.dart`
- depends_on: [Task_3]
- acceptance:
  - Enabled repeating plans always maintain the configured rolling future horizon after startup/resume/reconciliation.
  - A same-weekday plan created after today's target schedules the next valid week instead of succeeding with zero requests.
  - Repeated normal-path reconciliation is idempotent for occurrences with authoritative persisted platform IDs and does not duplicate existing occurrences or native requests.
  - Concurrent reconciliation requests are serialized without dropping a later request whose snapshot or lifecycle admission may differ.
  - Disabled/deleted/skipped plans are not replenished incorrectly.
  - Empty schedule results cannot masquerade as successful scheduling when an enabled plan should have a future occurrence.
- validation:
  - kind: command; required: true; owner: worker; detail: focused tests for same-weekday-after-time, day advancement, restart/resume, duplicate reconcile, skip, disabled, deleted.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: state/idempotency/time-boundary review.

### Task_8: Make edit/delete/skip compensation preserve the authoritative schedule

- status: complete
- worker_thread: `019f4e4e-3915-7e02-b823-bba4a34dd31c`
- branch: `codex/reviewfix-wake-plan-compensation`
- worker_head: `9b6058440e15999b24bd00ba95b71fe1cd1282ba`
- pr: `#44` — https://github.com/xpadev-net/calarm/pull/44
- merge_commit: `bbea05ef1c9b9df75a76f48c3d1815760cde81df`
- worker_thread_archived: true
- type: impl
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `test/features/wake_plan/application/wake_plan_service_test.dart`
- depends_on: [Task_7]
- acceptance:
  - Old cancel success followed by replacement schedule failure restores the old native reservation set, not only the plan row.
  - Partial old-cancel and replacement-cancel failures converge to an explicit recoverable state without silent missing or extra alarms.
  - Delete, edit, skip, and undo share consistent compensation semantics.
  - Every returned result accurately describes DB and native state; no success or restored UI state is emitted while alarms differ.
- validation:
  - kind: command; required: true; owner: worker; detail: focused fault-injection tests for each cancel/schedule/compensation boundary.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: failure-state-machine and retry review.
- review_evidence:
  - independent Reviewer `019f4f0c-14e9-7c11-9dae-84d19fbde74c` APPROVED exact head with no Blocker/High findings.
  - worker validation: 43 focused service tests, `flutter analyze`, full 232-test suite, and diff check passed.
  - orchestrator validation: exact-head 43 focused tests, analyze, full 232-test suite, and diff check passed in a clean temporary worktree.
  - orchestrator `$deep-review`: no Blocker/High findings; persistence, compensation, concurrency, cross-midnight metadata, and shared mutation paths reviewed.
  - final-head `gh-review-hook 44`: exit 0 in a clean temporary worktree; hosted checks 5/5 passed and review decision APPROVED.
  - residual risk: adapter-specific partial writes are not modeled by in-memory fault injection; stable native identity/inventory crash-window recovery remains owned by Tasks 10/12/13.

### Task_9: Make create retry idempotent

- status: complete
- worker_thread: `019f4f15-56f9-7832-804e-01750602dfd7` (startup systemError; archived)
- replacement_worker_thread: `019f4f16-f94f-7d22-89d1-566e6293690d` (startup systemError; archived)
- final_startup_retry_thread: `019f4f18-4966-73e3-a353-c70c656da829` (startup systemError; archived)
- active_worker_thread: `019f5016-9021-7cf1-a44b-582db456009f`
- worker_branch: `codex/reviewfix-create-retry-idempotency-retry`
- worker_runtime: `gpt-5.6-luna` / `high`
- prior_blocker_resolved: the new user-visible Codex worktree thread started successfully and remained active beyond initial worktree setup; the three earlier startup failures made no product changes.
- pr: `#45` — https://github.com/xpadev-net/calarm/pull/45
- final_head: `c3c3a5ccd369b33cfcefc776d0eb417b91f32ca8`
- merge_commit: `5c02fa3a10aeb23bf9480460b3e60adb8cfa0fb1`
- worker_thread_archived: true
- worker_hook: 30 invocations exited 2; after two in-scope ringing fixes, invocations 3-30 repeated only the native-success/DB-persistence crash window owned by Tasks 10-13.
- orchestrator_hook: exit 0 in a clean exact-head worktree.
- type: impl
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `lib/features/wake_plan/ui/create_wake_plan_sheet.dart`
  - `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`
  - corresponding wake-plan service/UI/calendar tests
- depends_on: [Task_4, Task_8]
- acceptance:
  - Retrying from the same open sheet reuses one logical plan identity.
  - Full failure leaves no duplicate plan; partial failure retry creates at most one native reservation per occurrence.
  - Calendar invalidation displays one plan and truthful warning/recovery state.
  - Double-tap and delayed completion cannot race into duplicate saves.
- validation:
  - kind: command; required: true; owner: worker; detail: full/partial failure retry, double-submit, and stale-completion widget/service tests.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: idempotency and UI lifecycle review.
- review_evidence:
  - independent Reviewer `019f5036-1d03-7dd0-adaa-17b57ce64f36` APPROVED exact final head with no Blocker/High findings.
  - worker validation: 76 focused service/UI/calendar tests, `flutter analyze`, full 244-test suite, and diff check passed.
  - orchestrator validation: exact-head focused 76 tests, analyze, full 244 tests, and diff check passed in a clean temporary worktree.
  - orchestrator `$deep-review`: no Task_9 Blocker/High findings; retry identity, persisted reservation status, ringing state, concurrent create cleanup, locked-draft UI, lifecycle invalidation, and Task_8 compensation paths reviewed.
  - hosted Baseline CI, CodeRabbit, Greptile, and Socket checks passed; PR was non-draft, CLEAN, APPROVED, and base-current.
  - residual risk: native success followed by platform-ID persistence failure remains explicitly owned by Tasks 10-13 and was not expanded into Task_9.

### Task_10: Define an additive stable-ID and native inventory contract

- status: complete
- worker:
  - thread: `019f5163-90ad-73b1-bf48-682e01d52962`
  - worktree: `/Users/xpadev/.codex/worktrees/481c/calarm`
  - branch: `codex/reviewfix-native-inventory-contract`
  - runtime: `gpt-5.6-luna` / `high`
  - startup: completed and archived after merge.
  - pull_request: `#46`
  - final_head: `eb6f9bd737e717da8d2b6fca62d1f9901aeef024`
  - merge_commit: `18dfba3ae6eac6211040e12308c7f3d426d6f58e`
- type: design
- owns:
  - `lib/core/platform/native_alarm_gateway.dart`
  - `lib/core/platform/method_channel_native_alarm_gateway.dart`
  - `lib/core/platform/fake_native_alarm_gateway.dart`
  - `test/core/platform/**`
  - `docs/platform/native-alarm-channel.md`
- depends_on: [Task_9]
- acceptance:
  - The contract supports durable caller-correlatable native alarm identity before/through scheduling and an inventory/status read for reconciliation.
  - The extension is schema-versioned or additive so rolling deployment and platform implementation order are safe.
  - Unknown, missing, duplicate, corrupt, and extra native rows have explicit failure semantics.
  - Fake and MethodChannel implementations have parity tests.
  - If a safe additive contract cannot fit this scope, the worker stops before broad edits and requests decomposition with a compatibility plan.
- validation:
  - kind: command; required: true; owner: worker; detail: focused gateway contract tests and `flutter test test/core/platform`.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and full `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: cross-version contract and boundary validation review.
- review_evidence:
  - independent Reviewer APPROVED exact final head `eb6f9bd737e717da8d2b6fca62d1f9901aeef024` with no findings after the base-current merge.
  - worker validation: 56 focused platform tests, `flutter analyze`, full 265-test suite, format, and diff check passed.
  - orchestrator validation: exact-head focused 56 tests, analyze, full 265 tests, format, and diff check passed in a clean temporary worktree.
  - worker and orchestrator `gh-review-hook` runs exited 0; hosted Baseline CI, Android/iOS native smoke, CodeRabbit, Greptile, and Socket checks passed.
  - orchestrator `$deep-review`: no Blocker/High findings; additive rolling compatibility, boundary validation, duplicate/corrupt/unknown/missing/extra semantics, failure classification, pre-side-effect validation, and fake/MethodChannel parity were reviewed.
  - PR `#46` was non-draft, CLEAN, APPROVED, base-current, and squash-merged as `18dfba3ae6eac6211040e12308c7f3d426d6f58e`.

### Task_11: Implement native inventory/stable identity on Android

- status: complete
- worker:
  - thread: `019f5239-66a3-7ec0-af34-8f7442c4a58d`
  - worktree: `/Users/xpadev/.codex/worktrees/5d23/calarm`
  - branch: `codex/reviewfix-android-native-inventory`
  - runtime: `gpt-5.6-luna` / `high`
  - final_head: `cd6b129f86387b6ed0dbc23c8f01290e417c4ede`
  - pr: `#47` — https://github.com/xpadev-net/calarm/pull/47
  - merge_commit: `f3c6a880f2d8d44d6709c4b121918a17d8283d15`
  - thread_archived: true
- type: impl
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/**`
  - `android/app/src/main/AndroidManifest.xml` only if contract delivery requires it
  - `android/app/src/test/**`
  - `integration_test/native_alarm_smoke_test.dart` only for Android contract coverage
- depends_on: [Task_6, Task_10]
- acceptance:
  - Android accepts/preserves the contract identity and enumerates authoritative mirror/AlarmManager-correlatable state.
  - Inventory excludes expired/corrupt rows safely and reports mismatches without inventing success.
  - Schedule/cancel/inventory/reboot remain idempotent under duplicate calls.
  - Existing Android wake, notification, stop, vibration, and recovery behavior remains intact.
- validation:
  - kind: command; required: true; owner: worker; detail: focused native contract/recovery tests.
  - kind: command; required: true; owner: worker; detail: `flutter build apk --debug`, Android native smoke where environment permits, `flutter analyze`, `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: Android integration and mirror-authority review.
- review_evidence:
  - independent Reviewer `019f543e-07e8-73a1-95b3-4a5bf0eb9d82` APPROVED exact final head with no findings.
  - worker validation: native JVM 42 tests, focused 56 platform tests, full 265-test suite, `flutter analyze`, debug APK build, format, and diff check passed.
  - orchestrator validation: exact-head native JVM, focused 55 platform tests, full 265-test suite, `flutter analyze`, debug APK build, format, and diff check passed.
  - worker and orchestrator `gh-review-hook` runs exited 0; hosted Baseline CI, Android/iOS native smoke, CodeRabbit, Greptile, and Socket checks passed.
  - orchestrator `$deep-review`: no Blocker/High findings; stable/legacy/synthetic identity, persisted-data validation, inventory authority, retry/cancel/receiver/restore lifecycle, rollback cleanup, and regression coverage were reviewed.
  - PR `#47` was non-draft, CLEAN, APPROVED, base-current, and squash-merged as `f3c6a880f2d8d44d6709c4b121918a17d8283d15`.

### Task_12: Implement AlarmKit inventory and stop-state observation on iOS

- status: complete
- pr: `#48` — https://github.com/xpadev-net/calarm/pull/48
- final_head: `1c82eaf3beee35434d0f7e250bc26d9c459721b8`
- merge_commit: `2d3ceb1c786aa0b44e6da90457c164df6afbe11e`
- initial_worker:
  - thread: `019f5b6a-1df9-7392-93f9-9b5c6d87c2be`
  - worktree: `/Users/xpadev/.codex/worktrees/a8e4/calarm`
  - branch: `codex/reviewfix-ios-native-inventory`
  - runtime: `gpt-5.6-luna` / `high`
  - state: interrupted and archived after remaining at a clean detached base for over one hour; one startup resume produced no progress, and no branch, edit, commit, push, or PR was created.
- replacement_worker:
  - thread: `019f7575-c7db-7420-a088-2ba9cdd95d2d`
  - worktree: `<CODEX_HOME>/worktrees/1a9a/calarm`
  - branch: `codex/reviewfix-ios-native-inventory-retry`
  - runtime: platform default
  - startup: completed the availability-first handover, stale-inventory remediation, fail-closed cancellation, and exact-head regression closeout.
  - state: merge-ready handoff accepted; archived after orchestrator-owned merge.
- prior_replacement_worker:
  - thread: `019f6b02-c520-7601-a7f9-81447e8915d2`
  - worktree: `<CODEX_HOME>/worktrees/a266/calarm`
  - state: produced the bounded AlarmKit transition proof, then its rollout file disappeared after automatic archival; an unarchive/resume attempt could not resolve the rollout and the task was archived again before replacement.
- earlier_replacement_worker:
  - thread: `019f5bac-5671-7022-8a1a-12fa6cc67ee3`
  - worktree: `/Users/xpadev/.codex/worktrees/5a01/calarm`
  - state: archived rollout missing after unarchive; could not be resumed and was replaced without reusing its worktree.
- validation_support_task: Task_17
- current_reviewer:
  - thread: `019f5d9d-66b4-7272-87cd-dce0a97405d8`
  - exact_head: `988f712b3cf05e5381562037ccaf2bc08b5fefb3`
  - runtime: `gpt-5.6-luna` / `high`
  - state: active, read-only nineteenth review of the rollback-recovery remediation.
- type: impl
- owns:
  - `ios/Runner/AlarmKitBridge.swift`
  - `ios/Runner/AppDelegate.swift`
  - `ios/Runner/SceneDelegate.swift` only if lifecycle delivery requires it
  - `ios/RunnerTests/**`
  - `integration_test/native_alarm_smoke_test.dart` only for iOS contract coverage
- depends_on: [Task_1, Task_10, Task_17]
- acceptance:
  - AlarmKit uses/preserves the contract identity and exposes authoritative scheduled inventory.
  - Stable reservation-to-platform identity and production `supportsInventory`/`getInventory` routing let a downstream id-less pending-enable reconcile after lost MethodChannel replies without an uncancellable stranded alarm.
  - Replacement uses schedule-new-before-retire-old so at least one exact owned alarm remains scheduled; because the installed public AlarmKit interface has no atomic replace primitive, the bounded duplicate-delivery window is minimized, documented, and converges through old-alarm retirement or restart inventory reconciliation rather than being mislabeled impossible-to-guarantee no-duplicate behavior.
  - AlarmKit stop/removal changes become observable to Dart or are recoverable on the next inventory read.
  - Authorization denied, disappeared one-shot alarm, cancel, and corrupt/unknown identity have explicit semantics.
  - Result callbacks are delivered on a Flutter-safe execution context.
  - Backward compatibility with pre-release native mirror/journal formats and existing installed-state migrations is not required; Task_12 may use a current-schema-only reset/design, while still proving the current-schema replacement and recovery guarantees.
- validation:
  - kind: command; required: true; owner: worker; detail: focused Swift/contract tests and plist validation.
  - kind: command; required: true; owner: worker; detail: iOS simulator build/smoke when platform is installed; otherwise record exact BLOCKED evidence and require remote CI before merge.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: AlarmKit lifecycle/contract review.
- review_evidence:
  - worker validation at exact head `1c82eaf3beee35434d0f7e250bc26d9c459721b8`: focused ownership-guard XCTest 3/3, full RunnerTests 70/70 with zero skips, focused Flutter platform tests 64/64, full Flutter tests 359/359, `flutter analyze`, no-change Dart format, Swift parse, plist lint, and diff check passed.
  - orchestrator validation: iOS 26.5 simulator build passed; RunnerTests 70/70 with zero failures/skips; full Flutter tests 359/359, `flutter analyze`, no-change Dart format, Swift parse, plist lint, and diff check passed.
  - orchestrator `$deep-review`: boundary/ownership, failure/lifecycle, and tests/concurrency reviewers APPROVED the exact head with no findings; the pre/post replacement-journal ownership guards and current-schema pending cancellation are directly protected by production-seam regressions.
  - worker and orchestrator `gh-review-hook 48` runs exited 0; hosted Baseline, Android native smoke, iOS native smoke, CodeRabbit, Greptile, and both Socket checks passed; review-thread audit reported `hasNextPage=false` and no unresolved threads.
  - PR `#48` was non-draft, CLEAN, MERGEABLE, APPROVED, base-current, and squash-merged as `2d3ceb1c786aa0b44e6da90457c164df6afbe11e`.
  - residual risk: physical-device AlarmKit delivery remains unverified; simulator/MethodChannel evidence does not claim physical-device or release approval.

### Task_17: Execute iOS RunnerTests in hosted native smoke CI

- status: complete
- worker_thread: `019f5d9c-7f4d-7b11-91ce-86bdd55c99c4`
- worker_worktree: `/Users/xpadev/.codex/worktrees/da98/calarm`
- worker_branch: `codex/reviewfix-ios-runner-xctest-ci`
- worker_runtime: `gpt-5.6-luna` / `xhigh`
- pr: `#49` — https://github.com/xpadev-net/calarm/pull/49
- final_head: `88f71cccbe8795e8d947099a0aad7952e639768e`
- merge_commit: `5c347ef5451c2a741eb1b5be47beb12a289535c0`
- worker_thread_archived: true
- merge_evidence:
  - Fresh independent read-only Reviewer approved the exact final head with no findings.
  - Worker and orchestrator `gh-review-hook 49` both exited 0; the PR was non-draft, CLEAN, APPROVED, base-current, and all seven CI/AI/security checks completed successfully.
  - Hosted Native Smoke CI run `29295707807`, iOS job `86968612110`, and artifact `8296918421` prove `xcodebuild test -only-testing:RunnerTests` completed with `** TEST SUCCEEDED **` and both RunnerTests passed on the selected iOS 26.5 simulator.
  - Orchestrator `$deep-review` found no Blocker, High, or Suggestion; YAML parsing, embedded Bash syntax, trigger-path assertions, `git diff --check`, artifact retention, failure propagation, timeout bounds, and real-device disclaimer were independently verified.
- type: test
- owns:
  - `.github/workflows/native-smoke.yml`
- depends_on: [Task_1, Task_10]
- acceptance:
  - The hosted iOS native-smoke job compiles and executes `RunnerTests` through the checked-in Runner scheme on its selected compatible simulator.
  - XCTest compile, execution, assertion, and timeout failures fail the job and retain actionable logs under the existing native-smoke artifact layout.
  - Existing iOS simulator build and integration smoke remain required and real-device approval remains explicitly out of scope.
- validation:
  - kind: command; required: true; owner: worker; detail: YAML/action and embedded-shell validation plus `git diff --check`.
  - kind: command; required: true; owner: worker; detail: hosted PR evidence showing the RunnerTests target compiled and its XCTest suite executed successfully.
  - kind: review; required: true; owner: reviewer; detail: independent CI failure-semantics, simulator-destination, artifact, and scope review.

### Task_13: Reconcile Drift and native reservations durably

- status: complete
- worker: `019f85b5-34b1-7611-88f4-0970c1c24f05`
- branch: `codex/task-13-durable-inventory-reconciliation`
- pr: [#60](https://github.com/xpadev-net/calarm/pull/60)
- merged: `76a68c48e9d83c16a8e43503cd6f8bfce0f54fc6`
- type: impl
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart`
  - `lib/features/wake_plan/data/src/wake_plan_database.dart`
  - generated Drift output only when regeneration is required
  - `lib/core/bootstrap/app_bootstrap.dart`
  - `lib/app.dart` only if the existing startup/resume entry point cannot invoke the reconciliation pass
  - `docs/platform/native-alarm-channel.md` only for the durable authority/repair policy
  - corresponding repository/service/migration tests
- depends_on: [Task_7, Task_8, Task_9, Task_11, Task_12]
- acceptance:
  - Native success followed by process/DB failure is detected on restart and converges by adopting or cancelling the alarm safely.
  - DB-only scheduled rows and native-only alarms are repaired according to one documented authority/merge policy.
  - Reconciliation is idempotent across repeated startup/resume calls and survives corrupt/stale rows.
  - Any schema change uses expand-contract migration and remains rollback-aware.
- validation:
  - kind: command; required: true; owner: worker; detail: table-driven whole-inventory tests for exact match, DB-only, matching and unrelated native-only, stale ID, duplicate, conflict, corrupt, unavailable, and read-failure states.
  - kind: command; required: true; owner: worker; detail: fault-injection tests for every create/replenish native/DB interruption point, side-effect-then-throw, post-result persistence failure, per-plan continuation, file-backed reopen/restart, repeated lifecycle reconciliation, and migration if required.
  - kind: command; required: true; owner: worker; detail: `flutter analyze`, full `flutter test`, `flutter build apk --debug`.
  - kind: review; required: true; owner: reviewer; detail: data authority, migration, and failure-recovery review.

### Task_14: Reconcile native stop state and current-ringing selection

- status: complete
- replacement_tasks: [Task_18, Task_19, Task_20, Task_21]
- type: impl
- owns:
  - `lib/features/alarm_ringing/application/alarm_ringing_controller.dart`
  - `lib/features/alarm_ringing/presentation/alarm_ringing_placeholder.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart` only for the minimal ringing query/state operation
  - corresponding alarm-ringing and repository tests
- depends_on: [Task_13]
- acceptance:
  - A native/system stop becomes dismissed/expired in Drift on next event or reconciliation.
  - Stale overdue `scheduled` rows cannot mask a newer truly active alarm.
  - Current selection has a bounded, documented due window and deterministic ordering.
  - Stop remains retryable when native cancel/update fails and never dismisses the wrong occurrence.
- validation:
  - kind: command; required: true; owner: worker; detail: native-stop then reopen, stale-vs-current, multiple due, retry, and idempotent dismissal tests.
  - kind: command; required: true; owner: worker; detail: `flutter analyze` and `flutter test`.
  - kind: review; required: true; owner: reviewer; detail: lifecycle/state-selection review.

### Task_18: Consolidate wake service providers and mutation serialization

- status: complete
- worker: `019f862b-b771-7812-abbc-11d1381a08f8`
- branch: `codex/task-18-provider-coordinator-consolidation`
- pr: [#62](https://github.com/xpadev-net/calarm/pull/62)
- merged: `c64e2908b5f5b072995b087d1086a1033298d601`
- type: impl
- owns:
  - `lib/app.dart`
  - `lib/features/wake_plan/application/wake_plan_service_providers.dart`
  - `lib/features/week_calendar/presentation/week_calendar_placeholder.dart`
  - `lib/features/alarm_ringing/presentation/alarm_ringing_placeholder.dart`
  - `lib/features/wake_plan/application/wake_plan_service.dart` only for coordinator injection/removal of static coordination
  - `lib/features/alarm_ringing/application/alarm_ringing_controller.dart` only for shared coordinator serialization
  - corresponding app/calendar/ringing tests
- depends_on: [Task_13]
- acceptance:
  - App, calendar, and ringing features consume one session-scoped repository, gateway, wake service, clock, and mutation coordinator.
  - Ringing dismissal serializes with wake-plan mutations, with no static `Expando` coordination.
  - Riverpod overrides and existing lifecycle reconciliation remain testable and unchanged in behavior.
  - Only the provider/coordinator intent is salvaged from the dirty parent; calendar redesign and Task_14 event settlement are excluded.
- validation:
  - kind: command; required: true; owner: worker; detail: focused app, calendar, ringing-controller, and provider tests plus Dart format, `flutter analyze`, full `flutter test`, and debug APK build.
  - kind: review; required: true; owner: reviewer; detail: Riverpod lifetime/override, coordinator serialization, disposal, and Task_13 regression review.

### Task_19: Improve the Android ringing surface

- status: complete
- worker: `019f862b-b771-7812-abbc-11fc2331d678`
- branch: `codex/task-19-android-ringing-surface`
- pr: [#61](https://github.com/xpadev-net/calarm/pull/61)
- merged: `b4d7d47335c6c4b6eb3d440e4246c0935b6596e1`
- type: impl
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmReceiver.kt`
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmStopActivity.kt`
  - `android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt` only for ringing metadata and next-alarm lookup
  - `android/app/src/test/kotlin/dev/xpa/calarm/AlarmReceiverTest.kt`
- depends_on: [Task_13]
- acceptance:
  - Native full-screen and notification surfaces show wake target, alarm position, current/scheduled context, and next alarm when available.
  - Legacy persisted alarm rows remain readable and stopping still removes only the current alarm.
  - Vibration follows the request and is stopped on cleanup/recreation without adding event-journal behavior.
  - Notification content avoids unnecessary sensitive detail on the lock screen.
- validation:
  - kind: command; required: true; owner: worker; detail: focused Robolectric ringing/notification/storage tests, Android JVM tests, Dart format/diff check, and debug APK build.
  - kind: review; required: true; owner: reviewer; detail: lock-screen lifecycle, notification privacy/accessibility, vibration cleanup, backward decoding, and current-only stop review.

### Task_20: Add a durable Android native-alarm event journal and Dart contract

- status: complete
- worker: `019f866d-bce1-7113-b4bd-772eeff25583`
- branch: `codex/task-20-durable-native-event-journal`
- pr: [#63](https://github.com/xpadev-net/calarm/pull/63)
- merged: `2e7e8f5e9827d5f6deb2b2b5dcfe9a57c6460081`
- type: impl
- owns:
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmReceiver.kt` only for proven-delivery journal hooks
  - `android/app/src/main/kotlin/dev/xpa/calarm/AlarmStopActivity.kt` only for dismissal journal hooks
  - `android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt` only for event storage and channel handlers
  - `android/app/src/test/kotlin/dev/xpa/calarm/AlarmEventStoreTest.kt`
  - `lib/core/platform/native_alarm_gateway.dart`
  - `lib/core/platform/method_channel_native_alarm_gateway.dart`
  - `lib/core/platform/fake_native_alarm_gateway.dart`
  - `test/core/platform/method_channel_native_alarm_gateway_test.dart`
  - `docs/platform/native-alarm-channel.md` only for the additive event protocol
- depends_on: [Task_19]
- acceptance:
  - Delivered/dismissed events survive process death in device-protected storage; fetch is non-destructive and acknowledgement removes only named persisted events.
  - Delivery is recorded only after at least one native delivery path succeeds, never merely because delivery was attempted.
  - Duplicate IDs, bounded retention, corrupt rows, Direct Boot, malformed payloads, and old-plugin behavior are explicit and fail safely.
  - The additive Dart/Kotlin channel contract remains compatible with platforms that do not implement the event journal.
- validation:
  - kind: command; required: true; owner: worker; detail: focused Kotlin event/channel tests, Dart gateway tests, Android JVM suite, `flutter analyze`, full `flutter test`, and debug APK build.
  - kind: review; required: true; owner: reviewer; detail: durability, deduplication, retention/eviction, Direct Boot, schema compatibility, corruption, and destructive acknowledgement review.

### Task_21: Integrate native events with Task_13 reconciliation and current selection

- status: complete
- worker: `019f86ce-0831-7702-a013-8d516a62a98f`
- branch: `codex/task-21-native-event-reconciliation`
- pr: [#64](https://github.com/xpadev-net/calarm/pull/64)
- merged: `f06b8625521cf6ba1e48aa251f60f003af68f0f6`
- type: impl
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart` only for the minimal event/ringing query or transactional operation
  - `lib/features/alarm_ringing/application/alarm_ringing_controller.dart`
  - corresponding wake-plan repository/service and ringing-controller tests
- depends_on: [Task_18, Task_20]
- acceptance:
  - A native dismissal settles the exact Drift occurrence on reconciliation and acknowledgement happens only after durable persistence.
  - Repeated, duplicated, save-failed, or crash-interrupted event application converges idempotently without weakening Task_13 whole-inventory authority or corrupt-state protections.
  - Stale overdue scheduled rows cannot mask a newer active alarm; selection uses a bounded documented due window and deterministic ordering.
  - Cancel/update failure remains retryable and never dismisses the wrong occurrence.
- validation:
  - kind: command; required: true; owner: worker; detail: native-stop/reopen, save-failure-before-ack, duplicate/corrupt/unknown events, delivered-only/missed, stale-vs-current, multiple-due, retry, and lifecycle-repeat tests plus format, `flutter analyze`, full `flutter test`, and debug APK build.
  - kind: review; required: true; owner: reviewer; detail: Task_13 authority integration, state-machine correctness, selection window/order, crash seams, and exact-head deep review.

### Task_15: Final harmonization and repository-wide merge gate

- status: in progress
- reviewer: `019f8717-1e82-7dd2-80eb-9135c20cc291`
- review_verdict: CHANGES_REQUESTED
- type: review
- owns: []
- depends_on: [Task_5, Task_11, Task_12, Task_21, Task_22, Task_23, Task_24]
- acceptance:
  - All confirmed findings map to merged evidence and no cross-PR contract drift remains.
  - Dart/Android/iOS channel schemas, IDs, state transitions, docs, and tests agree.
  - Orchestrator deep-review returns APPROVED with no Blocker/High finding.
- validation:
  - kind: command; required: true; owner: orchestrator; detail: `dart format --output=none --set-exit-if-changed lib test integration_test`.
  - kind: command; required: true; owner: orchestrator; detail: `flutter analyze`, full `flutter test`, `flutter build apk --debug`, and `git diff --check`.
  - kind: review; required: true; owner: reviewer; detail: repository-wide `$deep-review` and orchestrator `gh-review-hook` evidence for every final PR.

### Task_22: Block edit recovery when native inventory is unavailable

- status: complete
- worker: `019f8724-ed66-7d90-8c12-a02c9c7e1ce0`
- branch: `codex/task-22-edit-recovery-authority`
- pr: [#66](https://github.com/xpadev-net/calarm/pull/66)
- merged: `7f5c3453cef397222005797cb2b830095ccee98c`
- type: impl
- owns:
  - `lib/features/wake_plan/application/wake_plan_service.dart`
  - `test/features/wake_plan/application/wake_plan_service_test.dart`
- depends_on: [Task_21]
- acceptance:
  - A restart after edited-plan persistence but before old-reservation retirement never schedules a replacement while native inventory is unavailable or non-authoritative.
  - The affected plan remains observably recovery-required without destructive repair; unrelated plans may continue only when their authority is independently safe.
  - An authoritative later pass deterministically retires/adopts the old identity and schedules the edited canonical bundle without duplicates.
- validation:
  - kind: command; required: true; owner: worker; detail: focused edit-crash/restart/unavailable/corrupt/read-failure and later-authoritative convergence tests, repeated/concurrent reconciliation, full Flutter tests, analyze, format, debug APK, and diff-check.
  - kind: review; required: true; owner: reviewer; detail: Task_13 authority, edit transaction crash seams, per-plan isolation, and idempotency review.

### Task_23: Make ringing dismissal durable across native-success persistence failure

- status: unstarted
- type: impl
- owns:
  - `lib/features/alarm_ringing/application/alarm_ringing_controller.dart`
  - `lib/features/wake_plan/data/src/wake_plan_repository.dart` only for a minimal exact-occurrence dismissal operation
  - `lib/features/wake_plan/data/src/wake_plan_database.dart` and generated output only if a schema change proves necessary
  - corresponding ringing-controller and repository tests
- depends_on: [Task_21]
- acceptance:
  - Native cancellation success followed by Drift failure/process loss converges on retry/reopen to the exact durable dismissed occurrence instead of missed/ringing.
  - Native cancellation failure remains retryable and does not prematurely or incorrectly dismiss another occurrence.
  - The solution is idempotent, serialized by the shared coordinator, and avoids schema change unless required; any schema change is additive and rollback-aware.
- validation:
  - kind: command; required: true; owner: worker; detail: cancellation-before-effect, native-success/DB-failure, side-effect-then-throw, retry, real Drift reopen, duplicate/current-selection, full Flutter tests, analyze, format, debug APK, and diff-check.
  - kind: review; required: true; owner: reviewer; detail: durable intent/effect ordering, compensation/replay, exact identity, concurrency, and migration review.

### Task_24: Unify stable reservation recreation identity across platforms

- status: in progress
- worker: `019f875e-00fb-7440-b136-51c70bad8c78`
- branch: `codex/task-24-stable-recreation-identity`
- type: impl
- owns:
  - `ios/Runner/AlarmKitBridge.swift`
  - `ios/RunnerTests/RunnerTests.swift`
  - `android/app/src/main/kotlin/dev/xpa/calarm/AndroidAlarmBridge.kt`
  - corresponding Android bridge tests
  - `lib/core/platform/native_alarm_gateway.dart`
  - `lib/core/platform/fake_native_alarm_gateway.dart`
  - `lib/core/platform/method_channel_native_alarm_gateway.dart` only if the wire contract changes
  - corresponding Dart gateway tests
  - `lib/features/wake_plan/application/wake_plan_service.dart` and its tests only for final reconciliation alignment after Task_22 merges
  - `docs/platform/native-alarm-channel.md`
- depends_on: [Task_22, Task_25]
- acceptance:
  - One documented reservation/occurrence identity rule governs iOS, Android, fake, Dart validation, and Task_13 reconciliation for recreated occurrences.
  - Side-effect/reply-loss and process-restart seams converge without silently accepting cross-plan ownership, duplicate logical identities, or corrupt tuples.
  - Existing exact cancellation, inventory ownership, and backward-compatible additive channel behavior remain intact.
- validation:
  - kind: command; required: true; owner: worker; detail: iOS RunnerTests, focused/full Android JVM tests, Dart gateway/service identity matrices, full Flutter tests, analyze, format, debug APK, Native Smoke CI, and diff-check.
  - kind: review; required: true; owner: reviewer; detail: cross-platform schema/identity parity, crash recovery, ownership/security, and compatibility review.

### Task_25: Add the hosted Android JVM test gate

- status: in progress
- worker: `client-new-thread:b02a6dc6-65a9-4283-a82a-d52b3c4aedbb`
- branch: `codex/task-25-hosted-android-jvm-gate`
- type: ci
- owns:
  - `.github/workflows/native-smoke.yml`
  - `docs/qa/ci-native-smoke.md` only if the executed gate/evidence contract needs documentation
- depends_on: [Task_22]
- acceptance:
  - GitHub Actions runs the complete Android `:app:testDebugUnitTest` suite for Android/native-contract pull requests and manual native-smoke dispatches.
  - A failing, timed-out, or skipped-required JVM suite prevents the Android native-smoke job from succeeding and retains actionable logs/artifacts.
  - The gate runs against the exact checked-out PR head, uses the repository Flutter/Android toolchain, and does not relabel emulator or JVM evidence as physical-device approval.
  - Task_24 can normally merge the workflow update, rerun exact-head CI, and satisfy its Android JVM acceptance without any local build.
- validation:
  - kind: command; required: true; owner: worker; detail: workflow/YAML/static shell validation that does not compile locally, followed by exact-head GitHub Actions execution proving the full Android JVM suite passes.
  - kind: review; required: true; owner: reviewer; detail: trigger/path coverage, failure propagation, timeout/logging, exact-head provenance, and non-duplication review.

### Task_16: Real-device release evidence

- status: blocked
- type: test
- owns:
  - `docs/qa/artifacts/**`
  - `docs/qa/release-readiness.md`
  - platform QA checklists
- depends_on: [Task_15]
- acceptance:
  - iOS 26+ real-device alarm authorization, delivery, lock/terminated, stop, cancel, multi-reservation, and cleanup pass.
  - Android API 36 real-device delivery, lock/terminated, full-screen, permission transitions, reboot/direct-boot restore, stop, cancel, multi-reservation, and cleanup pass.
- validation:
  - kind: manual; required: true; owner: user; detail: collect device logs/screenshots under `docs/qa/artifacts/` and update release-readiness truthfully.
- blocker: no real-device evidence is currently available; code workers must not waive or relabel this gate.

## Task Waves

- Wave 1A (baseline repair): [Task_4]
- Wave 1B (parallel, disjoint after the required full-test baseline is green): [Task_1, Task_2, Task_3, Task_5]
- Wave 2 (parallel after dependencies): [Task_6, Task_7]
- Wave 3 (sequential state mutations): [Task_8]
- Wave 4 (sequential idempotency): [Task_9]
- Wave 5 (contract foundation): [Task_10]
- Wave 6 (Android platform implementation): [Task_11]
- Wave 6A (Task_12 hosted XCTest validation support): [Task_17]
- Wave 6B (iOS platform implementation completion): [Task_12]
- Wave 7 (sequential durable reconciliation): [Task_13]
- Wave 8A (parallel dirty-WIP salvage): [Task_18, Task_19]
- Wave 8B (Android event journal after shared native UX files settle): [Task_20]
- Wave 8C (Task_13-aware event and ringing reconciliation): [Task_21]
- Wave 9A (parallel final-review remediation): [Task_22, Task_23]
- Wave 9B (hosted Android JVM gate): [Task_25]
- Wave 9C (cross-platform identity contract after Task_22 and Task_25): [Task_24]
- Wave 9D (orchestrator/reviewer): [Task_15]
- Wave 10 (user-owned): [Task_16]

## Worker Contract

- Every worker uses `gpt-5.6-luna` with `xhigh` reasoning in a separate Codex worktree and `codex/reviewfix-*` branch.
- Every worker loads repository instructions, `$task-pr-worker`, `$orchestration-harness`, `$engineering-quality-baselines`, `$git-workflow`, and `$deep-review` before editing.
- Every shell command is prefixed with `rtk`; no force push, history rewrite, broad cleanup, or other worker's changes.
- Workers perform bounded investigation before editing, use subagents when allowed, obtain independent review, create a PR, iterate `gh-review-hook` to exit 0, and never merge.
- A worker must report before stopping and must request decomposition before crossing `owns` or growing a broad diff.

## Rollback / Safety

- Merge small PRs in dependency order; revert a single PR rather than rewriting history.
- Keep cross-PR channel contracts coordinated until both native implementations and Dart consumers are merged; pre-release compatibility with superseded formats is not a requirement unless a task explicitly restores it.
- Task_12 may reset or replace legacy native mirror/journal state because the product is still in development; current-schema state transitions and recovery still require explicit policy and tests. Drift/data behavior outside Task_12 ownership is unchanged.
- Do not mark release readiness PASS without Task 16 evidence.

## Progress Log

- 2026-07-10 Plan created from whole-codebase deep-review findings.
  - Research waived using current source-grounded review evidence.
  - No open PRs were present; `master` matched `origin/master` except user-owned untracked `docs/coding-agent/reports/`.
  - Next action: merge this ledger-only plan, then dispatch Wave 1 with Luna ExtraHigh.

- 2026-07-10 Task_4 dispatched and startup-checked.
  - Worker thread: `019f4a0e-0e34-7193-b3ec-f42d6216acfb` in a separate worktree.
  - Branch/runtime: `codex/reviewfix-clock-injection` on `gpt-5.6-luna` / `xhigh` (Luna ExtraHigh).
  - Startup state: active; exact Task_4 goal set; skill loading and pre-edit failure reproduction in progress.
  - Next action: review and merge Task_4 only after worker and orchestrator gates pass, then dispatch Wave 1B in parallel.

- 2026-07-10 Task_4 completed and archived.
  - PR #35 merged as `a783c5d06d744b13ea981497e2bacfe28652575f`; final worker head `7681cecc3abd4c4c131e0e7d418d1a6182b8f528`.
  - Worker validation: both original regressions, both live-clock regressions, 11/11 week-calendar tests, 9/9 detail-sheet tests, format, analyze, full 202/202 suite, and diff check passed.
  - Review evidence: worker deep-review and fresh independent review APPROVED; mutation checks proved create/detail snapshot regressions fail; worker `gh-review-hook` exited 0 after four cumulative invocations.
  - Orchestrator evidence: UI/lifecycle and final test/time-boundary deep-review APPROVED; orchestrator `gh-review-hook` exited 0; both original and live-clock regressions, target files, format, analyze, full 202/202 suite, and diff check passed.
  - Hosted gates: Baseline CI, Greptile, and both Socket checks passed; PR was non-draft, CLEAN, APPROVED, and not behind at merge.
  - Worker thread `019f4a0e-0e34-7193-b3ec-f42d6216acfb` archived.
  - Next action: dispatch Wave 1B Tasks 1, 2, 3, and 5 in parallel with Luna ExtraHigh.

- 2026-07-10 Wave 1B dispatched and startup-checked.
  - Task_1: thread `019f4a5e-02ad-79b3-b0e3-d8c3bc7a4975`, branch `codex/reviewfix-ios-alarmkit-usage`.
  - Task_2: thread `019f4a5e-02b3-7ee1-9651-24f8ba408ca8`, branch `codex/reviewfix-android-alarm-intents-vibration`.
  - Task_3: thread `019f4a5e-055b-71a1-9303-822c6f507a14`, branch `codex/reviewfix-responsive-home`.
  - Task_5: thread `019f4a5e-0636-7351-b735-bbe84d41370e`, branch `codex/reviewfix-flutter-gitignore`.
  - All four workers use `gpt-5.6-luna` / `xhigh`, separate worktrees, non-overlapping ownership, and detailed validation/review/PR contracts.
  - Startup state: all four active beyond initial delegation; Task_1, Task_3, and Task_5 explicitly entered skill/tooling setup, and Task_2 remained active in onboarding.
  - Next action: independently gate and merge each ready PR; Task_6 waits for Task_2, Task_7 waits for Task_3, and Task_15 waits for Task_5 plus later platform work.

- 2026-07-10 Task_3 completed and archived.
  - PR #41 squash-merged as `0e3b4f5df3e1eeb279e98d0f2a74db1ccfe48ac2`; final worker head `3a481d39b923798fe09ea72915636481e4297183`.
  - Worker evidence: focused app/settings tests, full 205-test suite, format, analyze, diff check, independent UI review APPROVED, final `gh-review-hook` exit 0, and clean local/remote state.
  - Orchestrator evidence: responsive/error-state deep-review APPROVED with no Blocker/High finding; orchestrator `gh-review-hook 41` exited 0; 5/5 app scaffold tests and 5/5 settings tests passed; `flutter analyze`, diff check, hosted Baseline/Greptile/Socket checks, CLEAN merge state, and base-behind count 0 passed.
  - UI evidence: compact portrait and landscape reachability and compact provider-error behavior were proven by bounded Flutter widget tests; native/browser screenshots were unavailable and not claimed.
  - Worker thread `019f4a5e-055b-71a1-9303-822c6f507a14` was archived with the Codex session CLI after merge.
  - Next action: Task_7 is dependency-unblocked, but do not dispatch it until active Wave 1B ownership and available worker capacity are rechecked.

- 2026-07-10 Task_1 and Task_5 resume attempts stopped on the required runtime usage limit.
  - Sessions `019f4a5e-02ad-79b3-b0e3-d8c3bc7a4975` and `019f4a5e-0636-7351-b735-bbe84d41370e` were formally resumed with `gpt-5.6-luna` / `xhigh` and their existing worktrees.
  - Both sessions reported the same usage-limit stop before performing the required normal base merge; the UI reported retry availability at 2026-07-10 21:48 JST.
  - No model substitution, history rewrite, force push, worker replacement, or product-code change was performed.
  - Next action: after the runtime resets, resume the same two sessions to merge `origin/master` normally, revalidate the scoped diffs, rerun final-head hooks, and return merge-ready reports.

- 2026-07-10 Task_1 and Task_5 runtime limit cleared; resume authorized.
  - User confirmed the runtime limit recovered.
  - Both tasks returned to `in_progress`; the same sessions, worktrees, branches, and `gpt-5.6-luna` / `xhigh` runtime remain authoritative.
  - Next action: workers merge the current `origin/master` normally, refresh scoped validation and final-head hooks, and report merge-ready without merging.

- 2026-07-10 Task_1 completed and archived.
  - PR #38 squash-merged as `d97e245195d9f8f8f1f0bcb30f89214d13d65a76`; final worker head `73e03c1b5a2a139f63e76981e7edfc5d6a200320`.
  - Worker evidence: plist lint, analyze, full 205-test suite, diff check, final-head hook exit 0, six hosted gates, CLEAN/base-current state, and clean local/remote worktree.
  - Orchestrator evidence: privacy/configuration deep-review APPROVED with no Blocker/High finding; orchestrator hook exit 0; plist lint, analyze, full 205-test suite, diff check, CLEAN/base-current state, and clean worktree passed.
  - Local focused XCTest remained unavailable because the installed Xcode runtime lacked iOS 26.5; hosted iOS simulator smoke passed, and the deterministic XCTest source/configuration assertion was reviewed directly.
  - Worker thread `019f4a5e-02ad-79b3-b0e3-d8c3bc7a4975` was archived after merge.

- 2026-07-10 Task_2 and Task_5 completed and archived.
  - Task_2 PR #40 squash-merged as `c3d1986321cedfecf7936d848e8ad3f5cc0abfbb`; final worker head `01c7380c42d00287310249dfc4508d8648c7069b`.
  - Task_2 worker evidence: Java 21 native tests, analyze, all 205 Flutter tests, debug APK, diff check, hosted gates, and final hook exit 0. Orchestrator deep-review found no Blocker/High issue; parent hook exit 0 and the same validation matrix passed. Corrupt-row migration/recovery remains explicitly owned by Task_6.
  - Task_2 worker thread `019f4a5e-02b3-7ee1-9651-24f8ba408ca8` was archived after merge.
  - Task_5 PR #39 squash-merged as `826628fa7324222f4fb578ab60f2a2d5c67ce46b`; final worker head `87c9ffd644ee05c1ff8b74180d4bb5123aca21fb`.
  - Task_5 worker evidence: positive/negative ignore probes, diff check, analyze, all 205 tests, independent/deep review approval, hosted gates, and final hook exit 0. Orchestrator deep-review found no Blocker/High issue; parent hook exit 0 and direct over-ignore/base/cleanliness checks passed.
  - Task_5 worker thread `019f4a5e-0636-7351-b735-bbe84d41370e` was archived after merge.
  - Next action: Task_6 and Task_7 are dependency-unblocked and may be delegated in parallel after the ledger update is pushed.

- 2026-07-11 Wave 2 dispatched and startup-checked with Luna High.
  - Task_6: thread `019f4cd9-8741-75d3-9944-2fb899e496c5`, branch `codex/reviewfix-android-recovery`, dedicated worktree `/Users/xpadev/IdeaProjects/calarm-worktrees/reviewfix-android-recovery`.
  - Task_7: thread `019f4cd9-8755-7283-8189-f870a3fb92d8`, branch `codex/reviewfix-rolling-replenishment`, dedicated worktree `/Users/xpadev/IdeaProjects/calarm-worktrees/reviewfix-rolling-replenishment`.
  - Runtime policy changed to the user's current instruction: `gpt-5.6-luna` / `high` for both workers and future resumes/replacements.
  - Task_6 remained active beyond onboarding and entered repository/worker instruction loading.
  - Task_7 initially stopped before work because Luna was at capacity; the same thread was resumed once with Luna High and remained active beyond turn startup.
  - No product code was changed in the orchestrator checkout; user-owned untracked `docs/coding-agent/reports/` remains untouched.
  - Next action: wait for worker PR reports, then apply the independent orchestrator review, hook, validation, merge, ledger, and archival gates in dependency order.

- 2026-07-11 Wave 2 CLI dispatch corrected and archived.
  - User clarified that workers must be launched as Codex threads, not through `codex exec` CLI processes.
  - CLI sessions `019f4cd9-8741-75d3-9944-2fb899e496c5` and `019f4cd9-8755-7283-8189-f870a3fb92d8` were interrupted and archived.
  - Both dedicated worktrees remained clean at base `01e69ae`; no implementation commit or PR exists.
  - The active parent tool surface was checked for `create_thread`, `send_message_to_thread`, and related thread-management capabilities, but none are exposed.
  - Task_6 and Task_7 are blocked pending thread-management capability; CLI and internal-subagent substitution are prohibited.
  - Future default: task-pr workers are created only as user-visible Codex threads with the requested runtime.

- 2026-07-11 Wave 2 resumed with user-visible Codex threads.
  - The previously missing `create_thread` capability is now available, so the durable Task_6/Task_7 blocker is resolved.
  - Task_6: thread `019f4d61-3a43-7a90-97f9-0f78d1a14124`, branch `codex/reviewfix-android-recovery-thread`, Codex worktree `/Users/xpadev/.codex/worktrees/bf39/calarm`.
  - Task_7: thread `019f4d61-3a43-7a90-97f9-0f50eb5366d9`, branch `codex/reviewfix-rolling-replenishment-thread`, Codex worktree `/Users/xpadev/.codex/worktrees/b266/calarm`.
  - Both workers use `gpt-5.6-luna` / `high`, have disjoint ownership, and were active beyond initial worktree setup.
  - The old clean CLI worktrees and archived session references remain untouched for auditability; the new branches avoid worktree checkout conflicts.
  - Independent Reviewer threads will be orchestrator-created because the repository harness forbids nested worker subagents.
  - Next action: wait for review-ready or blocker reports, dispatch independent Reviewer threads, then continue each worker through PR/hook and orchestrator merge gates.

- 2026-07-11 Task_7 independent review requested changes at head `929264f777a81535cced3429515ca0140c51ef47`.
  - Reviewer thread `019f4d70-d0fe-7921-b3da-69e141c1e82a` found that concurrent reconciliation coalesces into one stale snapshot and can drop a necessary later pass; this remains in Task_7 scope and returns to the same worker.
  - Reviewer also confirmed the native-success/database-write crash window cannot be closed by Task_7's Dart-only ownership because iOS currently assigns an undiscoverable random native UUID on each schedule call.
  - That authority gap remains owned by the existing Task_10 stable-ID/inventory contract, Task_12 AlarmKit implementation, and Task_13 durable reconciliation/fault-injection work; Task_7 must not modify native/channel contracts or claim that crash window solved.
  - Next action: Task_7 implements a serialized dirty/follow-up pass with mutation/lifecycle tests, revalidates, and returns a new exact head for independent re-review before PR creation.

- 2026-07-11 Task_7 completed and archived.
  - PR #43 squash-merged as `dfaaf927d5b15858202f1fc6668fe32e757acef7`; final worker head `7c8432cdb25c905a0120960b90d160227d86f89d`.
  - Worker validation: focused wake-plan/app tests passed 108/108, `flutter analyze` passed, full Flutter suite passed 215/215, and diff check passed on the final head.
  - Review evidence: worker deep-review found no Blocker/High; independent Reviewer thread `019f4d81-31a3-7e11-95c8-eeb77bf14ee8` APPROVED the serialized follow-up design; worker hook fixed two later actionable findings and exited 0 on the final head.
  - Orchestrator evidence: merge preflight was non-draft, CLEAN, APPROVED, base-current, and all Baseline/Greptile/Socket checks passed; parent deep-review found no Blocker/High; parent `gh-review-hook 43` exited 0; focused 108/108 tests, analyze, full 215/215 tests, and diff check passed in a clean detached PR-head worktree.
  - Residual risk remains explicitly assigned to Tasks 10/12/13: native success followed by process/DB failure can duplicate an iOS alarm until stable identity, inventory, and durable adoption/cancellation recovery are implemented.
  - Non-blocking coverage suggestion remains recorded: terminal drain exception recovery and a request arriving specifically during the follow-up pass do not yet have direct regression tests.
  - Worker thread `019f4d61-3a43-7a90-97f9-0f50eb5366d9` was archived after merge.
  - The initial merge command completed the GitHub squash merge but returned exit 1 only because detached-worktree branch deletion could not resolve a current branch; post-command GitHub verification proved the merge commit above.
  - Next action: complete Task_6 merge gates; after Tasks 6 and 7 are both merged, dispatch dependency-ready Task_8 while respecting its shared WakePlanService ownership.

- 2026-07-11 Task_6 completed and archived.
  - PR #42 squash-merged as `67df3f795879f7dabf1c820d169f7627807f24d4`; final worker head `779daec2eb288c5d0fed5e6d93c2e84d3a87f06e`.
  - Worker validation: `flutter analyze` passed, full Flutter suite passed 215/215, debug APK build passed, manifest/source inspection and diff check passed, all seven hosted checks passed, and final `gh-review-hook 42` exited 0. Local direct Gradle unit execution was unavailable because the repository has no wrapper and no standalone Gradle; hosted Baseline reported Android unit tests 15/15 and Android native smoke passed.
  - Review evidence: independent Reviewer thread `019f4e40-478b-7751-9113-5ebb58eee020` APPROVED exact head with no Blocker/High; the stale CodeRabbit changes-requested review was dismissed with rationale after the current-head review found only non-blocking observations.
  - Orchestrator evidence: final preflight was non-draft, CLEAN, base-current, with no blocking review decision and all seven checks successful; parent deep-review found no Blocker/High; parent `gh-review-hook 42` exited 0; analyze, all 215 Flutter tests, debug APK build, and diff check passed in a clean detached PR-head worktree.
  - Residual risk: conflicting dual legacy rows without `updatedAtMillis` have no recoverable writer order. The deterministic fallback is documented and is not a supported base-to-head regression; choosing either storage domain as canonical would remain speculative. Real Android API 36 reboot/locked-boot/full-screen verification remains owned by Task_16.
  - Original worker thread `019f4d61-3a43-7a90-97f9-0f78d1a14124`, replacement worker thread `019f4dd2-951f-7551-b0a1-0995ed137340`, and independent Reviewer thread are archived after merge.
  - The merge command completed the GitHub squash merge but returned exit 1 only because the checked-out branch could not be deleted from the original sibling worktree; post-command GitHub verification proved the merge commit above.
  - Next action: dispatch dependency-ready Task_8 under the approved remediation plan.

- 2026-07-11 Task_8 completed and archived.
  - PR #44 squash-merged as `bbea05ef1c9b9df75a76f48c3d1815760cde81df`; final worker head `9b6058440e15999b24bd00ba95b71fe1cd1282ba`.
  - Worker validation: focused wake-plan service tests passed 43/43, `flutter analyze` passed, full Flutter suite passed 232/232, and diff check passed; scope remained the two owned files.
  - Review evidence: independent Reviewer `019f4f0c-14e9-7c11-9dae-84d19fbde74c` APPROVED exact head with no Blocker/High; the reviewer verified post-native persistence failures, truthful recovery state, compensation, cross-midnight metadata, canonical indexes, unmapped rows, and shared edit/delete/skip/undo behavior.
  - Orchestrator evidence: final preflight was non-draft, CLEAN, APPROVED, base-current, and all five hosted checks passed; parent deep-review found no Blocker/High; final-head `gh-review-hook 44` exited 0 in a clean temporary PR-head worktree; exact-head focused 43 tests, analyze, full 232 tests, and diff check passed.
  - Residual risk remains explicitly recorded: adapter-specific partial writes are not modeled by in-memory fault injection, and native-success/database-write crash-window recovery remains owned by Tasks 10/12/13.
  - Worker thread `019f4e4e-3915-7e02-b823-bba4a34dd31c` and Reviewer thread `019f4f0c-14e9-7c11-9dae-84d19fbde74c` were archived after merge.
  - The merge command returned exit 1 only because the worker branch could not be deleted from its active sibling worktree; GitHub verification proved the squash merge and no open PRs remain.
  - Next action: dispatch dependency-ready Task_9 while preserving the now-merged compensation semantics.

- 2026-07-11 Task_9 blocked at worker startup.
  - Initial thread `019f4f15-56f9-7832-804e-01750602dfd7` stopped with `systemError` before onboarding; one bounded resume stopped identically.
  - Replacement thread `019f4f16-f94f-7d22-89d1-566e6293690d` and final explicit Luna High startup retry `019f4f18-4966-73e3-a353-c70c656da829` also stopped with `systemError` before onboarding.
  - All three failed threads were archived; no worker edits, commits, pushes, PRs, or product changes occurred. Task_9 remains unstarted in substance and needs a future user-visible Codex thread/runtime recovery before implementation can proceed.

- 2026-07-13 Task_12 dispatched and startup-checked with Luna High.
  - Worker thread `019f5b6a-1df9-7392-93f9-9b5c6d87c2be` runs in Codex worktree `/Users/xpadev/.codex/worktrees/a8e4/calarm` on branch `codex/reviewfix-ios-native-inventory`.
  - The worker owns only the plan-defined iOS AlarmKit bridge/lifecycle/tests and optional iOS native smoke surface; Task_13/14 Dart and data reconciliation remain excluded.
  - Startup state: active beyond worktree creation with the required `gpt-5.6-luna` / `high` runtime and read-only independent Reviewer handoff contract.
  - Parent checkout remains product-code clean; user-owned untracked `docs/coding-agent/reports/` is preserved.
  - Next action: wait for the exact-head `REVIEW_READY` report, then create a fresh read-only Reviewer Codex worktree thread before permitting PR creation.

- 2026-07-13 Task_12 startup worker replaced after a non-progressing active turn.
  - Initial thread `019f5b6a-1df9-7392-93f9-9b5c6d87c2be` remained at clean detached base `97bd5ad` for over one hour with no tool activity, branch, edit, commit, push, or PR; one bounded Luna/High resume instruction did not start work.
  - The initial thread was interrupted and archived to prevent duplicate implementation.
  - Replacement thread `019f5bac-5671-7022-8a1a-12fa6cc67ee3` started in Codex worktree `/Users/xpadev/.codex/worktrees/5a01/calarm` on branch `codex/reviewfix-ios-native-inventory-retry` with `gpt-5.6-luna` / `high`.
  - Scope, validation, independent Reviewer handoff, no-merge contract, and parent product-code boundary remain unchanged.
  - Next action: wait for the replacement worker's exact-head `REVIEW_READY` report.

- 2026-07-14 Task_12 hosted XCTest validation split dispatched.
  - Independent review of PR #48 proved that `.github/workflows/native-smoke.yml` builds the iOS simulator app and runs the Flutter integration smoke but never invokes the Runner scheme TestAction, so hosted success did not execute `RunnerTests`.
  - Task_17 worker `019f5d9c-7f4d-7b11-91ce-86bdd55c99c4` started in separate worktree `/Users/xpadev/.codex/worktrees/da98/calarm` on branch `codex/reviewfix-ios-runner-xctest-ci` with `gpt-5.6-luna` / `xhigh`; ownership is only `.github/workflows/native-smoke.yml`.
  - Task_12 pushed rollback-recovery remediation head `988f712b3cf05e5381562037ccaf2bc08b5fefb3`; read-only Reviewer `019f5d9d-66b4-7272-87cd-dce0a97405d8` is reviewing that exact code head with Luna High.
  - PR #48 remains unmerged until Task_17 merges, Task_12 incorporates the updated base, the hosted RunnerTests gate passes, and all fresh exact-head worker/orchestrator gates pass.

- 2026-07-16 Task_12 open-PR worker replaced after archived rollout loss.
  - Existing worker thread `019f5bac-5671-7022-8a1a-12fa6cc67ee3` could be unarchived but could not be resumed because its archived rollout file was missing.
  - Replacement thread `019f6b02-c520-7601-a7f9-81447e8915d2` started in separate worktree `<CODEX_HOME>/worktrees/a266/calarm` on the existing branch `codex/reviewfix-ios-native-inventory-retry`.
  - The replacement must normally merge current `master`, remediate the two current AlarmKit correctness findings, rerun hosted iOS and exact-head review/hook gates, and never merge PR #48.

- 2026-07-17 Task_12 accepted the Task_2 native recovery prerequisite.
  - Exact-head Task_2 review proved that a lost iOS schedule reply can leave an id-less `userEnablePending` row while a live native alarm may exist; service-only retry is unsafe and rejecting the operation violates Task_2 acceptance.
  - Task_12 already owns the required AlarmKit stable identity, authoritative inventory, production routing, and native tests, so the prerequisite is added here instead of expanding PR #52 or creating a conflicting worker.
  - Required evidence now includes lost-reply/retry/restart stable identity, production `supportsInventory`/`getInventory` full-tuple authority, and downstream reconciliation without duplicate or stranded alarms. PR #52 remains stopped until PR #48 merges.

- 2026-07-18 Task_12 backward-compatibility constraint removed by user decision.
  - Legacy AlarmKit mirror/journal encodings, serialized envelopes, and installed-state migration paths no longer need preservation because the product is still in development.
  - Task_12 may adopt a clean current-schema-only design or reset legacy native state within its existing ownership; this does not authorize Dart service/database changes or unrelated scope expansion.
  - The decision does not waive current-schema correctness: authoritative inventory must be refreshed inside serialized pruning, and the supported AlarmKit design must still address process-death behavior around old/new alarm handover without assuming an atomic same-ID replacement primitive.
  - If the platform cannot eliminate both missed-fire and duplicate-fire windows, the worker must return a concrete proof and bounded product guarantee for orchestrator review rather than preserve compatibility-driven complexity.

- 2026-07-18 Task_12 adopted the supported availability-first AlarmKit handover guarantee.
  - The worker inspected the installed AlarmKit 26.5 public interface and found only per-ID schedule, cancel, stop, pause, resume, authoritative alarms, and alarm updates; it exposes no atomic replace/swap/transaction or initially-disabled creation primitive.
  - Finite transition proof: retiring the old alarm first admits process death with no live alarm and a missed fire; scheduling the candidate first admits process death with both alarms and a possible duplicate; journals and inventory cannot run while the process is dead, and undocumented same-ID replacement is forbidden.
  - Accepted current-platform guarantee: schedule the candidate before retiring the old alarm, preserve at least one exact owned alarm, minimize and document the duplicate window, then converge through old retirement or restart reconciliation. No Dart/database decomposition can create the missing OS atomic primitive.
  - Separate required remediation remains: observer/start events are wake hints, authoritative inventory is fetched inside `mirrorCoordinator` before every pruning path, read/validation failure retains state, and the post-journal second refetch plus gated stale-snapshot regressions remain mandatory.

- 2026-07-18 Task_12 worker replaced after post-report rollout loss.
  - Worker `019f6b02-c520-7601-a7f9-81447e8915d2` delivered the bounded transition proof and was automatically archived; its archived rollout file was then missing, so neither the accepted continuation prompt nor a bounded unarchive/resume could be delivered.
  - The unrecoverable task was archived again to prevent concurrent branch edits. Replacement worker `019f7575-c7db-7420-a088-2ba9cdd95d2d` started from the same existing PR branch in a fresh worktree and owns the same seven-file Task_12 scope.
  - The replacement was instructed to preserve all existing branch edits/history, normally merge current master, implement the recorded availability-first and stale-inventory fixes, refresh every exact-head gate, and never merge or rewrite history.

- 2026-07-22 Task_13 acceptance audit completed and bounded implementation started.
  - Read-only audit thread `019f85aa-b3a7-7b51-aa01-3c96ff760455` reviewed exact `origin/master` `6e2cd80e100a08b96c02ba78f4703ab985415026` and returned `NARROW_DELTA_REQUIRED`; it was archived after reporting.
  - Audit validation passed focused 145/145 tests, full 446/446 tests, `flutter analyze`, debug APK build, and `git diff --check` from a clean worktree.
  - Existing occurrence-toggle recovery and reconciliation serialization are retained, but Task_13 remains incomplete because ordinary scheduled rows are not compared with one authoritative native inventory snapshot and the required general create/replenish interruption matrix is absent.
  - Implementation worker `019f85b5-34b1-7611-88f4-0970c1c24f05` started and passed the startup stability check on `codex/task-13-durable-inventory-reconciliation`.
  - Scope is limited to Task_13's service/repository/database/bootstrap/tests plus the narrow authority-policy documentation and conditional app entry point recorded above. Task_14 ringing/native-stop work and the dirty parent checkout remain excluded.
  - Next action: startup-check the worker, require exact-head independent review, PR/hook/check gates, and orchestrator-owned review/tests before merge.

- 2026-07-22 Task_13 durable reconciliation completed and merged.
  - PR [#60](https://github.com/xpadev-net/calarm/pull/60) merged exact approved head `859c3e9f830ed51d6cc91b29b562624f81acb088` into `master` as `76a68c48e9d83c16a8e43503cd6f8bfce0f54fc6` without history rewrite.
  - The final implementation compares one transactional eligible Drift snapshot with one authoritative native inventory, adopts exact stable identities, repairs authoritative DB-only absence, cancels exact owned stale alarms, and blocks corrupt, conflicting, duplicate, inactive, or unavailable state fail-closed while unrelated safe plans continue.
  - Fresh independent exact-head review approved the final post-hook head with no findings. Worker and orchestrator `gh-review-hook 60` both exited 0; the PR was non-draft, CLEAN, APPROVED, base-current, and all Baseline CI, Greptile, CodeRabbit, and Socket checks succeeded.
  - Orchestrator validation passed the service/repository suites 155/155, full Flutter suite 472/472, `flutter analyze`, debug APK build, Dart format 61 files/0 changed, and `git diff --check` from a clean detached PR-head worktree.
  - No schema, startup wiring, native-platform, ringing, UI, or calendar changes were included. Task_14 remains the next dependent task and requires ownership attribution/replanning against the dirty parent WIP before dispatch.

- 2026-07-22 Task_14 dirty-WIP audit completed and replacement tasks defined.
  - Read-only inspection classified the implementation intent as valid but found four mixed concerns authored against pre-Task_13 `master`: provider/coordinator consolidation, Android ringing UX, durable Android event journal, and Task_13-aware event/ringing reconciliation.
  - Task_14 is split into Task_18 through Task_21 so low-conflict provider and Android UX work can proceed independently before shared Android journal and Dart reconciliation waves.
  - The dirty parent remains unchanged. Calendar drafts, historical plans/reports, device artifacts, and the destructive lessons-log replacement are excluded from product workers; no whole dirty path is deleted as disposable.
  - Next action: dispatch Task_18 and Task_19 from current `origin/master`, using the dirty checkout only as read-only source material and requiring fresh implementation against current code.

- 2026-07-22 Task_18 provider/coordinator consolidation completed and merged.
  - PR [#62](https://github.com/xpadev-net/calarm/pull/62) merged exact approved head `368758956807f0a82c9d7f50976227379e1962a0` as `c64e2908b5f5b072995b087d1086a1033298d601`.
  - Session-scoped Riverpod providers now share one repository, native gateway, clock, wake service, and explicit mutation coordinator across app, calendar, and ringing paths; the static `Expando` coordination was removed.
  - Fresh exact-head review approved with no findings. Worker and orchestrator `gh-review-hook 62` exited 0; hosted Baseline CI, Greptile, CodeRabbit, and Socket checks succeeded with CLEAN, base-current merge state.
  - Orchestrator validation passed focused 193/193 tests, full Flutter 479/479, `flutter analyze`, format 63 files/0 changed, debug APK build, and `git diff --check`.
  - Worker thread `019f862b-b771-7812-abbc-11d1381a08f8` is archived. Task_19 remains the other active Wave 8A task; Task_20 waits for its merge.

- 2026-07-22 Task_19 Android ringing surface completed and Task_20 started.
  - PR [#61](https://github.com/xpadev-net/calarm/pull/61) merged exact approved head `9251920a7da8cfac4d1f678a8e81e026c9e398e6` as `b4d7d47335c6c4b6eb3d440e4246c0935b6596e1`.
  - The native full-screen/private notification now exposes scheduled/current context, wake target, alarm position, and deterministic next same-plan alarm while the public lock-screen notification remains redacted; exact current-only stop and legacy row decoding are preserved.
  - Fresh exact-head review approved with no findings. Worker and orchestrator `gh-review-hook 61` exited 0; Baseline CI, Android/iOS native smoke, Greptile, CodeRabbit, and Socket checks all succeeded with CLEAN, base-current merge state.
  - Orchestrator validation passed focused Robolectric `AlarmReceiverTest` 21/21, full Android `:app:testDebugUnitTest`, debug APK, format 63 files/0 changed, and `git diff --check`. The clean worktree first lacked ignored `android/local.properties`; Flutter APK generation restored the local prerequisite and the required native tests then passed.
  - Worker `019f862b-b771-7812-abbc-11fc2331d678` is archived. Task_20 worker `019f866d-bce1-7113-b4bd-772eeff25583` started from current `origin/master` and owns only the durable event journal/channel contract wave.

- 2026-07-22 Task_20 durable native event journal completed and Task_21 started.
  - PR [#63](https://github.com/xpadev-net/calarm/pull/63) merged exact approved head `77f68c0bb59545908ba577950dc31bc649c3b13c` as `2e7e8f5e9827d5f6deb2b2b5dcfe9a57c6460081`.
  - Android now persists delivered/dismissed events synchronously in device-protected storage with non-destructive fetch, exact acknowledgement, deterministic dedupe/order/cap, corrupt-row handling, and rollback-safe future-schema isolation; the additive Dart gateway contract preserves old-plugin behavior.
  - Fresh exact-head review approved with no findings after multiple durability fixes. Worker and orchestrator `gh-review-hook 63` exited 0; Baseline CI, Android/iOS native smoke, Greptile, CodeRabbit, and Socket checks all succeeded with CLEAN, base-current merge state.
  - Orchestrator validation passed focused Kotlin event/receiver 32/32, full Android `:app:testDebugUnitTest`, focused Dart gateway 31/31, full Flutter 487/487, `flutter analyze`, debug APK, format 63 files/0 changed, and `git diff --check`.
  - Worker `019f866d-bce1-7113-b4bd-772eeff25583` is archived. Task_21 worker `019f86ce-0831-7702-a013-8d516a62a98f` started from current `origin/master` for the final Task_13-aware event/ringing reconciliation wave.

- 2026-07-22 Task_21 native event reconciliation completed and Task_14 closed.
  - PR [#64](https://github.com/xpadev-net/calarm/pull/64) merged exact approved head `a0f07f619a6ecd651c6aaa1c706bbfc88637845e` as `f06b8625521cf6ba1e48aa251f60f003af68f0f6`.
  - Native delivered/dismissed events now settle exact Drift occurrences only after authoritative inventory and unambiguous persisted identity checks; persistence precedes acknowledgement, replay is idempotent, and ambiguous/corrupt events remain durable and unapplied.
  - Ringing selection now uses a bounded 15-minute window with deterministic newest-first ordering, while stale rows cannot mask a current alarm and exact dismissal remains serialized and retryable.
  - Fresh exact-head review approved with no findings. Worker and orchestrator `gh-review-hook 64` exited 0; Baseline CI, Android/iOS native smoke, Greptile, CodeRabbit, and Socket checks succeeded with CLEAN, base-current merge state.
  - Orchestrator validation passed focused service/repository/ringing tests 180/180, full Flutter 503/503, `flutter analyze`, debug APK, format 6 files/0 changed, and `git diff --check` from a clean detached PR-head worktree.
  - Task_14 and replacement Tasks 18-21 are complete. Task_15 final harmonization is now in progress; Task_16 remains blocked on real-device evidence.

- 2026-07-22 Task_15 exact-master harmonization review requested remediation.
  - Read-only reviewer `019f8717-1e82-7dd2-80eb-9135c20cc291` reviewed exact `origin/master` `f25dd96832d06dc0b7e4c7c54142a7137e256dba` and returned `CHANGES_REQUESTED` after format, analyze, 503/503 Flutter tests, debug APK, diff-check, and clean-tree verification.
  - Blocker: restart after edited-plan persistence can schedule a new stable identity while native inventory is unavailable, leaving the old native alarm live. Task_22 owns the narrow authority/restart fix.
  - High: native dismissal success followed by Drift failure can lose the exact dismissed transition. Task_23 owns durable dismissal ordering and replay.
  - High: stable reservation recreation semantics differ across iOS, Android, fake, and Dart reconciliation. Task_24 owns the cross-platform contract after Task_22 settles shared service ownership.
  - Task_22 and Task_23 may proceed in parallel. Task_24 waits for Task_22; Task_15 re-runs only after all three merge. Task_16 remains blocked on physical-device evidence.

- 2026-07-22 Task_22 edit-recovery authority fix completed and Task_24 started.
  - PR [#66](https://github.com/xpadev-net/calarm/pull/66) merged exact approved head `8f323a32fa9a4893728c9e6cea06bf4dc4b3ed4b` as `7f5c3453cef397222005797cb2b830095ccee98c`.
  - Non-authoritative inventory now blocks only affected edited plans whose noncanonical persisted rows may retain native ownership; later authoritative reconciliation retires the old identity before canonical scheduling. Terminal event identity is retained until journal acknowledgement succeeds.
  - Fresh exact-head review approved with no findings. Worker and orchestrator `gh-review-hook 66` exited 0; Baseline CI, Greptile, CodeRabbit, and Socket checks passed with CLEAN, base-current merge state.
  - Orchestrator validation passed focused service 143/143, full Flutter 507/507, `flutter analyze`, debug APK, format 2 files/0 changed, and `git diff --check` from a clean detached PR-head worktree.
  - Task_22 worker is archived. Task_24 is dispatched from the merged base for the cross-platform stable recreation identity contract; Task_23 continues independently.

- 2026-07-22 Task_24 requested CI ownership decomposition for Android JVM evidence.
  - The user disabled local build/compile-heavy validation because the local battery is failing; required evidence moved to exact-head GitHub Actions without waiving a gate.
  - Task_24 proved the official workflows cover Flutter/analyze, debug APK, iOS RunnerTests, and native smoke, but no workflow runs the complete Android `:app:testDebugUnitTest` suite.
  - Task_25 exclusively owns the narrow workflow update. Task_24 remains not merge-ready at PR [#67](https://github.com/xpadev-net/calarm/pull/67) head `4a40b9a` until Task_25 merges and exact-head CI supplies the missing Android JVM evidence.

## Decision Log

- 2026-07-22 Decision: split dirty Task_14-related WIP into four sequentially safe replacement tasks.
  - Trigger: the dirty parent contains 17 modified tracked files and untracked source mixed across provider wiring, Android UX, native journaling, Dart reconciliation, calendar work, documentation, and device evidence; PR #60 substantially rewrote the overlapping service/repository/tests.
  - Plan delta: Task_14 becomes `split in progress`; Task_18 and Task_19 are parallel, Task_20 follows Task_19 on shared Android files, and Task_21 follows Task_18 and Task_20 on Task_13-aware reconciliation.
  - Tradeoffs considered: a single salvage PR would be faster to stage but unsafe to review and likely to reverse Task_13 invariants; discarding the WIP would lose coherent tested intent.
  - User approval: yes; the user directed inspection, cleanup only when unnecessary, and commit/PR for valid changes.

- 2026-07-18 Decision: pre-release backward compatibility is not required for Task_12 native state.
  - Trigger: the user explicitly stated that the product is under development and backward compatibility is unnecessary.
  - Scope effect: PR #48 may remove legacy native mirror/journal decoding and migration behavior and use current-schema-only state, but remains within Task_12 ownership.
  - Non-waiver: AlarmKit's non-atomic schedule/cancel boundary and stale-inventory race remain correctness requirements independent of serialization compatibility.
  - Default if platform proof shows both delivery guarantees cannot coexist: return the evidence and a narrow availability-first recommendation with the duplicate window minimized and documented; do not silently weaken acceptance.
  - User approval: explicit on 2026-07-18.

- 2026-07-18 Decision: prefer no missed fire over an impossible current-platform no-duplicate guarantee.
  - Trigger: the Task_12 bounded interface inspection and transition matrix proved that every supported two-call AlarmKit replacement ordering has one process-death intermediate state, and no atomic replacement primitive exists in the installed public API.
  - Scope effect: Task_12 stays within its seven approved files and implements schedule-new-before-retire-old plus authoritative restart convergence; no Dart/database task is added because it cannot alter native process-death atomicity.
  - Acceptance delta: remove the absolute no-duplicate claim, require a minimized/documented duplicate window, forbid unsupported same-ID replacement assumptions, and retain all exact-identity, ownership, inventory, and cleanup guarantees.
  - Revisit condition: strengthen the guarantee only when a supported AlarmKit atomic replace/swap primitive becomes available and is covered by native tests.
  - User approval: follows the explicitly recorded availability-first default after the user removed compatibility constraints; no additional scope or destructive action is introduced.

- 2026-07-14 Decision: split the missing hosted RunnerTests execution gate into Task_17 before Task_12 can merge.
  - Trigger: the Task_12 worker and nineteenth-review preparation confirmed that the iOS native-smoke job does not run `xcodebuild test`; the checked-in RunnerTests therefore lacked the plan-required remote execution evidence.
  - Plan delta: Task_17 exclusively owns `.github/workflows/native-smoke.yml`; Task_12 now depends on Task_17 and must update to the resulting base before final review and merge gates.
  - Tradeoff: one small prerequisite CI PR and an additional base update for PR #48, in exchange for keeping workflow ownership out of the already large AlarmKit product PR and obtaining executable Swift regression evidence.
  - User approval: covered by the user's standing instruction to decompose cross-ownership work into separate user-visible workers and enforce every required validation gate.

- 2026-07-11 Decision: keep Task_7 narrow and route the native crash-window authority gap through Tasks 10, 12, and 13.
  - Trigger: independent review proved that a native schedule can succeed before the platform ID is persisted, and the unchanged iOS bridge generates a new UUID per call.
  - Evidence: Task_13 already requires recovery from native success followed by process/DB failure, while Tasks 10 and 12 establish the stable identity and AlarmKit inventory needed to make that recovery possible.
  - Scope effect: Task_7 remains responsible for rolling-horizon normal-path idempotency and non-dropping serialized reconciliation; it does not expand into native/channel ownership.
  - Tradeoff: the current PR can remain bounded and reviewable, while the known crash-window duplicate risk remains explicitly unapproved until Task_13 merges.
  - User approval: covered by the previously approved dependency-ordered remediation plan; this clarifies existing ownership rather than adding or waiving work.

- 2026-07-10 Decision: split cross-platform state repair into additive contract, platform implementation, durable reconciliation, and ringing reconciliation.
  - Trigger: a single fix would span Dart, Drift, Android, iOS, lifecycle, migrations, and UI state.
  - Tradeoff: more PRs and sequential waves in exchange for bounded ownership, rollback safety, and reviewable contracts.
  - User approval: yes; user explicitly requested orchestration, detailed Luna ExtraHigh workers, and decomposition of complex tasks.

- 2026-07-10 Decision: keep real-device release evidence blocked and user-owned.
  - Trigger: existing release-readiness requires physical iOS 26+ and Android API 36 evidence.
  - Tradeoff: code remediation can complete while normal MVP release remains blocked.
  - User approval: inherited from existing release gate; no waiver requested.

- 2026-07-10 Decision: run Task_4 before the remaining Wave 1 tasks.
  - Trigger: the repository-wide `flutter test` baseline currently fails on the two clock-dependent tests, so parallel workers could not satisfy their required full-suite merge gate.
  - Plan delta: Task_4 now owns the detail-sheet clock propagation path; Tasks 1, 2, 3, and 5 depend on Task_4 for validation readiness.
  - Tradeoff: one short sequential PR before parallel work prevents every other worker from carrying and later rebasing around the same known red baseline.
  - User approval: covered by the user's instruction to split clearly complex work and proceed autonomously.
