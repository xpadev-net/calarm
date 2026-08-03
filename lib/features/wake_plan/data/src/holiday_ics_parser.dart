import '../../../../core/time/time.dart';
import '../../domain/wake_plan_domain.dart';

class HolidayIcsParseException implements Exception {
  HolidayIcsParseException(this.message);

  final String message;

  @override
  String toString() => 'HolidayIcsParseException: $message';
}

/// Parses the narrow ICS shape produced by the `holidays-ical` generator:
/// one all-day VEVENT per holiday, `DTSTART;VALUE=DATE:YYYYMMDD` and
/// `SUMMARY:` only. Does not attempt general RRULE/timezone/VALARM support.
List<Holiday> parseHolidayIcs(String icsContent) {
  final lines = _unfoldLines(icsContent);
  final holidays = <Holiday>[];

  List<String>? currentEventLines;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      currentEventLines = <String>[];
      continue;
    }
    if (line == 'END:VEVENT') {
      if (currentEventLines == null) {
        throw HolidayIcsParseException('END:VEVENT without matching BEGIN');
      }
      holidays.add(_parseEvent(currentEventLines));
      currentEventLines = null;
      continue;
    }
    currentEventLines?.add(line);
  }

  if (currentEventLines != null) {
    throw HolidayIcsParseException('unterminated VEVENT block');
  }

  return holidays;
}

Holiday _parseEvent(List<String> eventLines) {
  String? dateText;
  String? summary;

  for (final line in eventLines) {
    if (line.startsWith('DTSTART')) {
      final colonIndex = line.indexOf(':');
      if (colonIndex == -1) {
        throw HolidayIcsParseException('malformed DTSTART line: $line');
      }
      dateText = line.substring(colonIndex + 1).trim();
    } else if (line.startsWith('SUMMARY:')) {
      summary = _unescapeText(line.substring('SUMMARY:'.length));
    }
  }

  if (dateText == null) {
    throw HolidayIcsParseException('VEVENT missing DTSTART');
  }
  if (summary == null) {
    throw HolidayIcsParseException('VEVENT missing SUMMARY');
  }

  return Holiday(date: _parseIcsDate(dateText), name: summary);
}

CalendarDay _parseIcsDate(String dateText) {
  if (dateText.length != 8) {
    throw HolidayIcsParseException('invalid DTSTART date: $dateText');
  }
  final year = int.tryParse(dateText.substring(0, 4));
  final month = int.tryParse(dateText.substring(4, 6));
  final day = int.tryParse(dateText.substring(6, 8));
  if (year == null || month == null || day == null) {
    throw HolidayIcsParseException('invalid DTSTART date: $dateText');
  }
  try {
    return CalendarDay(year: year, month: month, day: day);
  } on ArgumentError {
    throw HolidayIcsParseException('invalid DTSTART date: $dateText');
  }
}

String _unescapeText(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == '\\' && i + 1 < value.length) {
      final next = value[i + 1];
      switch (next) {
        case 'n':
        case 'N':
          buffer.write('\n');
          i++;
          continue;
        case ',':
        case ';':
        case '\\':
          buffer.write(next);
          i++;
          continue;
      }
    }
    buffer.write(char);
  }
  return buffer.toString();
}

List<String> _unfoldLines(String icsContent) {
  final rawLines = icsContent.split(RegExp(r'\r\n|\r|\n'));
  final unfolded = <String>[];
  for (final rawLine in rawLines) {
    if (rawLine.isEmpty) {
      continue;
    }
    if ((rawLine.startsWith(' ') || rawLine.startsWith('\t')) &&
        unfolded.isNotEmpty) {
      unfolded[unfolded.length - 1] += rawLine.substring(1);
    } else {
      unfolded.add(rawLine);
    }
  }
  return unfolded;
}
