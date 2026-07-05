import 'calendar_day.dart';

class WeekRange {
  factory WeekRange({
    required CalendarDay start,
    int visibleDays = DateTime.daysPerWeek,
  }) {
    if (visibleDays <= 0) {
      throw ArgumentError.value(visibleDays, 'visibleDays', 'must be positive');
    }

    return WeekRange._(start: start, visibleDays: visibleDays);
  }

  const WeekRange._({required this.start, required this.visibleDays});

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
