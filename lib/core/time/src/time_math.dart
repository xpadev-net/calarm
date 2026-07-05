import 'calendar_day.dart';
import 'date_minute.dart';
import 'time_of_day_minutes.dart';
import 'week_range.dart';

const Duration defaultTimeSnapInterval = Duration(minutes: 5);

CalendarDay weekStartSunday(CalendarDay day) {
  final daysSinceSunday = day.weekday % DateTime.daysPerWeek;
  return day.addDays(-daysSinceSunday);
}

WeekRange visibleWeekRange(DateTime anchor) {
  return WeekRange(start: weekStartSunday(CalendarDay.fromDateTime(anchor)));
}

TimeOfDayMinutes roundMinutesSinceMidnightToNearestInterval(
  int minutesSinceMidnight, {
  int intervalMinutes = 5,
}) {
  if (minutesSinceMidnight < 0 ||
      minutesSinceMidnight >= TimeOfDayMinutes.minutesPerDay) {
    throw RangeError.range(
      minutesSinceMidnight,
      0,
      TimeOfDayMinutes.minutesPerDay - 1,
      'minutesSinceMidnight',
    );
  }
  if (intervalMinutes <= 0 ||
      TimeOfDayMinutes.minutesPerDay % intervalMinutes != 0) {
    throw ArgumentError.value(
      intervalMinutes,
      'intervalMinutes',
      'must be a positive divisor of ${TimeOfDayMinutes.minutesPerDay}',
    );
  }

  final lower = (minutesSinceMidnight ~/ intervalMinutes) * intervalMinutes;
  final remainder = minutesSinceMidnight - lower;
  final upper = lower + intervalMinutes;
  final rounded = remainder * 2 < intervalMinutes ? lower : upper;

  return TimeOfDayMinutes.fromMinutesSinceMidnight(
    rounded % TimeOfDayMinutes.minutesPerDay,
  );
}

DateMinute roundDateTimeToNearestInterval(
  DateTime dateTime, {
  Duration interval = defaultTimeSnapInterval,
}) {
  if (interval <= Duration.zero) {
    throw ArgumentError.value(interval, 'interval', 'must be positive');
  }
  final intervalMicros = interval.inMicroseconds;
  final elapsed = dateTime.difference(
    CalendarDay.fromDateTime(dateTime).startOfDay,
  );
  final elapsedMicros = elapsed.inMicroseconds;
  final lowerSteps = elapsedMicros ~/ intervalMicros;
  final lowerMicros = lowerSteps * intervalMicros;
  final remainder = elapsedMicros - lowerMicros;
  final roundedMicros = remainder * 2 < intervalMicros
      ? lowerMicros
      : lowerMicros + intervalMicros;
  final roundedDateTime = CalendarDay.fromDateTime(
    dateTime,
  ).startOfDay.add(Duration(microseconds: roundedMicros));

  return DateMinute.fromDateTime(roundedDateTime);
}

bool isRoundedTargetInPast(
  DateTime target, {
  required DateTime now,
  Duration interval = defaultTimeSnapInterval,
}) {
  return roundDateTimeToNearestInterval(
    target,
    interval: interval,
  ).toDateTime().isBefore(now);
}

DateTime targetStartAt({
  required DateTime targetAt,
  required Duration startOffset,
}) {
  if (startOffset < Duration.zero) {
    throw ArgumentError.value(
      startOffset,
      'startOffset',
      'must not be negative',
    );
  }

  return targetAt.subtract(startOffset);
}
