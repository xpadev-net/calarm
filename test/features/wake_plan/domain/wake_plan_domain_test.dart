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
    CalendarDay? skipNextDate,
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
      skipNextDate: skipNextDate,
      soundId: 'default',
      vibrationEnabled: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  AlarmOccurrence buildOccurrence({
    AlarmOccurrenceStatus status = AlarmOccurrenceStatus.scheduled,
    String? platformAlarmId,
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
  });

  group('WakePlan', () {
    test('represents enabled, deleted, and skip-next-date semantics', () {
      final weekly = buildPlan(
        repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        status: WakePlanStatus.skipped,
        skipNextDate: monday,
      );
      final deleted = weekly.copyWith(
        status: WakePlanStatus.deleted,
        isEnabled: false,
        skipNextDate: null,
      );

      expect(weekly.isEnabled, isTrue);
      expect(weekly.status, WakePlanStatus.skipped);
      expect(weekly.hasSkippedNextDate, isTrue);
      expect(weekly.occursOn(monday), isFalse);
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

    test('enforces skipped status and skip-next-date consistency', () {
      expect(
        () => buildPlan(status: WakePlanStatus.skipped),
        throwsArgumentError,
      );
      expect(() => buildPlan(skipNextDate: monday), throwsArgumentError);
    });

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
    test('represents default plan constraints and notification settings', () {
      final settings = AppSettings(
        defaultStartOffset: const Duration(minutes: 60),
        defaultInterval: const Duration(minutes: 5),
        defaultSoundId: 'default',
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
  });
}
