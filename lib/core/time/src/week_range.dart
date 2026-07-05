import 'calendar_day.dart';

class WeekRange {
  const WeekRange({
    required this.start,
    this.visibleDays = DateTime.daysPerWeek,
  }) : assert(visibleDays > 0);

  final CalendarDay start;
  final int visibleDays;

  CalendarDay get endExclusive => start.addDays(visibleDays);

  List<CalendarDay> get days {
    return List.generate(visibleDays, start.addDays);
  }

  bool contains(CalendarDay day) {
    return day.compareTo(start) >= 0 && day.compareTo(endExclusive) < 0;
  }
}
