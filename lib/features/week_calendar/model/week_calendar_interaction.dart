import '../../../core/time/time.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';

const int weekCalendarStartMinute = 0;
const int weekCalendarEndMinute = TimeOfDayMinutes.minutesPerDay;
const int weekCalendarDefaultScrollMinute = 5 * TimeOfDayMinutes.minutesPerHour;
const Duration weekCalendarDraftSnapInterval = Duration(minutes: 5);
const Duration weekCalendarDraftMinimumDuration = Duration(minutes: 5);
const Duration weekCalendarDraftMaximumDuration = Duration(hours: 3);

enum WeekCalendarDraftRangeError { notOrdered, tooShort, tooLong }

class WeekCalendarDraftRangeEdit {
  const WeekCalendarDraftRangeEdit._({this.draft, this.error});

  const WeekCalendarDraftRangeEdit.valid(WeekCalendarDraft draft)
    : this._(draft: draft);

  const WeekCalendarDraftRangeEdit.invalid(WeekCalendarDraftRangeError error)
    : this._(error: error);

  final WeekCalendarDraft? draft;
  final WeekCalendarDraftRangeError? error;

  bool get isValid => draft != null;
}

class WeekCalendarDraft {
  WeekCalendarDraft({
    required this.id,
    required this.startAt,
    required this.endAt,
    required this.createdAt,
  }) {
    if (!startAt.isBefore(endAt)) {
      throw ArgumentError('startAt must be before endAt');
    }
    final duration = endAt.difference(startAt);
    if (duration < weekCalendarDraftMinimumDuration ||
        duration > weekCalendarDraftMaximumDuration) {
      throw ArgumentError.value(duration, 'duration', 'must be 5m through 3h');
    }
  }

  final String id;
  final DateTime startAt;
  final DateTime endAt;
  final DateTime createdAt;

  Duration get duration => endAt.difference(startAt);

  WeekCalendarDraft moveBy({required int days, required int minutes}) {
    final interval = weekCalendarDraftSnapInterval.inMinutes;
    final snappedMinutes = (minutes / interval).round() * interval;
    final minuteDelta = Duration(minutes: snappedMinutes);
    final nextStartAt = _addCalendarDays(startAt, days).add(minuteDelta);
    return copyWith(startAt: nextStartAt, endAt: nextStartAt.add(duration));
  }

  WeekCalendarDraft resizeStartBy(Duration delta) {
    final nextStart = _clampDraftStart(startAt.add(delta), endAt);
    return copyWith(startAt: nextStart);
  }

  WeekCalendarDraft resizeEndBy(Duration delta) {
    final nextEnd = _clampDraftEnd(startAt, endAt.add(delta));
    return copyWith(endAt: nextEnd);
  }

  WeekCalendarDraft copyWith({DateTime? startAt, DateTime? endAt}) {
    return WeekCalendarDraft(
      id: id,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      createdAt: createdAt,
    );
  }
}

WeekCalendarDraft weekCalendarDraftFromTap({
  required String id,
  required WeekCalendarTapTarget target,
  required Duration defaultDuration,
  required DateTime createdAt,
}) {
  final boundedDuration = defaultDuration < weekCalendarDraftMinimumDuration
      ? weekCalendarDraftMinimumDuration
      : defaultDuration > weekCalendarDraftMaximumDuration
      ? weekCalendarDraftMaximumDuration
      : defaultDuration;
  final intervalMinutes = weekCalendarDraftSnapInterval.inMinutes;
  final snappedDuration = Duration(
    minutes:
        (boundedDuration.inMinutes / intervalMinutes).round() * intervalMinutes,
  );
  final startAt = snapWeekCalendarDraftDateTime(target.dateTime);
  return WeekCalendarDraft(
    id: id,
    startAt: startAt,
    endAt: startAt.add(snappedDuration),
    createdAt: createdAt,
  );
}

DateTime snapWeekCalendarDraftDateTime(DateTime value) {
  final interval = weekCalendarDraftSnapInterval.inMinutes;
  final dayStart = value.isUtc
      ? DateTime.utc(value.year, value.month, value.day)
      : DateTime(value.year, value.month, value.day);
  final minute = value.difference(dayStart).inMinutes;
  final snappedMinute = (minute / interval).round() * interval;
  return dayStart.add(Duration(minutes: snappedMinute));
}

