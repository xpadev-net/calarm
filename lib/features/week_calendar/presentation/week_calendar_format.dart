import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../model/week_calendar_interaction.dart';

String weekCalendarWeekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => throw RangeError.range(weekday, DateTime.monday, DateTime.sunday),
  };
}

/// Saturdays get a blue accent, Sundays and public holidays a red one —
/// matching the convention most Japanese calendars use. [holidays] should
/// come from [activeHolidaySetProvider]/[WakePlan.occursOnConsideringHolidays]'s
/// same source so this always agrees with what's actually skipped.
enum WeekCalendarDateHeaderDayKind { normal, saturday, sundayOrHoliday }

WeekCalendarDateHeaderDayKind weekCalendarDateHeaderDayKind(
  CalendarDay day,
  Set<CalendarDay> holidays,
) {
  if (day.weekday == DateTime.sunday || holidays.contains(day)) {
    return WeekCalendarDateHeaderDayKind.sundayOrHoliday;
  }
  if (day.weekday == DateTime.saturday) {
    return WeekCalendarDateHeaderDayKind.saturday;
  }
  return WeekCalendarDateHeaderDayKind.normal;
}

Color? weekCalendarDateHeaderDayKindColor(WeekCalendarDateHeaderDayKind kind) {
  return switch (kind) {
    WeekCalendarDateHeaderDayKind.saturday => Colors.blue.shade600,
    WeekCalendarDateHeaderDayKind.sundayOrHoliday => Colors.red.shade600,
    WeekCalendarDateHeaderDayKind.normal => null,
  };
}

String weekCalendarWakePlanBlockLabel(WeekCalendarWakePlanBlock block) {
  return '${block.wakePlan.targetTime}\n'
      '${weekCalendarTimeLabel(block.startAt)}-${weekCalendarTimeLabel(block.targetAt)}\n'
      'Every ${block.wakePlan.interval.inMinutes} min\n'
      '${block.occurrenceCount} alarms';
}

String weekCalendarTimeLabel(DateTime dateTime) {
  return '${dateTime.hour.toString().padLeft(2, '0')}:'
      '${dateTime.minute.toString().padLeft(2, '0')}';
}

String weekCalendarAccessibleDateTime(DateTime dateTime) {
  return '${dateTime.year.toString().padLeft(4, '0')}-'
      '${dateTime.month.toString().padLeft(2, '0')}-'
      '${dateTime.day.toString().padLeft(2, '0')} '
      '${weekCalendarTimeLabel(dateTime)}';
}
