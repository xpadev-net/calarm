import 'dart:io';

import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late WakePlanDatabase database;
  late WakePlanRepository repository;

  final monday = CalendarDay(year: 2026, month: 7, day: 6);
  final tuesday = CalendarDay(year: 2026, month: 7, day: 7);
  final saturday = CalendarDay(year: 2026, month: 7, day: 11);
  final targetTime = TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0);
  final now = DateTime(2026, 7, 6, 8);

  setUp(() {
    database = WakePlanDatabase(NativeDatabase.memory());
    repository = WakePlanRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  WakePlan buildPlan({
    String id = 'plan-1',
    RepeatRule? repeatRule,
    bool isEnabled = true,
    WakePlanStatus status = WakePlanStatus.scheduled,
    CalendarDay? skipNextDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WakePlan(
      id: id,
      title: 'Weekday wake up',
      targetTime: targetTime,
      startOffset: const Duration(minutes: 60),
      interval: const Duration(minutes: 5),
      repeatRule: repeatRule ?? RepeatRule.oneTime(monday),
      isEnabled: isEnabled,
      status: status,
      skipNextDate: skipNextDate,
      soundId: 'default',
      vibrationEnabled: true,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  AlarmOccurrence buildOccurrence({
    String id = 'occ-1',
    String wakePlanId = 'plan-1',
    CalendarDay? day,
    TimeOfDayMinutes? time,
    AlarmOccurrenceStatus status = AlarmOccurrenceStatus.scheduled,
    String? platformAlarmId,
    DateTime? firedAt,
    DateTime? updatedAt,
  }) {
    return AlarmOccurrence(
      id: id,
      wakePlanId: wakePlanId,
      scheduledAt: DateMinute(day: day ?? monday, time: time ?? targetTime),
      status: status,
      platformAlarmId: platformAlarmId,
      firedAt: firedAt,
      createdAt: now,
      updatedAt: updatedAt ?? now,
    );
  }

  group('schema', () {
    test('starts at migration version 2', () {
      expect(database.schemaVersion, 2);
      expect(database.migration, isNotNull);
    });

    test('migrates version 1 rows with no pending dismissal', () async {
      await database.close();
      final directory = await Directory.systemTemp.createTemp(
        'calarm-dismissal-migration-',
      );
      final file = File('${directory.path}/wake-plan.sqlite');
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('''
        CREATE TABLE alarm_occurrence_rows (
          id TEXT NOT NULL PRIMARY KEY,
          wake_plan_id TEXT NOT NULL,
          scheduled_at_days INTEGER NOT NULL,
          scheduled_at_minutes INTEGER NOT NULL,
          status TEXT NOT NULL,
          platform_alarm_id TEXT,
          fired_at INTEGER,
          dismissed_at INTEGER,
          failure_reason TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      legacy.execute(
        'INSERT INTO alarm_occurrence_rows '
        '(id, wake_plan_id, scheduled_at_days, scheduled_at_minutes, status, '
        'platform_alarm_id, created_at, updated_at) '
        "VALUES ('legacy-occ', 'legacy-plan', 20640, 410, 'scheduled', "
        "'legacy-native', 0, 0)",
      );
      legacy.execute('PRAGMA user_version = 1');
      legacy.dispose();

      final migratedDatabase = WakePlanDatabase(NativeDatabase(file));
      final migratedRepository = WakePlanRepository(migratedDatabase);
      try {
        final occurrence = await migratedRepository.fetchAlarmOccurrence(
          'legacy-occ',
        );

        expect(occurrence, isNotNull);
        expect(occurrence!.platformAlarmId, 'legacy-native');
        expect(
          await migratedRepository.fetchPendingAlarmOccurrenceDismissals(),
          isEmpty,
        );
      } finally {
        await migratedDatabase.close();
        await directory.delete(recursive: true);
      }
    });

    test(
      're-upgrades after rollback leaves additive columns in place',
      () async {
        await database.close();
        final directory = await Directory.systemTemp.createTemp(
          'calarm-dismissal-reupgrade-',
        );
        final file = File('${directory.path}/wake-plan.sqlite');
        var upgradedDatabase = WakePlanDatabase(NativeDatabase(file));
        var upgradedRepository = WakePlanRepository(upgradedDatabase);
        await upgradedRepository.saveWakePlan(buildPlan());
        await upgradedRepository.saveAlarmOccurrences([
          buildOccurrence(platformAlarmId: 'native-exact'),
        ]);
        await upgradedRepository.prepareAlarmOccurrenceDismissal(
          occurrenceId: 'occ-1',
          expectedPlatformAlarmId: 'native-exact',
          requestedAt: DateTime(2026, 7, 6, 8, 1),
        );
        await upgradedDatabase.close();

        final rolledBack = sqlite.sqlite3.open(file.path);
        rolledBack.execute('PRAGMA user_version = 1');
        rolledBack.execute(
          "UPDATE alarm_occurrence_rows SET updated_at = 1 WHERE id = 'occ-1'",
        );
        rolledBack.dispose();

        upgradedDatabase = WakePlanDatabase(NativeDatabase(file));
        upgradedRepository = WakePlanRepository(upgradedDatabase);
        try {
          final pending = await upgradedRepository
              .fetchPendingAlarmOccurrenceDismissal('occ-1');

          expect(pending, isNotNull);
          expect(pending!.platformAlarmId, 'native-exact');
          expect(pending.occurrence.status, AlarmOccurrenceStatus.scheduled);
        } finally {
          await upgradedDatabase.close();
          await directory.delete(recursive: true);
        }
      },
    );
  });

  group('wake plans', () {
    test('saves, updates, and fetches a plan by id', () async {
      final plan = buildPlan(
        repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
      );

      await repository.saveWakePlan(plan);
      await repository.saveWakePlan(plan.copyWith(title: 'Updated wake up'));

      final fetched = await repository.fetchWakePlan('plan-1');

      expect(fetched, isNotNull);
      expect(fetched!.id, 'plan-1');
      expect(fetched.title, 'Updated wake up');
      expect(fetched.repeatRule, plan.repeatRule);
      expect(fetched.targetTime, plan.targetTime);
      expect(fetched.startOffset, plan.startOffset);
      expect(fetched.interval, plan.interval);
      expect(fetched.soundId, plan.soundId);
      expect(fetched.vibrationEnabled, isTrue);
    });

    test('round-trips one-time repeat rules', () async {
      final plan = buildPlan();

      await repository.saveWakePlan(plan);

      final fetched = await repository.fetchWakePlan('plan-1');

      expect(fetched, isNotNull);
      expect(fetched!.repeatRule, RepeatRule.oneTime(monday));
    });

    test('fetches plans needed for a calendar range', () async {
      await repository.saveWakePlan(
        buildPlan(
          id: 'weekday',
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        ),
      );
      await repository.saveWakePlan(
        buildPlan(id: 'saturday', repeatRule: RepeatRule.oneTime(saturday)),
      );
      await repository.saveWakePlan(
        buildPlan(
          id: 'disabled',
          repeatRule: RepeatRule.weekly({Weekday.monday}),
          isEnabled: false,
        ),
      );

      final plans = await repository.fetchWakePlansForCalendarRange(
        start: monday,
        end: tuesday,
      );

      expect(plans.map((plan) => plan.id), ['weekday']);
    });

    test(
      'can include disabled plans in calendar range for debug/history views',
      () async {
        await repository.saveWakePlan(
          buildPlan(
            id: 'disabled',
            repeatRule: RepeatRule.weekly({Weekday.monday}),
            isEnabled: false,
          ),
        );

        final plans = await repository.fetchWakePlansForCalendarRange(
          start: monday,
          end: tuesday,
          includeDisabled: true,
        );

        expect(plans.map((plan) => plan.id), ['disabled']);
      },
    );

    test(
      'soft-deletes plans without returning them in normal fetches',
      () async {
        await repository.saveWakePlan(buildPlan());

        await repository.softDeleteWakePlan(
          id: 'plan-1',
          updatedAt: DateTime(2026, 7, 6, 9),
        );

        expect(await repository.fetchWakePlan('plan-1'), isNull);

        final deleted = await repository.fetchWakePlan(
          'plan-1',
          includeDeleted: true,
        );
        expect(deleted, isNotNull);
        expect(deleted!.status, WakePlanStatus.deleted);
        expect(deleted.isEnabled, isFalse);
      },
    );

    test('reports missing plans when soft-deleting', () async {
      expect(
        () => repository.softDeleteWakePlan(
          id: 'missing',
          updatedAt: DateTime(2026, 7, 6, 9),
        ),
        throwsStateError,
      );
    });

    test(
      'excludes expired one-time plans from normal lists after retention',
      () async {
        await repository.saveWakePlan(buildPlan());

        final normal = await repository.fetchWakePlans(
          now: DateTime(2026, 7, 6, 7, 30),
        );
        final retained = await repository.fetchWakePlans(
          now: DateTime(2026, 7, 6, 7, 29),
        );
        final debug = await repository.fetchWakePlans(
          now: DateTime(2026, 7, 6, 7, 30),
          includeExpiredOneTimeHistory: true,
        );

        expect(normal, isEmpty);
        expect(retained.map((plan) => plan.id), ['plan-1']);
        expect(debug.map((plan) => plan.id), ['plan-1']);
      },
    );

    test('skips malformed rows when fetching normal plan lists', () async {
      await repository.saveWakePlan(
        buildPlan(id: 'valid', repeatRule: RepeatRule.weekly({Weekday.monday})),
      );
      await database
          .into(database.wakePlanRows)
          .insert(
            _malformedPlanCompanion(
              id: 'bad-one-time',
              repeatType: RepeatType.oneTime,
            ),
          );

      final plans = await repository.fetchWakePlans(now: now);

      expect(plans.map((plan) => plan.id), ['valid']);
    });

    test('skips malformed rows when fetching calendar range plans', () async {
      await repository.saveWakePlan(
        buildPlan(id: 'valid', repeatRule: RepeatRule.weekly({Weekday.monday})),
      );
      await database
          .into(database.wakePlanRows)
          .insert(
            _malformedPlanCompanion(
              id: 'bad-weekly',
              repeatType: RepeatType.weekly,
            ),
          );

      final plans = await repository.fetchWakePlansForCalendarRange(
        start: monday,
        end: tuesday,
      );

      expect(plans.map((plan) => plan.id), ['valid']);
    });
  });

  group('occurrences', () {
    test(
      'saves and fetches occurrences by plan ordered by schedule time',
      () async {
        await repository.saveWakePlan(buildPlan());
        await repository.saveAlarmOccurrences([
          buildOccurrence(id: 'later', time: targetTime),
          buildOccurrence(
            id: 'earlier',
            time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
          ),
        ]);

        final occurrences = await repository.fetchOccurrencesForPlan('plan-1');

        expect(occurrences.map((occurrence) => occurrence.id), [
          'earlier',
          'later',
        ]);
      },
    );

    test(
      'fetches the complete occurrence inventory for reconciliation',
      () async {
        await repository.saveWakePlan(buildPlan());
        await repository.saveWakePlan(buildPlan(id: 'plan-2'));
        await repository.saveAlarmOccurrences([
          buildOccurrence(id: 'occ-2', wakePlanId: 'plan-2'),
          buildOccurrence(id: 'occ-1'),
        ]);

        final snapshot = await repository.fetchReconciliationSnapshot(
          now: DateTime(2026, 7, 6, 7, 20),
        );

        expect(snapshot.occurrences.map((occurrence) => occurrence.id), [
          'occ-1',
          'occ-2',
        ]);
      },
    );

    test(
      'surfaces constructor-invalid rows in reconciliation metadata',
      () async {
        await repository.saveWakePlan(buildPlan());
        await database
            .into(database.wakePlanRows)
            .insert(
              _malformedPlanCompanion(
                id: 'bad-plan',
                repeatType: RepeatType.weekly,
              ),
            );
        await database
            .into(database.alarmOccurrenceRows)
            .insert(
              AlarmOccurrenceRowsCompanion.insert(
                id: 'bad-suppression',
                wakePlanId: 'plan-1',
                scheduledAtDays: monday.daysSinceUnixEpoch,
                scheduledAtMinutes: targetTime.minutesSinceMidnight,
                status: AlarmOccurrenceStatus.userDisabled.name,
                platformAlarmId: const Value('native-exact'),
                createdAt: now,
                updatedAt: now,
              ),
            );

        final snapshot = await repository.fetchReconciliationSnapshot(
          now: DateTime(2026, 7, 6, 7, 20),
        );

        expect(snapshot.plans.map((plan) => plan.id), ['plan-1']);
        expect(snapshot.occurrences, isEmpty);
        expect(snapshot.corruptPlanIds, {'bad-plan'});
        expect(snapshot.corruptOccurrenceIds, {'bad-suppression'});
        expect(snapshot.corruptOccurrenceWakePlanIds, {'plan-1'});
      },
    );

    test('excludes expired one-time plans from reconciliation work', () async {
      await repository.saveWakePlan(buildPlan());
      await repository.saveAlarmOccurrences([
        buildOccurrence(
          id: 'expired-recovery',
          status: AlarmOccurrenceStatus.userEnablePending,
        ),
      ]);
      await database
          .into(database.alarmOccurrenceRows)
          .insert(
            AlarmOccurrenceRowsCompanion.insert(
              id: 'expired-corrupt',
              wakePlanId: 'plan-1',
              scheduledAtDays: monday.daysSinceUnixEpoch,
              scheduledAtMinutes: targetTime.minutesSinceMidnight,
              status: AlarmOccurrenceStatus.userDisabled.name,
              platformAlarmId: const Value('native-exact'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final snapshot = await repository.fetchReconciliationSnapshot(now: now);

      expect(snapshot.plans, isEmpty);
      expect(snapshot.occurrences, isEmpty);
      expect(snapshot.corruptPlanIds, isEmpty);
      expect(snapshot.corruptOccurrenceIds, isEmpty);
      expect(snapshot.corruptOccurrenceWakePlanIds, isEmpty);
    });

    test(
      'finds exact retained platform identities without decoding corrupt rows',
      () async {
        await repository.saveWakePlan(buildPlan());
        await repository.saveWakePlan(buildPlan(id: 'plan-2'));
        await repository.saveAlarmOccurrences([
          buildOccurrence(id: 'retained-1', platformAlarmId: 'native-shared'),
          buildOccurrence(
            id: 'retained-2',
            wakePlanId: 'plan-2',
            platformAlarmId: 'native-shared',
          ),
          buildOccurrence(id: 'other', platformAlarmId: 'native-other'),
        ]);
        await database
            .into(database.alarmOccurrenceRows)
            .insert(
              AlarmOccurrenceRowsCompanion.insert(
                id: 'corrupt',
                wakePlanId: 'plan-1',
                scheduledAtDays: monday.daysSinceUnixEpoch,
                scheduledAtMinutes: targetTime.minutesSinceMidnight,
                status: AlarmOccurrenceStatus.userDisabled.name,
                platformAlarmId: const Value('native-shared'),
                createdAt: now,
                updatedAt: now,
              ),
            );

        final matches = await repository
            .fetchAlarmOccurrencesByPlatformAlarmIds({'native-shared'});

        expect(matches.occurrences.map((occurrence) => occurrence.id), [
          'retained-1',
          'retained-2',
        ]);
        expect(matches.corruptPlatformAlarmIds, {'native-shared'});
        final empty = await repository.fetchAlarmOccurrencesByPlatformAlarmIds(
          {},
        );
        expect(empty.occurrences, isEmpty);
        expect(empty.corruptPlatformAlarmIds, isEmpty);
      },
    );

    test(
      'updates and clears nullable platform alarm id for native lifecycle',
      () async {
        await repository.saveWakePlan(buildPlan());
        await repository.saveAlarmOccurrences([buildOccurrence()]);

        await repository.updateOccurrencePlatformAlarmId(
          occurrenceId: 'occ-1',
          platformAlarmId: 'ios-native-1',
          updatedAt: DateTime(2026, 7, 6, 8, 1),
        );
        final scheduled = await repository.fetchAlarmOccurrence('occ-1');

        expect(scheduled!.platformAlarmId, 'ios-native-1');
        expect(scheduled.hasNativeReservation, isTrue);

        await repository.updateOccurrencePlatformAlarmId(
          occurrenceId: 'occ-1',
          platformAlarmId: null,
          updatedAt: DateTime(2026, 7, 6, 8, 2),
        );
        final cleared = await repository.fetchAlarmOccurrence('occ-1');

        expect(cleared!.platformAlarmId, isNull);
        expect(cleared.hasNativeReservation, isFalse);
      },
    );

    test('prepares and completes an exact durable dismissal', () async {
      final requestedAt = DateTime(2026, 7, 6, 8, 1, 0, 123, 456);
      final persistedRequestedAt = DateTime(2026, 7, 6, 8, 1);
      final dismissedAt = DateTime(2026, 7, 6, 8, 2, 0, 789, 123);
      await repository.saveWakePlan(buildPlan());
      await repository.saveAlarmOccurrences([
        buildOccurrence(
          status: AlarmOccurrenceStatus.ringing,
          platformAlarmId: 'native-exact',
          firedAt: now,
        ),
      ]);

      final preparation = await repository.prepareAlarmOccurrenceDismissal(
        occurrenceId: 'occ-1',
        expectedPlatformAlarmId: 'native-exact',
        requestedAt: requestedAt,
      );

      expect(
        preparation.status,
        AlarmOccurrenceDismissalPreparationStatus.ready,
      );
      expect(preparation.intent!.occurrence.id, 'occ-1');
      expect(preparation.intent!.occurrence.platformAlarmId, 'native-exact');
      expect(
        (await repository.fetchPendingAlarmOccurrenceDismissals())
            .single
            .requestedAt,
        persistedRequestedAt,
      );
      expect(preparation.intent!.requestedAt, persistedRequestedAt);

      await repository.completeAlarmOccurrenceDismissal(
        intent: preparation.intent!,
        dismissedAt: dismissedAt,
      );
      final completed = await repository.fetchAlarmOccurrence('occ-1');

      expect(completed!.status, AlarmOccurrenceStatus.dismissed);
      expect(completed.platformAlarmId, isNull);
      expect(completed.dismissedAt, DateTime(2026, 7, 6, 8, 2));
      expect(await repository.fetchPendingAlarmOccurrenceDismissals(), isEmpty);

      await repository.completeAlarmOccurrenceDismissal(
        intent: preparation.intent!,
        dismissedAt: dismissedAt,
      );
    });

    test('preparation rejects a changed exact platform identity', () async {
      await repository.saveWakePlan(buildPlan());
      await repository.saveAlarmOccurrences([
        buildOccurrence(platformAlarmId: 'native-current'),
      ]);

      final preparation = await repository.prepareAlarmOccurrenceDismissal(
        occurrenceId: 'occ-1',
        expectedPlatformAlarmId: 'native-stale',
        requestedAt: DateTime(2026, 7, 6, 8, 1),
      );

      expect(
        preparation.status,
        AlarmOccurrenceDismissalPreparationStatus.noLongerEligible,
      );
      expect(await repository.fetchPendingAlarmOccurrenceDismissals(), isEmpty);
      expect(
        (await repository.fetchAlarmOccurrence('occ-1'))!.platformAlarmId,
        'native-current',
      );
    });

    test('generic saves preserve an in-flight dismissal intent', () async {
      final requestedAt = DateTime(2026, 7, 6, 8, 1);
      await repository.saveWakePlan(buildPlan());
      final ringing = buildOccurrence(
        status: AlarmOccurrenceStatus.ringing,
        platformAlarmId: 'native-exact',
        firedAt: now,
      );
      await repository.saveAlarmOccurrences([ringing]);
      final preparation = await repository.prepareAlarmOccurrenceDismissal(
        occurrenceId: ringing.id,
        expectedPlatformAlarmId: ringing.platformAlarmId,
        requestedAt: requestedAt,
      );

      await repository.saveAlarmOccurrences([
        ringing.copyWith(
          status: AlarmOccurrenceStatus.missed,
          updatedAt: DateTime(2026, 7, 6, 8, 2),
        ),
      ]);

      final pending = await repository.fetchPendingAlarmOccurrenceDismissal(
        ringing.id,
      );
      expect(pending, isNotNull);
      expect(pending!.requestedAt, requestedAt);
      expect(pending.occurrence.status, AlarmOccurrenceStatus.missed);
      await repository.completeAlarmOccurrenceDismissal(
        intent: preparation.intent!,
        dismissedAt: DateTime(2026, 7, 6, 8, 3),
      );
      expect(
        (await repository.fetchAlarmOccurrence(ringing.id))!.status,
        AlarmOccurrenceStatus.dismissed,
      );
    });

    test('completion cannot dismiss a changed exact identity', () async {
      final requestedAt = DateTime(2026, 7, 6, 8, 1);
      await repository.saveWakePlan(buildPlan());
      await repository.saveAlarmOccurrences([
        buildOccurrence(platformAlarmId: 'native-exact'),
      ]);
      final preparation = await repository.prepareAlarmOccurrenceDismissal(
        occurrenceId: 'occ-1',
        expectedPlatformAlarmId: 'native-exact',
        requestedAt: requestedAt,
      );
      await repository.updateOccurrencePlatformAlarmId(
        occurrenceId: 'occ-1',
        platformAlarmId: 'native-replacement',
        updatedAt: DateTime(2026, 7, 6, 8, 2),
      );
      expect(
        (await repository.fetchPendingAlarmOccurrenceDismissal(
          'occ-1',
        ))!.platformAlarmId,
        'native-exact',
      );

      await expectLater(
        repository.completeAlarmOccurrenceDismissal(
          intent: preparation.intent!,
          dismissedAt: DateTime(2026, 7, 6, 8, 3),
        ),
        throwsStateError,
      );
      final unchanged = await repository.fetchAlarmOccurrence('occ-1');
      expect(unchanged!.status, AlarmOccurrenceStatus.scheduled);
      expect(unchanged.platformAlarmId, 'native-replacement');
    });

    test('round-trips the distinct user-disabled occurrence state', () async {
      await repository.saveWakePlan(buildPlan());
      await repository.saveAlarmOccurrences([
        buildOccurrence(
          id: 'disabled-occurrence',
          status: AlarmOccurrenceStatus.userDisabled,
        ),
      ]);

      final fetched = await repository.fetchAlarmOccurrence(
        'disabled-occurrence',
      );

      expect(fetched, isNotNull);
      expect(fetched!.status, AlarmOccurrenceStatus.userDisabled);
      expect(fetched.platformAlarmId, isNull);
      expect(fetched.isUserDisabled, isTrue);
    });

    test(
      'reports missing occurrences when storing platform alarm id',
      () async {
        expect(
          () => repository.updateOccurrencePlatformAlarmId(
            occurrenceId: 'missing',
            platformAlarmId: 'ios-native-1',
            updatedAt: DateTime(2026, 7, 6, 8, 1),
          ),
          throwsStateError,
        );
      },
    );

    test('fetches reserved occurrences for plan cancel', () async {
      await repository.saveWakePlan(buildPlan());
      await repository.saveAlarmOccurrences([
        buildOccurrence(id: 'reserved-1', platformAlarmId: 'native-1'),
        buildOccurrence(id: 'unreserved'),
        buildOccurrence(
          id: 'reserved-2',
          day: tuesday,
          platformAlarmId: 'native-2',
        ),
        buildOccurrence(
          id: 'ringing',
          day: tuesday,
          status: AlarmOccurrenceStatus.ringing,
          platformAlarmId: 'native-ringing',
          firedAt: DateTime(2026, 7, 7, 7),
        ),
        buildOccurrence(
          id: 'stale-cancelled',
          day: tuesday,
          status: AlarmOccurrenceStatus.cancelled,
          platformAlarmId: 'native-stale',
        ),
        buildOccurrence(
          id: 'user-disabled',
          status: AlarmOccurrenceStatus.userDisabled,
        ),
        buildOccurrence(
          id: 'pending-off',
          status: AlarmOccurrenceStatus.userDisablePending,
          platformAlarmId: 'native-pending-off',
        ),
        buildOccurrence(
          id: 'pending-on',
          status: AlarmOccurrenceStatus.userEnablePending,
          platformAlarmId: 'native-pending-on',
        ),
        buildOccurrence(
          id: 'unknown-with-native',
          status: AlarmOccurrenceStatus.unknownPersisted,
          platformAlarmId: 'native-unknown',
        ),
        buildOccurrence(
          id: 'unknown-without-native',
          status: AlarmOccurrenceStatus.unknownPersisted,
        ),
      ]);

      final reserved = await repository.fetchReservedOccurrencesForPlan(
        'plan-1',
      );

      expect(reserved.map((occurrence) => occurrence.platformAlarmId), [
        'native-1',
        'native-pending-off',
        'native-pending-on',
        'native-unknown',
        null,
        'native-2',
        'native-ringing',
      ]);
    });

    test('fetches occurrences for a calendar range', () async {
      await repository.saveWakePlan(buildPlan());
      await repository.saveAlarmOccurrences([
        buildOccurrence(id: 'monday', day: monday),
        buildOccurrence(id: 'tuesday', day: tuesday),
        buildOccurrence(id: 'saturday', day: saturday),
      ]);

      final occurrences = await repository.fetchOccurrencesForCalendarRange(
        start: monday,
        end: tuesday,
      );

      expect(occurrences.map((occurrence) => occurrence.id), [
        'monday',
        'tuesday',
      ]);
    });

    test('decodes unknown occurrence statuses conservatively', () async {
      await repository.saveWakePlan(buildPlan());
      await repository.saveAlarmOccurrences([buildOccurrence(id: 'valid')]);
      await database
          .into(database.alarmOccurrenceRows)
          .insert(_malformedOccurrenceCompanion());

      final unknown = await repository.fetchAlarmOccurrence('bad-occ');
      expect(unknown, isNotNull);
      expect(unknown!.status, AlarmOccurrenceStatus.unknownPersisted);

      final byPlan = await repository.fetchOccurrencesForPlan('plan-1');
      final byRange = await repository.fetchOccurrencesForCalendarRange(
        start: monday,
        end: monday,
      );
      final conservativeCancellation = await repository
          .fetchReservedOccurrencesForPlan('plan-1');

      expect(byPlan.map((occurrence) => occurrence.id), ['valid', 'bad-occ']);
      expect(byRange.map((occurrence) => occurrence.id), ['valid', 'bad-occ']);
      expect(conservativeCancellation.map((occurrence) => occurrence.id), [
        'bad-occ',
      ]);
    });
  });

  group('app settings', () {
    test('returns null before settings are saved', () async {
      expect(await repository.fetchAppSettings(), isNull);
    });

    test('returns initial defaults before settings are saved', () async {
      final settings = await repository.fetchEffectiveAppSettings();

      expect(settings.defaultStartOffset, const Duration(minutes: 60));
      expect(settings.defaultInterval, const Duration(minutes: 5));
      expect(settings.defaultRepeatType, RepeatType.oneTime);
      expect(settings.defaultVibrationEnabled, isTrue);
      expect(settings.defaultSoundId, 'default');
    });

    test('saves and fetches app settings', () async {
      final settings = AppSettings(
        defaultStartOffset: const Duration(minutes: 45),
        defaultInterval: const Duration(minutes: 10),
        defaultSoundId: defaultWakePlanSoundId,
        defaultVibrationEnabled: false,
        defaultRepeatType: RepeatType.weekly,
        defaultTargetTime: targetTime,
      );

      await repository.saveAppSettings(settings);

      final fetched = await repository.fetchAppSettings();

      expect(fetched, isNotNull);
      expect(fetched!.defaultStartOffset, settings.defaultStartOffset);
      expect(fetched.defaultInterval, settings.defaultInterval);
      expect(fetched.defaultSoundId, defaultWakePlanSoundId);
      expect(fetched.defaultVibrationEnabled, isFalse);
      expect(fetched.defaultRepeatType, RepeatType.weekly);
      expect(fetched.defaultTargetTime, targetTime);
    });

    test('updates existing app settings', () async {
      await repository.saveAppSettings(
        AppSettings(
          defaultStartOffset: const Duration(minutes: 45),
          defaultInterval: const Duration(minutes: 10),
          defaultSoundId: defaultWakePlanSoundId,
          defaultVibrationEnabled: false,
          defaultRepeatType: RepeatType.weekly,
          defaultTargetTime: targetTime,
        ),
      );

      await repository.saveAppSettings(
        AppSettings(
          defaultStartOffset: const Duration(minutes: 60),
          defaultInterval: const Duration(minutes: 5),
          defaultSoundId: defaultWakePlanSoundId,
          defaultVibrationEnabled: true,
          defaultRepeatType: RepeatType.oneTime,
        ),
      );

      final fetched = await repository.fetchAppSettings();

      expect(fetched, isNotNull);
      expect(fetched!.defaultStartOffset, const Duration(minutes: 60));
      expect(fetched.defaultInterval, const Duration(minutes: 5));
      expect(fetched.defaultSoundId, defaultWakePlanSoundId);
      expect(fetched.defaultVibrationEnabled, isTrue);
      expect(fetched.defaultRepeatType, RepeatType.oneTime);
      expect(fetched.defaultTargetTime, isNull);
    });

    test('isolates malformed app settings rows', () async {
      await database
          .into(database.appSettingsRows)
          .insert(_malformedAppSettingsCompanion());

      expect(await repository.fetchAppSettings(), isNull);
      expect(
        (await repository.fetchEffectiveAppSettings()).defaultStartOffset,
        AppSettings.initial().defaultStartOffset,
      );
    });

    test(
      'falls back when stored defaults violate timing constraints',
      () async {
        await database
            .into(database.appSettingsRows)
            .insert(_invalidTimingAppSettingsCompanion());

        expect(await repository.fetchAppSettings(), isNull);
        final fallback = await repository.fetchEffectiveAppSettings();

        expect(fallback.defaultStartOffset, defaultWakePlanStartOffset);
        expect(fallback.defaultInterval, defaultWakePlanInterval);
        expect(fallback.defaultSoundId, defaultWakePlanSoundId);
        expect(fallback.defaultVibrationEnabled, isTrue);
        expect(fallback.defaultRepeatType, RepeatType.oneTime);
      },
    );

    test('falls back when stored default sound is unsupported', () async {
      await database
          .into(database.appSettingsRows)
          .insert(_unsupportedSoundAppSettingsCompanion());

      expect(await repository.fetchAppSettings(), isNull);
      expect(
        (await repository.fetchEffectiveAppSettings()).defaultSoundId,
        defaultWakePlanSoundId,
      );
    });
  });

  group('malformed persisted rows', () {
    test('isolates one-time plans missing their date', () async {
      await database
          .into(database.wakePlanRows)
          .insert(
            _malformedPlanCompanion(
              id: 'bad-one-time',
              repeatType: RepeatType.oneTime,
            ),
          );

      expect(await repository.fetchWakePlan('bad-one-time'), isNull);
    });

    test('isolates weekly plans missing their weekday mask', () async {
      await database
          .into(database.wakePlanRows)
          .insert(
            _malformedPlanCompanion(
              id: 'bad-weekly',
              repeatType: RepeatType.weekly,
            ),
          );

      expect(await repository.fetchWakePlan('bad-weekly'), isNull);
    });
  });
}

AlarmOccurrenceRowsCompanion _malformedOccurrenceCompanion() {
  final now = DateTime(2026, 7, 6, 8);
  return AlarmOccurrenceRowsCompanion.insert(
    id: 'bad-occ',
    wakePlanId: 'plan-1',
    scheduledAtDays: CalendarDay(
      year: 2026,
      month: 7,
      day: 6,
    ).daysSinceUnixEpoch,
    scheduledAtMinutes: 420,
    status: 'not-a-status',
    createdAt: now,
    updatedAt: now,
  );
}

AppSettingsRowsCompanion _malformedAppSettingsCompanion() {
  return AppSettingsRowsCompanion.insert(
    id: const Value(1),
    defaultStartOffsetMinutes: 60,
    defaultIntervalMinutes: 5,
    defaultSoundId: 'default',
    defaultVibrationEnabled: true,
    defaultRepeatType: 'not-a-repeat-type',
  );
}

AppSettingsRowsCompanion _invalidTimingAppSettingsCompanion() {
  return AppSettingsRowsCompanion.insert(
    id: const Value(1),
    defaultStartOffsetMinutes: 240,
    defaultIntervalMinutes: 1,
    defaultSoundId: 'default',
    defaultVibrationEnabled: true,
    defaultRepeatType: RepeatType.oneTime.name,
  );
}

AppSettingsRowsCompanion _unsupportedSoundAppSettingsCompanion() {
  return AppSettingsRowsCompanion.insert(
    id: const Value(1),
    defaultStartOffsetMinutes: 60,
    defaultIntervalMinutes: 5,
    defaultSoundId: 'soft-bells',
    defaultVibrationEnabled: true,
    defaultRepeatType: RepeatType.oneTime.name,
  );
}

WakePlanRowsCompanion _malformedPlanCompanion({
  required String id,
  required RepeatType repeatType,
}) {
  final now = DateTime(2026, 7, 6, 8);
  return WakePlanRowsCompanion.insert(
    id: id,
    title: 'Malformed',
    targetTimeMinutes: 420,
    startOffsetMinutes: 60,
    intervalMinutes: 5,
    repeatType: repeatType.name,
    isEnabled: true,
    status: WakePlanStatus.scheduled.name,
    soundId: 'default',
    vibrationEnabled: true,
    createdAt: now,
    updatedAt: now,
    oneTimeDateDays: const Value.absent(),
    weekdaysMask: const Value.absent(),
  );
}
