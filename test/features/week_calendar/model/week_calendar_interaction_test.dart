import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/week_calendar/week_calendar.dart';
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
}
