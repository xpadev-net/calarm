import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/week_calendar/model/week_calendar_interaction.dart';
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
        page.addPages(1).week.start,
        CalendarDay(year: 2026, month: 7, day: 12),
      );
      expect(
        page.addPages(-1).week.start,
        CalendarDay(year: 2026, month: 6, day: 28),
      );
    });

    test('builds three-day periods from today and pages by three days', () {
      final page = WeekCalendarPage.fromAnchor(
        DateTime(2026, 7, 8, 9),
        visibleDays: 3,
      );

      expect(page.days, hasLength(3));
      expect(page.week.start, CalendarDay(year: 2026, month: 7, day: 8));
      expect(
        page.addPages(1).week.start,
        CalendarDay(year: 2026, month: 7, day: 11),
      );
      expect(
        page.addPages(-1).week.start,
        CalendarDay(year: 2026, month: 7, day: 5),
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

    test('maps x position across a three-day range', () {
      final range = WeekRange(start: monday, visibleDays: 3);
      final target = weekCalendarTapTargetFromPosition(
        week: range,
        localX: 250,
        localY: 420,
        gridWidth: 300,
        gridHeight: 1440,
      );

      expect(target.day, CalendarDay(year: 2026, month: 7, day: 8));
      expect(target.time, TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0));
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

  group('WeekCalendarDraft', () {
    final target = WeekCalendarTapTarget(
      day: CalendarDay(year: 2026, month: 7, day: 8),
      time: TimeOfDayMinutes.fromHourMinute(hour: 23, minute: 55),
    );

    test('uses the tapped time as start and supports cross-midnight end', () {
      final draft = weekCalendarDraftFromTap(
        id: 'draft-1',
        target: target,
        defaultDuration: const Duration(minutes: 60),
        createdAt: DateTime(2026, 7, 8, 5, 30),
      );

      expect(draft.startAt, DateTime(2026, 7, 8, 23, 55));
      expect(draft.endAt, DateTime(2026, 7, 9, 0, 55));
      expect(draft.duration, const Duration(minutes: 60));
    });

    test('snaps adjustments and clamps resize to five minutes and 3 hours', () {
      final draft = weekCalendarDraftFromTap(
        id: 'draft-1',
        target: target,
        defaultDuration: const Duration(minutes: 60),
        createdAt: DateTime(2026, 7, 8, 5, 30),
      );

      final minimum = draft.resizeStartBy(const Duration(minutes: 100));
      final maximum = draft.resizeStartBy(const Duration(hours: -5));
      final snapped = draft.resizeEndBy(const Duration(minutes: 7));

      expect(minimum.duration, weekCalendarDraftMinimumDuration);
      expect(maximum.duration, weekCalendarDraftMaximumDuration);
      expect(snapped.endAt, DateTime(2026, 7, 9, 1, 0));
    });

    test('moves by absolute day and snapped minute deltas', () {
      final draft = weekCalendarDraftFromTap(
        id: 'draft-1',
        target: target,
        defaultDuration: const Duration(minutes: 60),
        createdAt: DateTime(2026, 7, 8, 5, 30),
      );

      final moved = draft.moveBy(days: 1, minutes: -65);

      expect(moved.startAt, DateTime(2026, 7, 9, 22, 50));
      expect(moved.endAt, DateTime(2026, 7, 9, 23, 50));
      expect(moved.id, draft.id);
      expect(moved.createdAt, draft.createdAt);
    });

    test('keeps wall-clock time when moving across a DST boundary', () {
      final draft = WeekCalendarDraft(
        id: 'dst-draft',
        startAt: DateTime(2026, 3, 7, 12, 10),
        endAt: DateTime(2026, 3, 7, 13, 10),
        createdAt: DateTime(2026, 3, 1),
      );

      final moved = draft.moveBy(days: 1, minutes: 7);

      expect(moved.startAt, DateTime(2026, 3, 8, 12, 15));
      expect(moved.endAt, DateTime(2026, 3, 8, 13, 15));
      expect(moved.duration, draft.duration);
    });

    test('keeps elapsed duration across the spring DST transition', () {
      final draft = WeekCalendarDraft(
        id: 'spring-dst-draft',
        startAt: DateTime(2026, 3, 7, 1, 30),
        endAt: DateTime(2026, 3, 7, 3),
        createdAt: DateTime(2026, 3, 1),
      );

      final moved = draft.moveBy(days: 1, minutes: 0);

      expect(moved.startAt, DateTime(2026, 3, 8, 1, 30));
      expect(moved.duration, draft.duration);
      if (moved.startAt.timeZoneOffset != moved.endAt.timeZoneOffset) {
        expect(moved.endAt, DateTime(2026, 3, 8, 4));
      }
    });

    test('keeps maximum duration across the fall DST transition', () {
      final draft = WeekCalendarDraft(
        id: 'fall-dst-draft',
        startAt: DateTime(2026, 10, 31, 0, 30),
        endAt: DateTime(2026, 10, 31, 3, 30),
        createdAt: DateTime(2026, 10, 1),
      );

      final moved = draft.moveBy(days: 1, minutes: 0);

      expect(moved.startAt, DateTime(2026, 11, 1, 0, 30));
      expect(moved.duration, weekCalendarDraftMaximumDuration);
      if (moved.startAt.timeZoneOffset != moved.endAt.timeZoneOffset) {
        expect(moved.endAt, DateTime(2026, 11, 1, 2, 30));
      }
    });

    test('moves by calendar days across month and year boundaries', () {
      final draft = WeekCalendarDraft(
        id: 'year-boundary-draft',
        startAt: DateTime(2026, 12, 31, 23, 45),
        endAt: DateTime(2027, 1, 1, 0, 45),
        createdAt: DateTime(2026, 12, 1),
      );

      final moved = draft.moveBy(days: 1, minutes: 0);

      expect(moved.startAt, DateTime(2027, 1, 1, 23, 45));
      expect(moved.endAt, DateTime(2027, 1, 2, 0, 45));
      expect(moved.duration, draft.duration);
    });

    test('clamps invalid configured durations into supported bounds', () {
      final short = weekCalendarDraftFromTap(
        id: 'short',
        target: target,
        defaultDuration: Duration.zero,
        createdAt: DateTime(2026, 7, 8),
      );
      final long = weekCalendarDraftFromTap(
        id: 'long',
        target: target,
        defaultDuration: const Duration(hours: 4),
        createdAt: DateTime(2026, 7, 8),
      );
      final snapped = weekCalendarDraftFromTap(
        id: 'snapped',
        target: target,
        defaultDuration: const Duration(minutes: 8),
        createdAt: DateTime(2026, 7, 8),
      );

      expect(short.duration, weekCalendarDraftMinimumDuration);
      expect(long.duration, weekCalendarDraftMaximumDuration);
      expect(snapped.duration, const Duration(minutes: 10));
    });
  });

  group('clampWeekCalendarDraftToRange', () {
    WeekCalendarDraft draft(DateTime startAt, DateTime endAt) {
      return WeekCalendarDraft(
        id: 'draft',
        startAt: startAt,
        endAt: endAt,
        createdAt: DateTime(2026, 7, 1),
      );
    }

    test('moves a draft that partially crosses the start into the range', () {
      final original = draft(
        DateTime(2026, 7, 5, 23, 30),
        DateTime(2026, 7, 6, 0, 30),
      );

      final clamped = clampWeekCalendarDraftToRange(
        draft: original,
        week: week,
      );

      expect(clamped.startAt, DateTime(2026, 7, 6));
      expect(clamped.endAt, DateTime(2026, 7, 6, 1));
      expect(clamped.duration, original.duration);
    });

    test('moves a draft that partially crosses the end into the range', () {
      final original = draft(
        DateTime(2026, 7, 12, 23, 30),
        DateTime(2026, 7, 13, 0, 30),
      );

      final clamped = clampWeekCalendarDraftToRange(
        draft: original,
        week: week,
      );

      expect(clamped.startAt, DateTime(2026, 7, 12, 23));
      expect(clamped.endAt, DateTime(2026, 7, 13));
      expect(clamped.duration, original.duration);
    });

    test('moves a draft completely before the range to the start', () {
      final original = draft(
        DateTime(2026, 7, 4, 10),
        DateTime(2026, 7, 4, 11, 30),
      );

      final clamped = clampWeekCalendarDraftToRange(
        draft: original,
        week: week,
      );

      expect(clamped.startAt, DateTime(2026, 7, 6));
      expect(clamped.endAt, DateTime(2026, 7, 6, 1, 30));
      expect(clamped.duration, original.duration);
    });

    test('moves a draft completely after the range to the end', () {
      final original = draft(
        DateTime(2026, 7, 14, 10),
        DateTime(2026, 7, 14, 11, 30),
      );

      final clamped = clampWeekCalendarDraftToRange(
        draft: original,
        week: week,
      );

      expect(clamped.startAt, DateTime(2026, 7, 12, 22, 30));
      expect(clamped.endAt, DateTime(2026, 7, 13));
      expect(clamped.duration, original.duration);
    });

    test('returns an in-range draft unchanged', () {
      final original = draft(
        DateTime(2026, 7, 8, 10),
        DateTime(2026, 7, 8, 11, 30),
      );

      final clamped = clampWeekCalendarDraftToRange(
        draft: original,
        week: week,
      );

      expect(identical(clamped, original), isTrue);
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
