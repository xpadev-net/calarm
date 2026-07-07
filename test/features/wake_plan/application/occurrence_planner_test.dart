import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/application/occurrence_planner.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = OccurrencePlanner();
  final monday = CalendarDay(year: 2026, month: 7, day: 6);
  final tuesday = CalendarDay(year: 2026, month: 7, day: 7);
  final wednesday = CalendarDay(year: 2026, month: 7, day: 8);
  final saturday = CalendarDay(year: 2026, month: 7, day: 11);
  final sunday = CalendarDay(year: 2026, month: 7, day: 12);
  final createdAt = DateTime(2026, 7, 1, 12);

  WakePlan buildPlan({
    TimeOfDayMinutes? targetTime,
    Duration startOffset = const Duration(minutes: 60),
    Duration interval = const Duration(minutes: 5),
    RepeatRule? repeatRule,
    WakePlanStatus status = WakePlanStatus.scheduled,
    bool isEnabled = true,
    CalendarDay? skipNextDate,
  }) {
    return WakePlan(
      id: 'plan-1',
      title: 'Morning',
      targetTime:
          targetTime ?? TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
      startOffset: startOffset,
      interval: interval,
      repeatRule: repeatRule ?? RepeatRule.oneTime(monday),
      isEnabled: isEnabled,
      status: status,
      skipNextDate: skipNextDate,
      soundId: 'default',
      vibrationEnabled: true,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  List<String> times(Iterable<AlarmOccurrenceDraft> occurrences) {
    return occurrences
        .map((occurrence) => occurrence.scheduledAt.time.toString())
        .toList();
  }

  List<String> dateTimes(Iterable<AlarmOccurrenceDraft> occurrences) {
    return occurrences
        .map((occurrence) => occurrence.scheduledAt.toString())
        .toList();
  }

  group('OccurrencePlanner', () {
    test('generates 13 occurrences for 07:00 / 60 minutes / 5 minutes', () {
      final result = planner.plan(
        wakePlan: buildPlan(),
        startDay: monday,
        endExclusive: tuesday,
        now: DateTime(2026, 7, 6, 5),
      );

      expect(result.wakeInstances, hasLength(1));
      expect(result.previewCount, 13);
      expect(result.schedulingCandidateCount, 13);
      expect(times(result.previewOccurrences).first, '06:00');
      expect(times(result.previewOccurrences).last, '07:00');
    });

    test('includes target time when interval does not divide the window', () {
      final result = planner.plan(
        wakePlan: buildPlan(
          startOffset: const Duration(minutes: 45),
          interval: const Duration(minutes: 10),
        ),
        startDay: monday,
        endExclusive: tuesday,
        now: DateTime(2026, 7, 6, 5),
      );

      expect(times(result.previewOccurrences), [
        '06:15',
        '06:25',
        '06:35',
        '06:45',
        '06:55',
        '07:00',
      ]);
      expect(result.schedulingCandidates, result.previewOccurrences);
    });

    test('excludes past occurrences only from scheduling candidates', () {
      final result = planner.plan(
        wakePlan: buildPlan(),
        startDay: monday,
        endExclusive: tuesday,
        now: DateTime(2026, 7, 6, 6, 20),
      );

      expect(result.previewCount, 13);
      expect(result.schedulingCandidateCount, 9);
      expect(times(result.schedulingCandidates).first, '06:20');
      expect(times(result.schedulingCandidates).last, '07:00');
    });

    test('handles wake windows that cross into the previous day', () {
      final result = planner.plan(
        wakePlan: buildPlan(
          targetTime: TimeOfDayMinutes.fromHourMinute(hour: 0, minute: 30),
          startOffset: const Duration(minutes: 60),
          interval: const Duration(minutes: 15),
          repeatRule: RepeatRule.oneTime(tuesday),
        ),
        startDay: tuesday,
        endExclusive: wednesday,
        now: DateTime(2026, 7, 6, 23),
      );

      expect(result.wakeInstances.single.targetDay, tuesday);
      expect(dateTimes(result.previewOccurrences), [
        '2026-07-06 23:30',
        '2026-07-06 23:45',
        '2026-07-07 00:00',
        '2026-07-07 00:15',
        '2026-07-07 00:30',
      ]);
    });

    test(
      'handles one-time, daily, weekday, weekend, and arbitrary weekdays',
      () {
        final oneTime = planner.plan(
          wakePlan: buildPlan(repeatRule: RepeatRule.oneTime(tuesday)),
          startDay: monday,
          endExclusive: wednesday,
          now: DateTime(2026, 7, 6, 5),
        );
        final daily = planner.plan(
          wakePlan: buildPlan(
            repeatRule: RepeatRule.weekly(Set.of(Weekday.values)),
          ),
          startDay: monday,
          endExclusive: sunday.addDays(1),
          now: DateTime(2026, 7, 6, 5),
        );
        final weekdays = planner.plan(
          wakePlan: buildPlan(
            repeatRule: RepeatRule.weekly({
              Weekday.monday,
              Weekday.tuesday,
              Weekday.wednesday,
              Weekday.thursday,
              Weekday.friday,
            }),
          ),
          startDay: monday,
          endExclusive: sunday.addDays(1),
          now: DateTime(2026, 7, 6, 5),
        );
        final weekends = planner.plan(
          wakePlan: buildPlan(
            repeatRule: RepeatRule.weekly({Weekday.saturday, Weekday.sunday}),
          ),
          startDay: monday,
          endExclusive: sunday.addDays(1),
          now: DateTime(2026, 7, 6, 5),
        );
        final arbitraryWeekdays = planner.plan(
          wakePlan: buildPlan(
            repeatRule: RepeatRule.weekly({Weekday.tuesday, Weekday.thursday}),
          ),
          startDay: monday,
          endExclusive: sunday.addDays(1),
          now: DateTime(2026, 7, 6, 5),
        );

        expect(oneTime.wakeInstances.map((instance) => instance.targetDay), [
          tuesday,
        ]);
        expect(daily.wakeInstances, hasLength(7));
        expect(weekdays.wakeInstances, hasLength(5));
        expect(weekends.wakeInstances.map((instance) => instance.targetDay), [
          saturday,
          sunday,
        ]);
        expect(
          arbitraryWeekdays.wakeInstances.map((instance) => instance.targetDay),
          [tuesday, CalendarDay(year: 2026, month: 7, day: 9)],
        );
      },
    );

    test('excludes the skip-next wake instance', () {
      final result = planner.plan(
        wakePlan: buildPlan(
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
          skipNextDate: monday,
        ),
        startDay: monday,
        endExclusive: wednesday,
        now: DateTime(2026, 7, 6, 5),
      );

      expect(result.wakeInstances.map((instance) => instance.targetDay), [
        tuesday,
      ]);
      expect(result.previewCount, 13);
      expect(result.schedulingCandidateCount, 13);
    });

    test('does not generate disabled, deleted, or finished plans', () {
      for (final plan in [
        buildPlan(isEnabled: false),
        buildPlan(status: WakePlanStatus.finished),
        buildPlan(status: WakePlanStatus.deleted, isEnabled: false),
      ]) {
        final result = planner.plan(
          wakePlan: plan,
          startDay: monday,
          endExclusive: tuesday,
          now: DateTime(2026, 7, 6, 5),
        );

        expect(result.wakeInstances, isEmpty);
        expect(result.previewOccurrences, isEmpty);
        expect(result.schedulingCandidates, isEmpty);
      }
    });

    test('rejects inverted ranges', () {
      expect(
        () => planner.plan(
          wakePlan: buildPlan(),
          startDay: tuesday,
          endExclusive: monday,
          now: DateTime(2026, 7, 6, 5),
        ),
        throwsArgumentError,
      );
    });
  });
}
