import 'package:calarm/core/time/time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimeOfDayMinutes', () {
    test('stores minutes since midnight', () {
      final time = TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 30);

      expect(time.minutesSinceMidnight, 390);
      expect(time.hour, 6);
      expect(time.minute, 30);
    });

    test('rejects minutes outside one local day', () {
      expect(
        () => TimeOfDayMinutes.fromMinutesSinceMidnight(-1),
        throwsRangeError,
      );
      expect(
        () => TimeOfDayMinutes.fromMinutesSinceMidnight(1440),
        throwsRangeError,
      );
    });
  });

  group('CalendarDay and DateMinute', () {
    test('convert between date plus minutes and DateTime at boundaries', () {
      final day = CalendarDay(year: 2026, month: 7, day: 5);
      final time = TimeOfDayMinutes.fromMinutesSinceMidnight(0);
      final dateMinute = DateMinute(day: day, time: time);

      expect(dateMinute.toDateTime(), DateTime(2026, 7, 5));
      expect(
        dateMinute.addMinutes(-1),
        DateMinute.fromDateTime(DateTime(2026, 7, 4, 23, 59)),
      );
      expect(
        dateMinute.addMinutes(1440),
        DateMinute.fromDateTime(DateTime(2026, 7, 6)),
      );
    });

    test('uses calendar-day arithmetic across month and year boundaries', () {
      final day = CalendarDay(year: 2026, month: 12, day: 31);

      expect(day.addDays(1), CalendarDay(year: 2027, month: 1, day: 1));
      expect(
        CalendarDay(year: 2027, month: 1, day: 2).differenceInDays(day),
        2,
      );
    });

    test('rejects invalid calendar dates instead of normalizing them', () {
      expect(
        () => CalendarDay(year: 2026, month: 2, day: 31),
        throwsArgumentError,
      );
    });

    test('compares date plus minutes without local DateTime conversion', () {
      final before = DateMinute.fromDateTime(DateTime(2026, 7, 5, 23, 59));
      final after = DateMinute.fromDateTime(DateTime(2026, 7, 6));

      expect(before.compareTo(after), isNegative);
      expect(before.addMinutes(1), after);
    });
  });

  group('week ranges', () {
    test('weekStartSunday returns the same day for Sunday', () {
      final sunday = CalendarDay(year: 2026, month: 7, day: 5);

      expect(weekStartSunday(sunday), sunday);
    });

    test('weekStartSunday backs up from weekdays to Sunday', () {
      final monday = CalendarDay(year: 2026, month: 7, day: 6);
      final saturday = CalendarDay(year: 2026, month: 7, day: 11);

      expect(
        weekStartSunday(monday),
        CalendarDay(year: 2026, month: 7, day: 5),
      );
      expect(
        weekStartSunday(saturday),
        CalendarDay(year: 2026, month: 7, day: 5),
      );
    });

    test('visibleWeekRange exposes a seven day Sunday based range', () {
      final range = visibleWeekRange(DateTime(2026, 7, 8, 12, 15));

      expect(range.start, CalendarDay(year: 2026, month: 7, day: 5));
      expect(range.endExclusive, CalendarDay(year: 2026, month: 7, day: 12));
      expect(range.days, [
        CalendarDay(year: 2026, month: 7, day: 5),
        CalendarDay(year: 2026, month: 7, day: 6),
        CalendarDay(year: 2026, month: 7, day: 7),
        CalendarDay(year: 2026, month: 7, day: 8),
        CalendarDay(year: 2026, month: 7, day: 9),
        CalendarDay(year: 2026, month: 7, day: 10),
        CalendarDay(year: 2026, month: 7, day: 11),
      ]);
      expect(
        range.contains(CalendarDay(year: 2026, month: 7, day: 11)),
        isTrue,
      );
      expect(
        range.contains(CalendarDay(year: 2026, month: 7, day: 12)),
        isFalse,
      );
    });
  });

  group('rounding', () {
    test('rounds minutes since midnight to nearest 5 minutes', () {
      expect(
        roundMinutesSinceMidnightToNearestInterval(7),
        TimeOfDayMinutes.fromHourMinute(hour: 0, minute: 5),
      );
      expect(
        roundMinutesSinceMidnightToNearestInterval(8),
        TimeOfDayMinutes.fromHourMinute(hour: 0, minute: 10),
      );
    });

    test('rounds exact DateTime midpoint forward', () {
      final rounded = roundDateTimeToNearestInterval(
        DateTime(2026, 7, 5, 9, 2, 30),
      );

      expect(rounded, DateMinute.fromDateTime(DateTime(2026, 7, 5, 9, 5)));
    });

    test('rounds across midnight into the next day', () {
      final rounded = roundDateTimeToNearestInterval(
        DateTime(2026, 7, 5, 23, 58),
      );

      expect(rounded, DateMinute.fromDateTime(DateTime(2026, 7, 6)));
    });

    test('detects targets that are past after rounding', () {
      final now = DateTime(2026, 7, 5, 10);

      expect(
        isRoundedTargetInPast(DateTime(2026, 7, 5, 9, 57), now: now),
        isTrue,
      );
      expect(
        isRoundedTargetInPast(DateTime(2026, 7, 5, 9, 58), now: now),
        isFalse,
      );
    });
  });

  group('targetStartAt', () {
    test('subtracts wake window offset across the previous day', () {
      final start = targetStartAt(
        targetAt: DateTime(2026, 7, 6, 0, 20),
        startOffset: const Duration(minutes: 45),
      );

      expect(start, DateTime(2026, 7, 5, 23, 35));
    });

    test('rejects negative offsets', () {
      expect(
        () => targetStartAt(
          targetAt: DateTime(2026, 7, 6, 0, 20),
          startOffset: const Duration(minutes: -1),
        ),
        throwsArgumentError,
      );
    });
  });
}
