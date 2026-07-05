import 'calendar_day.dart';
import 'time_of_day_minutes.dart';

class DateMinute implements Comparable<DateMinute> {
  const DateMinute({required this.day, required this.time});

  factory DateMinute.fromDateTime(DateTime dateTime) {
    return DateMinute(
      day: CalendarDay.fromDateTime(dateTime),
      time: TimeOfDayMinutes.fromDateTime(dateTime),
    );
  }

  final CalendarDay day;
  final TimeOfDayMinutes time;

  DateTime toDateTime() {
    return day.at(time);
  }

  DateMinute addMinutes(int minutes) {
    final totalMinutes = time.minutesSinceMidnight + minutes;
    final dayDelta = _floorDivide(totalMinutes, TimeOfDayMinutes.minutesPerDay);
    final minuteOfDay = totalMinutes % TimeOfDayMinutes.minutesPerDay;

    return DateMinute(
      day: day.addDays(dayDelta),
      time: TimeOfDayMinutes.fromMinutesSinceMidnight(minuteOfDay),
    );
  }

  @override
  int compareTo(DateMinute other) {
    final dayComparison = day.compareTo(other.day);
    if (dayComparison != 0) {
      return dayComparison;
    }

    return time.compareTo(other.time);
  }

  @override
  bool operator ==(Object other) {
    return other is DateMinute && day == other.day && time == other.time;
  }

  @override
  int get hashCode => Object.hash(day, time);

  @override
  String toString() => '$day ${time.toString()}';
}

int _floorDivide(int dividend, int divisor) {
  if (dividend >= 0) {
    return dividend ~/ divisor;
  }

  return -((-dividend + divisor - 1) ~/ divisor);
}
