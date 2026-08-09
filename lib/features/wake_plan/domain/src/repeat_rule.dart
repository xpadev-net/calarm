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
      until: null,
    );
  }

  factory RepeatRule.weekly(Set<Weekday> weekdays, {CalendarDay? until}) {
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
      until: until,
    );
  }

  const RepeatRule._({
    required this.type,
    required this.oneTimeDate,
    required this.weekdays,
    required this.until,
  });

  final RepeatType type;
  final CalendarDay? oneTimeDate;
  final Set<Weekday> weekdays;

  /// Exclusive: the first day no longer included by this rule. Used to
  /// implement "delete this and following occurrences" for a repeating
  /// series. Only meaningful for [RepeatType.weekly] — always null for
  /// [RepeatType.oneTime].
  final CalendarDay? until;

  bool includes(CalendarDay day) {
    if (until != null && day.compareTo(until!) >= 0) {
      return false;
    }

    return switch (type) {
      RepeatType.oneTime => oneTimeDate == day,
      RepeatType.weekly => weekdays.contains(
        Weekday.fromDateTimeValue(day.weekday),
      ),
    };
  }

  RepeatRule copyWith({CalendarDay? until}) {
    return RepeatRule._(
      type: type,
      oneTimeDate: oneTimeDate,
      weekdays: weekdays,
      until: until ?? this.until,
    );
  }

  /// Truncates this rule so it no longer includes [day] or any day after it.
  RepeatRule truncatedBefore(CalendarDay day) {
    if (type == RepeatType.oneTime) {
      throw StateError('cannot truncate a one-time repeat rule');
    }

    return RepeatRule._(
      type: type,
      oneTimeDate: oneTimeDate,
      weekdays: weekdays,
      until: day,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RepeatRule &&
        type == other.type &&
        oneTimeDate == other.oneTimeDate &&
        until == other.until &&
        _setEquals(weekdays, other.weekdays);
  }

  @override
  int get hashCode {
    final orderedWeekdays = Weekday.values.where(weekdays.contains);

    return Object.hash(
      type,
      oneTimeDate,
      until,
      Object.hashAll(orderedWeekdays),
    );
  }

  @override
  String toString() {
    final suffix = until == null ? '' : ', until: $until';
    return switch (type) {
      RepeatType.oneTime => 'RepeatRule.oneTime($oneTimeDate)',
      RepeatType.weekly => 'RepeatRule.weekly($weekdays$suffix)',
    };
  }
}

bool _setEquals<T>(Set<T> left, Set<T> right) {
  return left.length == right.length && left.containsAll(right);
}
