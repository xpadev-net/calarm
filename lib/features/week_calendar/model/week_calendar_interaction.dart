import '../../../core/time/time.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';

const int weekCalendarStartMinute = 0;
const int weekCalendarEndMinute = TimeOfDayMinutes.minutesPerDay;
const int weekCalendarDefaultScrollMinute = 5 * TimeOfDayMinutes.minutesPerHour;

class WeekCalendarPage {
  WeekCalendarPage({required this.week});

  factory WeekCalendarPage.fromAnchor(DateTime anchor) {
    return WeekCalendarPage(week: visibleWeekRange(anchor));
  }

  final WeekRange week;

  List<CalendarDay> get days => week.days;

  bool contains(CalendarDay day) => week.contains(day);

  WeekCalendarPage addWeeks(int weeks) {
    return WeekCalendarPage(
      week: WeekRange(start: week.start.addDays(weeks * DateTime.daysPerWeek)),
    );
  }
}

class WeekCalendarScrollTarget {
  const WeekCalendarScrollTarget({
    required this.minute,
    required this.offset,
    required this.isCurrentWeek,
  });

  final int minute;
  final double offset;
  final bool isCurrentWeek;
}

class WeekCalendarTapTarget {
  const WeekCalendarTapTarget({required this.day, required this.time});

  final CalendarDay day;
  final TimeOfDayMinutes time;

  DateTime get dateTime => day.at(time);
}

WeekCalendarScrollTarget initialWeekCalendarScrollTarget({
  required WeekRange week,
  required DateTime now,
  required double pixelsPerMinute,
  double leadingContextPixels = 96,
}) {
  if (pixelsPerMinute <= 0) {
    throw ArgumentError.value(
      pixelsPerMinute,
      'pixelsPerMinute',
      'must be positive',
    );
  }
  if (leadingContextPixels < 0) {
    throw ArgumentError.value(
      leadingContextPixels,
      'leadingContextPixels',
      'must not be negative',
    );
  }

  final today = CalendarDay.fromDateTime(now);
  final isCurrentWeek = week.contains(today);
  final targetMinute = isCurrentWeek
      ? now.hour * TimeOfDayMinutes.minutesPerHour + now.minute
      : weekCalendarDefaultScrollMinute;
  final offset = (targetMinute * pixelsPerMinute) - leadingContextPixels;

  return WeekCalendarScrollTarget(
    minute: targetMinute,
    offset: offset < 0 ? 0 : offset,
    isCurrentWeek: isCurrentWeek,
  );
}

WeekCalendarTapTarget weekCalendarTapTargetFromPosition({
  required WeekRange week,
  required double localX,
  required double localY,
  required double gridWidth,
  required double gridHeight,
}) {
  if (gridWidth <= 0) {
    throw ArgumentError.value(gridWidth, 'gridWidth', 'must be positive');
  }
  if (gridHeight <= 0) {
    throw ArgumentError.value(gridHeight, 'gridHeight', 'must be positive');
  }

  final dayWidth = gridWidth / week.visibleDays;
  final dayIndex = (localX / dayWidth).floor().clamp(0, week.visibleDays - 1);
  final rawMinute = (localY / gridHeight) * TimeOfDayMinutes.minutesPerDay;
  final boundedMinute = rawMinute.clamp(
    weekCalendarStartMinute.toDouble(),
    weekCalendarEndMinute.toDouble(),
  );
  final wholeMinute = boundedMinute.round().clamp(
    weekCalendarStartMinute,
    weekCalendarEndMinute,
  );
  final rounded = wholeMinute == TimeOfDayMinutes.minutesPerDay
      ? RoundedTimeOfDayMinutes(
          time: TimeOfDayMinutes.fromMinutesSinceMidnight(0),
          dayOffset: 1,
        )
      : roundMinutesSinceMidnightToNearestInterval(
          wholeMinute,
          intervalMinutes: minimumWakePlanInterval.inMinutes,
        );

  return WeekCalendarTapTarget(
    day: week.start.addDays(dayIndex + rounded.dayOffset),
    time: rounded.time,
  );
}
