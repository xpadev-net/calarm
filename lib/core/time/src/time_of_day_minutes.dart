class TimeOfDayMinutes implements Comparable<TimeOfDayMinutes> {
  const TimeOfDayMinutes._(this.minutesSinceMidnight);

  factory TimeOfDayMinutes.fromHourMinute({
    required int hour,
    required int minute,
  }) {
    if (hour < 0 || hour > 23) {
      throw RangeError.range(hour, 0, 23, 'hour');
    }
    if (minute < 0 || minute > 59) {
      throw RangeError.range(minute, 0, 59, 'minute');
    }

    return TimeOfDayMinutes._(hour * minutesPerHour + minute);
  }

  factory TimeOfDayMinutes.fromMinutesSinceMidnight(int minutes) {
    if (minutes < 0 || minutes >= minutesPerDay) {
      throw RangeError.range(minutes, 0, minutesPerDay - 1, 'minutes');
    }

    return TimeOfDayMinutes._(minutes);
  }

  factory TimeOfDayMinutes.fromDateTime(DateTime dateTime) {
    return TimeOfDayMinutes.fromHourMinute(
      hour: dateTime.hour,
      minute: dateTime.minute,
    );
  }

  static const int minutesPerHour = 60;
  static const int hoursPerDay = 24;
  static const int minutesPerDay = hoursPerDay * minutesPerHour;

  final int minutesSinceMidnight;

  int get hour => minutesSinceMidnight ~/ minutesPerHour;

  int get minute => minutesSinceMidnight % minutesPerHour;

  @override
  int compareTo(TimeOfDayMinutes other) {
    return minutesSinceMidnight.compareTo(other.minutesSinceMidnight);
  }

  @override
  bool operator ==(Object other) {
    return other is TimeOfDayMinutes &&
        minutesSinceMidnight == other.minutesSinceMidnight;
  }

  @override
  int get hashCode => minutesSinceMidnight.hashCode;

  @override
  String toString() {
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }
}
