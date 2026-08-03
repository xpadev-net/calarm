import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHolidayIcs', () {
    test('parses a simple VEVENT into a Holiday', () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VEVENT\r\n'
          'UID:19550101-jp@holidays-ical.xpadev.net\r\n'
          'DTSTAMP:19550101T000000Z\r\n'
          'DTSTART;VALUE=DATE:19550101\r\n'
          'DTEND;VALUE=DATE:19550102\r\n'
          'SUMMARY:元日\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';

      final holidays = parseHolidayIcs(ics);

      expect(holidays, [
        Holiday(date: CalendarDay(year: 1955, month: 1, day: 1), name: '元日'),
      ]);
    });

    test('parses multiple VEVENTs', () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'DTSTART;VALUE=DATE:19550101\r\n'
          'SUMMARY:元日\r\n'
          'END:VEVENT\r\n'
          'BEGIN:VEVENT\r\n'
          'DTSTART;VALUE=DATE:19550115\r\n'
          'SUMMARY:成人の日\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';

      final holidays = parseHolidayIcs(ics);

      expect(holidays, hasLength(2));
      expect(holidays[0].name, '元日');
      expect(holidays[1].name, '成人の日');
    });

    test('unfolds a continuation line before extracting SUMMARY', () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'DTSTART;VALUE=DATE:19550101\r\n'
          'SUMMARY:a very long holiday name that wraps across a fold\r\n'
          ' ed continuation line\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';

      final holidays = parseHolidayIcs(ics);

      expect(
        holidays.single.name,
        'a very long holiday name that wraps across a folded continuation line',
      );
    });

    test('unescapes commas, semicolons, and backslashes in SUMMARY', () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'DTSTART;VALUE=DATE:19550101\r\n'
          r'SUMMARY:a\, b\; c\\d'
          '\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';

      final holidays = parseHolidayIcs(ics);

      expect(holidays.single.name, r'a, b; c\d');
    });

    test('throws HolidayIcsParseException when DTSTART is missing', () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'SUMMARY:元日\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';

      expect(
        () => parseHolidayIcs(ics),
        throwsA(isA<HolidayIcsParseException>()),
      );
    });

    test('throws HolidayIcsParseException when SUMMARY is missing', () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'DTSTART;VALUE=DATE:19550101\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';

      expect(
        () => parseHolidayIcs(ics),
        throwsA(isA<HolidayIcsParseException>()),
      );
    });

    test('throws HolidayIcsParseException on an invalid date', () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'DTSTART;VALUE=DATE:20260231\r\n'
          'SUMMARY:元日\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';

      expect(
        () => parseHolidayIcs(ics),
        throwsA(isA<HolidayIcsParseException>()),
      );
    });

    test('throws HolidayIcsParseException on an unterminated VEVENT', () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'DTSTART;VALUE=DATE:19550101\r\n'
          'SUMMARY:元日\r\n'
          'END:VCALENDAR\r\n';

      expect(
        () => parseHolidayIcs(ics),
        throwsA(isA<HolidayIcsParseException>()),
      );
    });

    test('returns an empty list for a calendar with no events', () {
      const ics = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n';

      expect(parseHolidayIcs(ics), isEmpty);
    });
  });
}
