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

class WeekCalendarWakePlanTapTarget {
  const WeekCalendarWakePlanTapTarget({
    required this.wakePlan,
    required this.targetDay,
  });

  final WakePlan wakePlan;
  final CalendarDay targetDay;

  DateTime get targetAt => wakePlan.targetAt(targetDay);
}

class WeekCalendarWakePlanBlock {
  const WeekCalendarWakePlanBlock({
    required this.wakePlan,
    required this.targetDay,
    required this.day,
    required this.startAt,
    required this.endAt,
    required this.targetAt,
    required this.topMinute,
    required this.durationMinutes,
    required this.dayIndex,
    required this.laneIndex,
    required this.laneCount,
    required this.occurrenceCount,
  });

  final WakePlan wakePlan;
  final CalendarDay targetDay;
  final CalendarDay day;
  final DateTime startAt;
  final DateTime endAt;
  final DateTime targetAt;
  final int topMinute;
  final int durationMinutes;
  final int dayIndex;
  final int laneIndex;
  final int laneCount;
  final int occurrenceCount;

  bool get containsTarget {
    return !targetAt.isBefore(startAt) && !targetAt.isAfter(endAt);
  }

  WeekCalendarWakePlanTapTarget get tapTarget {
    return WeekCalendarWakePlanTapTarget(
      wakePlan: wakePlan,
      targetDay: targetDay,
    );
  }

  WeekCalendarWakePlanBlock copyWith({int? laneIndex, int? laneCount}) {
    return WeekCalendarWakePlanBlock(
      wakePlan: wakePlan,
      targetDay: targetDay,
      day: day,
      startAt: startAt,
      endAt: endAt,
      targetAt: targetAt,
      topMinute: topMinute,
      durationMinutes: durationMinutes,
      dayIndex: dayIndex,
      laneIndex: laneIndex ?? this.laneIndex,
      laneCount: laneCount ?? this.laneCount,
      occurrenceCount: occurrenceCount,
    );
  }
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

List<WeekCalendarWakePlanBlock> weekCalendarWakePlanBlocks({
  required WeekRange week,
  required Iterable<WakePlan> wakePlans,
}) {
  final visibleStart = week.start.startOfDay;
  final visibleEnd = week.endExclusive.startOfDay;
  final blocks = <WeekCalendarWakePlanBlock>[];

  for (final wakePlan in wakePlans) {
    final lookbackDays =
        (wakePlan.startOffset.inMinutes / TimeOfDayMinutes.minutesPerDay)
            .ceil();
    final firstTargetDay = week.start.addDays(-lookbackDays);
    final lastTargetDayExclusive = week.endExclusive.addDays(lookbackDays);

    for (
      var day = firstTargetDay;
      day.compareTo(lastTargetDayExclusive) < 0;
      day = day.addDays(1)
    ) {
      if (!wakePlan.occursOn(day)) {
        continue;
      }

      final targetAt = wakePlan.targetAt(day);
      final startAt = wakePlan.startAt(day);
      if (!startAt.isBefore(visibleEnd) || !targetAt.isAfter(visibleStart)) {
        continue;
      }

      final occurrenceCount = wakePlanOccurrenceCount(wakePlan);

      for (final visibleDay in week.days) {
        final dayStart = visibleDay.startOfDay;
        final dayEnd = visibleDay.addDays(1).startOfDay;
        final segmentStart = _latestDateTime(startAt, dayStart);
        final segmentEnd = _earliestDateTime(targetAt, dayEnd);
        if (!segmentStart.isBefore(segmentEnd)) {
          continue;
        }

        blocks.add(
          WeekCalendarWakePlanBlock(
            wakePlan: wakePlan,
            targetDay: day,
            day: visibleDay,
            startAt: segmentStart,
            endAt: segmentEnd,
            targetAt: targetAt,
            topMinute: _minuteOfDay(segmentStart),
            durationMinutes: segmentEnd.difference(segmentStart).inMinutes,
            dayIndex: visibleDay.differenceInDays(week.start),
            laneIndex: 0,
            laneCount: 1,
            occurrenceCount: occurrenceCount,
          ),
        );
      }
    }
  }

  return _withOverlapLanes(blocks);
}

int wakePlanOccurrenceCount(WakePlan wakePlan) {
  final offsetMinutes = wakePlan.startOffset.inMinutes;
  final intervalMinutes = wakePlan.interval.inMinutes;

  return ((offsetMinutes + intervalMinutes - 1) ~/ intervalMinutes) + 1;
}

List<WeekCalendarWakePlanBlock> _withOverlapLanes(
  List<WeekCalendarWakePlanBlock> blocks,
) {
  final result = <WeekCalendarWakePlanBlock>[];

  for (final dayIndex in blocks.map((block) => block.dayIndex).toSet()) {
    final dayBlocks =
        blocks.where((block) => block.dayIndex == dayIndex).toList()
          ..sort((left, right) {
            final topComparison = left.topMinute.compareTo(right.topMinute);
            if (topComparison != 0) {
              return topComparison;
            }

            return right.durationMinutes.compareTo(left.durationMinutes);
          });
    final assigned = <WeekCalendarWakePlanBlock>[];

    for (final block in dayBlocks) {
      final active = assigned.where((other) => _blocksOverlap(other, block));
      var laneIndex = 0;
      while (active.any((other) => other.laneIndex == laneIndex)) {
        laneIndex += 1;
      }
      assigned.add(block.copyWith(laneIndex: laneIndex));
    }

    final laneCounts = _overlapGroupLaneCounts(assigned);

    result.addAll(
      assigned.map((block) {
        final laneCount = laneCounts[block] ?? 1;
        return block.copyWith(laneCount: laneCount);
      }),
    );
  }

  result.sort((left, right) {
    final dayComparison = left.dayIndex.compareTo(right.dayIndex);
    if (dayComparison != 0) {
      return dayComparison;
    }

    return left.topMinute.compareTo(right.topMinute);
  });

  return result;
}

Map<WeekCalendarWakePlanBlock, int> _overlapGroupLaneCounts(
  List<WeekCalendarWakePlanBlock> blocks,
) {
  final laneCounts = <WeekCalendarWakePlanBlock, int>{};
  final visited = <WeekCalendarWakePlanBlock>{};

  for (final block in blocks) {
    if (visited.contains(block)) {
      continue;
    }

    final group = <WeekCalendarWakePlanBlock>[];
    final pending = <WeekCalendarWakePlanBlock>[block];
    visited.add(block);

    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      group.add(current);

      for (final candidate in blocks) {
        if (visited.contains(candidate) ||
            !_blocksOverlap(current, candidate)) {
          continue;
        }

        visited.add(candidate);
        pending.add(candidate);
      }
    }

    final groupLaneCount =
        group.map((block) => block.laneIndex).reduce((left, right) {
          return left > right ? left : right;
        }) +
        1;
    for (final groupBlock in group) {
      laneCounts[groupBlock] = groupLaneCount;
    }
  }

  return laneCounts;
}

bool _blocksOverlap(
  WeekCalendarWakePlanBlock left,
  WeekCalendarWakePlanBlock right,
) {
  return left.startAt.isBefore(right.endAt) &&
      right.startAt.isBefore(left.endAt);
}

DateTime _latestDateTime(DateTime left, DateTime right) {
  return left.isAfter(right) ? left : right;
}

DateTime _earliestDateTime(DateTime left, DateTime right) {
  return left.isBefore(right) ? left : right;
}

int _minuteOfDay(DateTime dateTime) {
  return dateTime.hour * TimeOfDayMinutes.minutesPerHour + dateTime.minute;
}
