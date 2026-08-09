import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 6, 8);
  final monday = CalendarDay(year: 2026, month: 7, day: 6);
  final tuesday = CalendarDay(year: 2026, month: 7, day: 7);
  final targetTime = TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0);

  WakePlan buildPlan({
    RepeatRule? repeatRule,
    WakePlanStatus status = WakePlanStatus.scheduled,
    bool isEnabled = true,
  }) {
    return WakePlan(
      id: 'plan-1',
      title: 'Weekday wake up',
      targetTime: targetTime,
      startOffset: const Duration(minutes: 60),
      interval: const Duration(minutes: 5),
      repeatRule: repeatRule ?? RepeatRule.oneTime(monday),
      isEnabled: isEnabled,
      status: status,
      soundId: 'default',
      vibrationEnabled: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  AlarmOccurrence buildOccurrence({
    AlarmOccurrenceStatus status = AlarmOccurrenceStatus.scheduled,
    String? platformAlarmId,
    String? reservationId,
    int reservationGeneration = 0,
    DateTime? firedAt,
    DateTime? dismissedAt,
    String? failureReason,
  }) {
    return AlarmOccurrence(
      id: 'occ-1',
      wakePlanId: 'plan-1',
      scheduledAt: DateMinute(day: monday, time: targetTime),
      status: status,
      platformAlarmId: platformAlarmId,
      reservationId: reservationId,
      reservationGeneration: reservationGeneration,
      firedAt: firedAt,
      dismissedAt: dismissedAt,
      failureReason: failureReason,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('RepeatRule', () {
    test('represents one-time and weekday repeat plans', () {
      final oneTime = RepeatRule.oneTime(monday);
      final weekdays = RepeatRule.weekly({Weekday.monday, Weekday.tuesday});

      expect(oneTime.type, RepeatType.oneTime);
      expect(oneTime.includes(monday), isTrue);
      expect(oneTime.includes(tuesday), isFalse);

      expect(weekdays.type, RepeatType.weekly);
      expect(weekdays.includes(monday), isTrue);
      expect(weekdays.includes(tuesday), isTrue);
    });

    test('rejects weekly repeat without days', () {
      expect(() => RepeatRule.weekly({}), throwsArgumentError);
    });

    test('treats weekly day sets as order independent', () {
      final mondayFirst = RepeatRule.weekly({Weekday.monday, Weekday.tuesday});
      final tuesdayFirst = RepeatRule.weekly({Weekday.tuesday, Weekday.monday});

      expect(mondayFirst, tuesdayFirst);
      expect(mondayFirst.hashCode, tuesdayFirst.hashCode);
    });

    test('truncates occurrences at and after until', () {
      final rule = RepeatRule.weekly({
        Weekday.monday,
        Weekday.tuesday,
      }, until: tuesday);

      expect(rule.includes(monday), isTrue);
      expect(rule.includes(tuesday), isFalse);
      expect(rule.includes(tuesday.addDays(7)), isFalse);
    });

    test('truncatedBefore sets until and rejects one-time rules', () {
      final rule = RepeatRule.weekly({Weekday.monday, Weekday.tuesday});
      final truncated = rule.truncatedBefore(tuesday);

      expect(truncated.until, tuesday);
      expect(truncated.includes(monday), isTrue);
      expect(truncated.includes(tuesday), isFalse);

      expect(
        () => RepeatRule.oneTime(monday).truncatedBefore(monday),
        throwsStateError,
      );
    });

    test('truncatedBefore never extends an already-earlier truncation', () {
      final rule = RepeatRule.weekly({
        Weekday.monday,
        Weekday.tuesday,
      }, until: monday);

      final extended = rule.truncatedBefore(tuesday);
      expect(extended.until, monday);

      final shortened = rule.truncatedBefore(monday.addDays(-7));
      expect(shortened.until, monday.addDays(-7));
    });
  });

  group('WakePlan', () {
    test('represents enabled and deleted semantics', () {
      final weekly = buildPlan(
        repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
      );
      final deleted = weekly.copyWith(
        status: WakePlanStatus.deleted,
        isEnabled: false,
      );

      expect(weekly.isEnabled, isTrue);
      expect(weekly.status, WakePlanStatus.scheduled);
      expect(weekly.occursOn(monday), isTrue);
      expect(weekly.occursOn(tuesday), isTrue);

      expect(deleted.isDeleted, isTrue);
      expect(deleted.occursOn(tuesday), isFalse);
    });

    test('uses core time helpers for target and start times', () {
      final plan = buildPlan();

      expect(plan.targetAt(monday), DateTime(2026, 7, 6, 7));
      expect(plan.startAt(monday), DateTime(2026, 7, 6, 6));
    });

    test(
      'validates sound, vibration, interval, and start offset constraints',
      () {
        expect(
          () => buildPlan().copyWith(startOffset: const Duration(seconds: -1)),
          throwsArgumentError,
        );
        expect(
          () => buildPlan().copyWith(interval: Duration.zero),
          throwsArgumentError,
        );
        expect(() => buildPlan().copyWith(soundId: ' '), throwsArgumentError);
        expect(buildPlan().vibrationEnabled, isTrue);
      },
    );

    test('requires deleted plans to be disabled', () {
      expect(
        () => buildPlan(status: WakePlanStatus.deleted),
        throwsArgumentError,
      );
    });

    test('uses the MVP minimum interval', () {
      expect(
        () => buildPlan().copyWith(interval: const Duration(minutes: 3)),
        throwsArgumentError,
      );
      expect(minimumWakePlanInterval, const Duration(minutes: 5));
    });

    test('does not cap already-created plan wake windows', () {
      final plan = buildPlan().copyWith(
        startOffset: maximumWakePlanStartOffset + const Duration(minutes: 5),
      );

      expect(plan.startOffset, const Duration(minutes: 185));
    });

    test('normalizes skipHolidays to false for non-weekly plans, even via '
        'copyWith', () {
      final oneTimeWithSkip = WakePlan(
        id: 'plan-1',
        title: 'Weekday wake up',
        targetTime: targetTime,
        startOffset: const Duration(minutes: 60),
        interval: const Duration(minutes: 5),
        repeatRule: RepeatRule.oneTime(monday),
        isEnabled: true,
        status: WakePlanStatus.scheduled,
        skipHolidays: true,
        soundId: 'default',
        vibrationEnabled: true,
        createdAt: now,
        updatedAt: now,
      );
      expect(oneTimeWithSkip.skipHolidays, isFalse);

      final weekly = buildPlan(
        repeatRule: RepeatRule.weekly({Weekday.monday}),
      ).copyWith(skipHolidays: true);
      expect(weekly.skipHolidays, isTrue);

      // Switching a weekly plan (with skipHolidays already on) back to
      // one-time via copyWith must not leave skipHolidays stuck at true —
      // a one-time plan's date was explicitly chosen by the user and must
      // never be silently dropped for landing on a holiday.
      final switchedToOneTime = weekly.copyWith(
        repeatRule: RepeatRule.oneTime(monday),
      );
      expect(switchedToOneTime.skipHolidays, isFalse);
    });
  });

  group('WakePlanOccurrenceException', () {
    test('generates a deterministic id from wakePlanId and originalDay', () {
      final exception = WakePlanOccurrenceException(
        wakePlanId: 'plan-1',
        originalDay: monday,
        type: WakePlanOccurrenceExceptionType.skipped,
        createdAt: now,
        updatedAt: now,
      );

      expect(
        exception.id,
        WakePlanOccurrenceException.idFor(
          wakePlanId: 'plan-1',
          originalDay: monday,
        ),
      );
      expect(exception.isSkipped, isTrue);
      expect(exception.isMoved, isFalse);
    });

    test('rejects movedToDay on a skipped exception', () {
      expect(
        () => WakePlanOccurrenceException(
          wakePlanId: 'plan-1',
          originalDay: monday,
          type: WakePlanOccurrenceExceptionType.skipped,
          movedToDay: tuesday,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('requires movedToDay on a moved exception', () {
      expect(
        () => WakePlanOccurrenceException(
          wakePlanId: 'plan-1',
          originalDay: monday,
          type: WakePlanOccurrenceExceptionType.moved,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      final moved = WakePlanOccurrenceException(
        wakePlanId: 'plan-1',
        originalDay: monday,
        type: WakePlanOccurrenceExceptionType.moved,
        movedToDay: tuesday,
        createdAt: now,
        updatedAt: now,
      );
      expect(moved.isMoved, isTrue);
      expect(moved.movedToDay, tuesday);
    });

    test('occursOnConsideringExceptions suppresses excepted days', () {
      final plan = buildPlan(
        repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
      );
      final exception = WakePlanOccurrenceException(
        wakePlanId: plan.id,
        originalDay: monday,
        type: WakePlanOccurrenceExceptionType.skipped,
        createdAt: now,
        updatedAt: now,
      );

      expect(
        occursOnConsideringExceptions(
          wakePlan: plan,
          day: monday,
          holidays: const {},
          exceptionsByOriginalDay: {monday: exception},
        ),
        isFalse,
      );
      expect(
        occursOnConsideringExceptions(
          wakePlan: plan,
          day: tuesday,
          holidays: const {},
          exceptionsByOriginalDay: {monday: exception},
        ),
        isTrue,
      );
    });
  });

  group('AlarmOccurrence', () {
    test('represents all required occurrence states', () {
      expect(
        AlarmOccurrenceStatus.values,
        containsAll([
          AlarmOccurrenceStatus.scheduled,
          AlarmOccurrenceStatus.ringing,
          AlarmOccurrenceStatus.dismissed,
          AlarmOccurrenceStatus.missed,
          AlarmOccurrenceStatus.expired,
          AlarmOccurrenceStatus.cancelled,
          AlarmOccurrenceStatus.failed,
        ]),
      );
    });

    test('holds nullable native reservation identity', () {
      final unscheduled = buildOccurrence();
      final scheduled = unscheduled.copyWith(platformAlarmId: 'ios-42');

      expect(unscheduled.platformAlarmId, isNull);
      expect(unscheduled.hasNativeReservation, isFalse);
      expect(scheduled.platformAlarmId, 'ios-42');
      expect(scheduled.hasNativeReservation, isTrue);
      expect(scheduled.copyWith(platformAlarmId: null).platformAlarmId, isNull);
    });

    test('defaults and validates durable reservation identity', () {
      final legacy = buildOccurrence();
      final recreated = buildOccurrence(
        reservationId: 'stable-slot',
        reservationGeneration: 4,
      );

      expect(legacy.reservationId, legacy.id);
      expect(legacy.reservationGeneration, 0);
      expect(recreated.reservationId, 'stable-slot');
      expect(recreated.reservationGeneration, 4);
      expect(
        recreated.copyWith(reservationGeneration: 7).reservationGeneration,
        7,
      );
      expect(
        () => buildOccurrence(reservationGeneration: -1),
        throwsRangeError,
      );
      expect(() => buildOccurrence(reservationId: '   '), throwsArgumentError);
    });

    test('dismissing one occurrence does not model stopping the plan', () {
      final plan = buildPlan(status: WakePlanStatus.active);
      final ringing = buildOccurrence(
        status: AlarmOccurrenceStatus.ringing,
        firedAt: DateTime(2026, 7, 6, 6),
      );

      final dismissed = ringing.copyWith(
        status: AlarmOccurrenceStatus.dismissed,
        dismissedAt: DateTime(2026, 7, 6, 6, 1),
      );

      expect(dismissed.status, AlarmOccurrenceStatus.dismissed);
      expect(plan.status, WakePlanStatus.active);
      expect(plan.isEnabled, isTrue);
    });

    test('requires failed occurrences to carry a failure reason', () {
      expect(
        () => buildOccurrence(status: AlarmOccurrenceStatus.failed),
        throwsArgumentError,
      );

      final failed = buildOccurrence(
        status: AlarmOccurrenceStatus.failed,
        failureReason: 'permission denied',
      );

      expect(failed.failureReason, 'permission denied');
    });

    test('rejects timestamps that conflict with occurrence status', () {
      expect(
        () => buildOccurrence(
          status: AlarmOccurrenceStatus.scheduled,
          firedAt: DateTime(2026, 7, 6, 6),
        ),
        throwsArgumentError,
      );
      expect(
        () => buildOccurrence(status: AlarmOccurrenceStatus.dismissed),
        throwsArgumentError,
      );
      expect(
        () => buildOccurrence(
          status: AlarmOccurrenceStatus.ringing,
          dismissedAt: DateTime(2026, 7, 6, 6, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('AppSettings', () {
    test('uses MVP initial defaults', () {
      final settings = AppSettings.initial();

      expect(settings.defaultStartOffset, defaultWakePlanStartOffset);
      expect(settings.defaultStartOffset, const Duration(minutes: 60));
      expect(settings.defaultInterval, defaultWakePlanInterval);
      expect(settings.defaultInterval, const Duration(minutes: 5));
      expect(settings.defaultSoundId, defaultWakePlanSoundId);
      expect(settings.defaultVibrationEnabled, isTrue);
      expect(settings.defaultRepeatType, RepeatType.oneTime);
      expect(settings.defaultTargetTime, isNull);
    });

    test('represents default plan constraints and notification settings', () {
      final settings = AppSettings(
        defaultStartOffset: const Duration(minutes: 60),
        defaultInterval: const Duration(minutes: 5),
        defaultSoundId: defaultWakePlanSoundId,
        defaultVibrationEnabled: true,
        defaultRepeatType: RepeatType.weekly,
        defaultTargetTime: targetTime,
      );

      expect(settings.defaultStartOffset, const Duration(minutes: 60));
      expect(settings.defaultInterval, const Duration(minutes: 5));
      expect(settings.defaultSoundId, 'default');
      expect(settings.defaultVibrationEnabled, isTrue);
      expect(settings.defaultRepeatType, RepeatType.weekly);
      expect(settings.defaultTargetTime, targetTime);
      expect(
        settings.copyWith(defaultTargetTime: null).defaultTargetTime,
        null,
      );
    });

    test('sanitizes UI-facing default values to supported constraints', () {
      final settings = sanitizeAppSettings(
        defaultStartOffset: const Duration(hours: 12),
        defaultInterval: const Duration(hours: 2),
        defaultSoundId: 'unsupported',
        defaultVibrationEnabled: false,
        defaultRepeatType: RepeatType.weekly,
      );

      expect(settings.defaultStartOffset, maximumWakePlanStartOffset);
      expect(settings.defaultInterval, maximumWakePlanInterval);
      expect(settings.defaultSoundId, defaultWakePlanSoundId);
      expect(settings.defaultVibrationEnabled, isFalse);
      expect(settings.defaultRepeatType, RepeatType.weekly);
    });

    test('sanitizes short default intervals to the minimum', () {
      final settings = sanitizeAppSettings(
        defaultInterval: const Duration(minutes: 1),
      );

      expect(settings.defaultInterval, minimumWakePlanInterval);
    });

    test('sanitizes negative durations to initial defaults', () {
      final settings = sanitizeAppSettings(
        defaultStartOffset: const Duration(minutes: -1),
        defaultInterval: const Duration(minutes: -1),
      );

      expect(settings.defaultStartOffset, defaultWakePlanStartOffset);
      expect(settings.defaultInterval, defaultWakePlanInterval);
    });

    test('rejects unsupported default sound ids', () {
      expect(
        () => AppSettings(
          defaultStartOffset: defaultWakePlanStartOffset,
          defaultInterval: defaultWakePlanInterval,
          defaultSoundId: 'soft-bells',
          defaultVibrationEnabled: true,
          defaultRepeatType: RepeatType.oneTime,
        ),
        throwsArgumentError,
      );
    });

    test('builds the repeat rule requested by create-flow defaults', () {
      final date = CalendarDay(year: 2026, month: 7, day: 8);

      expect(
        AppSettings.initial().repeatRuleForDate(date),
        RepeatRule.oneTime(date),
      );
      expect(
        AppSettings.initial()
            .copyWith(defaultRepeatType: RepeatType.weekly)
            .repeatRuleForDate(date),
        RepeatRule.weekly({Weekday.wednesday}),
      );
    });
  });
}
