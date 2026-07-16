import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
    test('starts at migration version 1', () {
      expect(database.schemaVersion, 1);
      expect(database.migration, isNotNull);
    });
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
      ]);

      final reserved = await repository.fetchReservedOccurrencesForPlan(
        'plan-1',
      );

      expect(reserved.map((occurrence) => occurrence.platformAlarmId), [
        'native-1',
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

    test('isolates malformed occurrence rows', () async {
      await repository.saveWakePlan(buildPlan());
      await repository.saveAlarmOccurrences([buildOccurrence(id: 'valid')]);
      await database
          .into(database.alarmOccurrenceRows)
          .insert(_malformedOccurrenceCompanion());

      expect(await repository.fetchAlarmOccurrence('bad-occ'), isNull);

      final byPlan = await repository.fetchOccurrencesForPlan('plan-1');
      final byRange = await repository.fetchOccurrencesForCalendarRange(
        start: monday,
        end: monday,
      );

      expect(byPlan.map((occurrence) => occurrence.id), ['valid']);
      expect(byRange.map((occurrence) => occurrence.id), ['valid']);
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
