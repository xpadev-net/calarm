import '../../../../core/time/time.dart';

enum RepeatType { oneTime, weekly }

enum Weekday {
  monday(DateTime.monday),
  tuesday(DateTime.tuesday),
  wednesday(DateTime.wednesday),
  thursday(DateTime.thursday),
  friday(DateTime.friday),
  saturday(DateTime.saturday),
  sunday(DateTime.sunday);

  const Weekday(this.dateTimeValue);

  final int dateTimeValue;

  static Weekday fromDateTimeValue(int value) {
    for (final weekday in Weekday.values) {
      if (weekday.dateTimeValue == value) {
        return weekday;
      }
    }

    throw RangeError.range(value, DateTime.monday, DateTime.sunday, 'weekday');
  }
}

class RepeatRule {
  factory RepeatRule.oneTime(CalendarDay date) {
    return RepeatRule._(
      type: RepeatType.oneTime,
      oneTimeDate: date,
      weekdays: const {},
    );
  }

  factory RepeatRule.weekly(Set<Weekday> weekdays) {
    if (weekdays.isEmpty) {
      throw ArgumentError.value(
        weekdays,
        'weekdays',
        'must include at least one weekday',
      );
    }

    return RepeatRule._(
      type: RepeatType.weekly,
      oneTimeDate: null,
      weekdays: Set.unmodifiable(weekdays),
    );
  }

  const RepeatRule._({
    required this.type,
    required this.oneTimeDate,
    required this.weekdays,
  });

  final RepeatType type;
  final CalendarDay? oneTimeDate;
  final Set<Weekday> weekdays;

  bool includes(CalendarDay day) {
    return switch (type) {
      RepeatType.oneTime => oneTimeDate == day,
      RepeatType.weekly => weekdays.contains(
        Weekday.fromDateTimeValue(day.weekday),
      ),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is RepeatRule &&
        type == other.type &&
        oneTimeDate == other.oneTimeDate &&
        _setEquals(weekdays, other.weekdays);
  }

  @override
  int get hashCode {
    final orderedWeekdays = Weekday.values.where(weekdays.contains);

    return Object.hash(type, oneTimeDate, Object.hashAll(orderedWeekdays));
  }

  @override
  String toString() {
    return switch (type) {
      RepeatType.oneTime => 'RepeatRule.oneTime($oneTimeDate)',
      RepeatType.weekly => 'RepeatRule.weekly($weekdays)',
    };
  }
}

bool _setEquals<T>(Set<T> left, Set<T> right) {
  return left.length == right.length && left.containsAll(right);
}
