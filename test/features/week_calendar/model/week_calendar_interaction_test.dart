import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/week_calendar/week_calendar.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final monday = CalendarDay(year: 2026, month: 7, day: 6);
  final week = WeekRange(start: monday);

  group('WeekCalendarPage', () {
    test('builds visible weeks from an anchor and pages by seven days', () {
      final page = WeekCalendarPage.fromAnchor(DateTime(2026, 7, 8, 9));

      expect(page.days, hasLength(DateTime.daysPerWeek));
      expect(page.week.start, CalendarDay(year: 2026, month: 7, day: 5));
      expect(
        page.addWeeks(1).week.start,
        CalendarDay(year: 2026, month: 7, day: 12),
      );
      expect(
        page.addWeeks(-1).week.start,
        CalendarDay(year: 2026, month: 6, day: 28),
      );
    });
  });

  group('initialWeekCalendarScrollTarget', () {
    test('uses current time for the current week with leading context', () {
      final target = initialWeekCalendarScrollTarget(
        week: week,
        now: DateTime(2026, 7, 8, 7, 42),
        pixelsPerMinute: 2,
        leadingContextPixels: 60,
      );

      expect(target.isCurrentWeek, isTrue);
      expect(target.minute, 7 * 60 + 42);
      expect(target.offset, ((7 * 60 + 42) * 2) - 60);
    });

    test('uses 05:00 for non-current weeks', () {
      final target = initialWeekCalendarScrollTarget(
        week: week,
        now: DateTime(2026, 7, 20, 22),
        pixelsPerMinute: 1,
      );

      expect(target.isCurrentWeek, isFalse);
      expect(target.minute, 5 * 60);
      expect(target.offset, 204);
    });
  });

  group('weekCalendarTapTargetFromPosition', () {
    test(
      'maps x position to day and y position to nearest five-minute time',
      () {
        final target = weekCalendarTapTargetFromPosition(
          week: week,
          localX: 250,
          localY: 423,
          gridWidth: 700,
          gridHeight: 1440,
        );

        expect(target.day, CalendarDay(year: 2026, month: 7, day: 8));
        expect(
          target.time,
          TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 5),
        );
      },
    );

    test('clamps before-grid taps to week start at midnight', () {
      final target = weekCalendarTapTargetFromPosition(
        week: week,
        localX: -20,
        localY: -20,
        gridWidth: 700,
        gridHeight: 1440,
      );

      expect(target.day, monday);
      expect(target.time, TimeOfDayMinutes.fromHourMinute(hour: 0, minute: 0));
    });

    test('keeps a 24:00 internal boundary by returning next-day midnight', () {
      final target = weekCalendarTapTargetFromPosition(
        week: week,
        localX: 699,
        localY: 1440,
        gridWidth: 700,
        gridHeight: 1440,
      );

      expect(target.day, CalendarDay(year: 2026, month: 7, day: 13));
      expect(target.time, TimeOfDayMinutes.fromHourMinute(hour: 0, minute: 0));
    });
  });

  group('weekCalendarWakePlanBlocks', () {
    test('projects a plan from start offset to target', () {
      final blocks = weekCalendarWakePlanBlocks(
        week: week,
        wakePlans: [
          buildPlan(
            id: 'plan-1',
            targetDay: CalendarDay(year: 2026, month: 7, day: 8),
            targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
            startOffset: const Duration(minutes: 60),
            interval: const Duration(minutes: 5),
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.day, CalendarDay(year: 2026, month: 7, day: 8));
      expect(blocks.single.topMinute, 6 * 60);
      expect(blocks.single.durationMinutes, 60);
      expect(blocks.single.occurrenceCount, 13);
      expect(blocks.single.containsTarget, isTrue);
    });

    test('splits cross-midnight plans into visible day segments', () {
      final blocks = weekCalendarWakePlanBlocks(
        week: week,
        wakePlans: [
          buildPlan(
            id: 'plan-1',
            targetDay: CalendarDay(year: 2026, month: 7, day: 8),
            targetTime: TimeOfDayMinutes.fromHourMinute(hour: 0, minute: 30),
            startOffset: const Duration(minutes: 90),
            interval: const Duration(minutes: 15),
          ),
        ],
      );

      expect(blocks, hasLength(2));
      expect(blocks[0].day, CalendarDay(year: 2026, month: 7, day: 7));
      expect(blocks[0].topMinute, 23 * 60);
      expect(blocks[0].durationMinutes, 60);
      expect(blocks[0].containsTarget, isFalse);
      expect(blocks[1].day, CalendarDay(year: 2026, month: 7, day: 8));
      expect(blocks[1].topMinute, 0);
      expect(blocks[1].durationMinutes, 30);
      expect(blocks[1].containsTarget, isTrue);
      expect(blocks[1].occurrenceCount, 7);
    });

    test(
      'includes a block that starts in the visible week for next target day',
      () {
        final blocks = weekCalendarWakePlanBlocks(
          week: week,
          wakePlans: [
            buildPlan(
              id: 'plan-1',
              targetDay: week.endExclusive,
              targetTime: TimeOfDayMinutes.fromHourMinute(hour: 0, minute: 20),
              startOffset: const Duration(minutes: 80),
              interval: const Duration(minutes: 10),
            ),
          ],
        );

        expect(blocks, hasLength(1));
        expect(blocks.single.day, CalendarDay(year: 2026, month: 7, day: 12));
        expect(blocks.single.topMinute, 23 * 60);
        expect(blocks.single.durationMinutes, 60);
        expect(blocks.single.containsTarget, isFalse);
      },
    );

    test('assigns overlapping plans to separate lanes', () {
      final blocks = weekCalendarWakePlanBlocks(
        week: week,
        wakePlans: [
          buildPlan(
            id: 'plan-1',
            targetDay: CalendarDay(year: 2026, month: 7, day: 8),
            targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
            startOffset: const Duration(minutes: 60),
          ),
          buildPlan(
            id: 'plan-2',
            targetDay: CalendarDay(year: 2026, month: 7, day: 8),
            targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 30),
            startOffset: const Duration(minutes: 60),
          ),
        ],
      );

      expect(blocks, hasLength(2));
      expect(blocks.map((block) => block.laneCount), everyElement(2));
      expect(blocks.map((block) => block.laneIndex).toSet(), {0, 1});
    });

    test('keeps a shared width for staggered overlap groups', () {
      final blocks = weekCalendarWakePlanBlocks(
        week: week,
        wakePlans: [
          buildPlan(
            id: 'plan-1',
            targetDay: CalendarDay(year: 2026, month: 7, day: 8),
            targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
            startOffset: const Duration(minutes: 60),
          ),
          buildPlan(
            id: 'plan-2',
            targetDay: CalendarDay(year: 2026, month: 7, day: 8),
            targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 30),
            startOffset: const Duration(minutes: 60),
          ),
          buildPlan(
            id: 'plan-3',
            targetDay: CalendarDay(year: 2026, month: 7, day: 8),
            targetTime: TimeOfDayMinutes.fromHourMinute(hour: 8, minute: 0),
            startOffset: const Duration(minutes: 60),
          ),
        ],
      );

      expect(blocks, hasLength(3));
      expect(blocks.map((block) => block.laneCount), everyElement(2));
      expect(blocks.map((block) => block.laneIndex), [0, 1, 0]);
    });
  });
}

WakePlan buildPlan({
  required String id,
  required CalendarDay targetDay,
  required TimeOfDayMinutes targetTime,
  Duration startOffset = const Duration(minutes: 60),
  Duration interval = const Duration(minutes: 5),
}) {
  final now = DateTime(2026, 7, 1, 12);

  return WakePlan(
    id: id,
    title: id,
    targetTime: targetTime,
    startOffset: startOffset,
    interval: interval,
    repeatRule: RepeatRule.oneTime(targetDay),
    isEnabled: true,
    status: WakePlanStatus.scheduled,
    soundId: 'default',
    vibrationEnabled: true,
    createdAt: now,
    updatedAt: now,
  );
}
