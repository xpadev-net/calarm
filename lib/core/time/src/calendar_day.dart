import 'time_of_day_minutes.dart';

class CalendarDay implements Comparable<CalendarDay> {
  factory CalendarDay({
    required int year,
    required int month,
    required int day,
  }) {
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw ArgumentError.value(
        '$year-$month-$day',
        'date',
        'must be a valid calendar date',
      );
    }

    return CalendarDay._(year: year, month: month, day: day);
  }

  factory CalendarDay.fromDateTime(DateTime dateTime) {
    return CalendarDay(
      year: dateTime.year,
      month: dateTime.month,
      day: dateTime.day,
    );
  }

  const CalendarDay._({
    required this.year,
    required this.month,
    required this.day,
  });

  final int year;
  final int month;
  final int day;

  DateTime get startOfDay => DateTime(year, month, day);

  int get weekday => DateTime.utc(year, month, day).weekday;

  int get daysSinceUnixEpoch {
    return DateTime.utc(year, month, day).difference(DateTime.utc(1970)).inDays;
  }

  CalendarDay addDays(int days) {
    return CalendarDay.fromDateTime(DateTime.utc(year, month, day + days));
  }

  int differenceInDays(CalendarDay other) {
    return daysSinceUnixEpoch - other.daysSinceUnixEpoch;
  }

  DateTime at(TimeOfDayMinutes time) {
    return DateTime(year, month, day, time.hour, time.minute);
  }

  @override
  int compareTo(CalendarDay other) {
    final yearComparison = year.compareTo(other.year);
    if (yearComparison != 0) {
      return yearComparison;
    }
    final monthComparison = month.compareTo(other.month);
    if (monthComparison != 0) {
      return monthComparison;
    }

    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarDay &&
        year == other.year &&
        month == other.month &&
        day == other.day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() {
    return '$year-${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }
}