WeekCalendarDraftRangeEdit editWeekCalendarDraftRange({
  required WeekCalendarDraft draft,
  required DateTime startAt,
  required DateTime endAt,
}) {
  final snappedStart = snapWeekCalendarDraftDateTime(startAt);
  final snappedEnd = snapWeekCalendarDraftDateTime(endAt);
  if (snappedStart.isAfter(snappedEnd)) {
    return const WeekCalendarDraftRangeEdit.invalid(
      WeekCalendarDraftRangeError.notOrdered,
    );
  }

  final duration = snappedEnd.difference(snappedStart);
  if (duration < weekCalendarDraftMinimumDuration) {
    return const WeekCalendarDraftRangeEdit.invalid(
      WeekCalendarDraftRangeError.tooShort,
    );
  }
  if (duration > weekCalendarDraftMaximumDuration) {
    return const WeekCalendarDraftRangeEdit.invalid(
      WeekCalendarDraftRangeError.tooLong,
    );
  }

  return WeekCalendarDraftRangeEdit.valid(
    draft.copyWith(startAt: snappedStart, endAt: snappedEnd),
  );
}

WeekCalendarDraft clampWeekCalendarDraftToRange({
  required WeekCalendarDraft draft,
  required WeekRange week,
}) {
  final rangeStart = week.start.startOfDay;
  final rangeEnd = week.endExclusive.startOfDay;
  if (draft.startAt.isBefore(rangeStart)) {
    return draft.copyWith(
      startAt: rangeStart,
      endAt: rangeStart.add(draft.duration),
    );
  }
  if (draft.endAt.isAfter(rangeEnd)) {
    return draft.copyWith(
      startAt: rangeEnd.subtract(draft.duration),
      endAt: rangeEnd,
    );
  }
  return draft;
}

DateTime _addCalendarDays(DateTime value, int days) {
  final nextDay = CalendarDay.fromDateTime(value).addDays(days);
  if (value.isUtc) {
    return DateTime.utc(
      nextDay.year,
      nextDay.month,
      nextDay.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }
  return DateTime(
    nextDay.year,
    nextDay.month,
    nextDay.day,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}

DateTime _clampDraftStart(DateTime candidate, DateTime endAt) {
  final snapped = snapWeekCalendarDraftDateTime(candidate);
  final earliest = endAt.subtract(weekCalendarDraftMaximumDuration);
  final latest = endAt.subtract(weekCalendarDraftMinimumDuration);
  if (snapped.isBefore(earliest)) {
    return earliest;
  }
  if (snapped.isAfter(latest)) {
    return latest;
  }
  return snapped;
}

DateTime _clampDraftEnd(DateTime startAt, DateTime candidate) {
  final snapped = snapWeekCalendarDraftDateTime(candidate);
  final earliest = startAt.add(weekCalendarDraftMinimumDuration);
  final latest = startAt.add(weekCalendarDraftMaximumDuration);
  if (snapped.isBefore(earliest)) {
    return earliest;
  }
  if (snapped.isAfter(latest)) {
    return latest;
  }
  return snapped;
}

class WeekCalendarPage {
  WeekCalendarPage({required this.week});

  factory WeekCalendarPage.fromAnchor(
    DateTime anchor, {
    int visibleDays = DateTime.daysPerWeek,
  }) {
    return WeekCalendarPage(
      week: currentCalendarRange(anchor, visibleDays: visibleDays),
    );
  }

  final WeekRange week;

  List<CalendarDay> get days => week.days;

  bool contains(CalendarDay day) => week.contains(day);

  WeekCalendarPage addPages(int pages) {
    return WeekCalendarPage(
      week: WeekRange(
        start: week.start.addDays(pages * week.visibleDays),
        visibleDays: week.visibleDays,
      ),
    );
  }
}

WeekRange currentCalendarRange(DateTime anchor, {required int visibleDays}) {
  if (visibleDays != 3 && visibleDays != DateTime.daysPerWeek) {
    throw ArgumentError.value(
      visibleDays,
      'visibleDays',
      'must be 3 or ${DateTime.daysPerWeek}',
    );
  }

  final anchorDay = CalendarDay.fromDateTime(anchor);
  return WeekRange(
    start: visibleDays == DateTime.daysPerWeek
        ? weekStartSunday(anchorDay)
        : anchorDay,
    visibleDays: visibleDays,
  );
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
