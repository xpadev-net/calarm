import '../../../../core/time/time.dart';
import 'wake_plan.dart';

enum WakePlanOccurrenceExceptionType { skipped, moved }

class WakePlanOccurrenceException {
  factory WakePlanOccurrenceException({
    required String wakePlanId,
    required CalendarDay originalDay,
    required WakePlanOccurrenceExceptionType type,
    required DateTime createdAt,
    required DateTime updatedAt,
    CalendarDay? movedToDay,
    TimeOfDayMinutes? movedToTargetTime,
  }) {
    _validateId(wakePlanId, 'wakePlanId');
    switch (type) {
      case WakePlanOccurrenceExceptionType.skipped:
        if (movedToDay != null || movedToTargetTime != null) {
          throw ArgumentError.value(
            movedToDay,
            'movedToDay',
            'must be null when type is skipped',
          );
        }
      case WakePlanOccurrenceExceptionType.moved:
        if (movedToDay == null) {
          throw ArgumentError.value(
            movedToDay,
            'movedToDay',
            'is required when type is moved',
          );
        }
    }

    return WakePlanOccurrenceException._(
      id: idFor(wakePlanId: wakePlanId, originalDay: originalDay),
      wakePlanId: wakePlanId,
      originalDay: originalDay,
      type: type,
      movedToDay: movedToDay,
      movedToTargetTime: movedToTargetTime,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  const WakePlanOccurrenceException._({
    required this.id,
    required this.wakePlanId,
    required this.originalDay,
    required this.type,
    required this.movedToDay,
    required this.movedToTargetTime,
    required this.createdAt,
    required this.updatedAt,
  });

  static String idFor({
    required String wakePlanId,
    required CalendarDay originalDay,
  }) {
    return '$wakePlanId:${originalDay.daysSinceUnixEpoch}';
  }

  final String id;
  final String wakePlanId;
  final CalendarDay originalDay;
  final WakePlanOccurrenceExceptionType type;
  final CalendarDay? movedToDay;
  final TimeOfDayMinutes? movedToTargetTime;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSkipped => type == WakePlanOccurrenceExceptionType.skipped;

  bool get isMoved => type == WakePlanOccurrenceExceptionType.moved;

  WakePlanOccurrenceException copyWith({
    String? wakePlanId,
    CalendarDay? originalDay,
    WakePlanOccurrenceExceptionType? type,
    Object? movedToDay = _unchanged,
    Object? movedToTargetTime = _unchanged,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WakePlanOccurrenceException(
      wakePlanId: wakePlanId ?? this.wakePlanId,
      originalDay: originalDay ?? this.originalDay,
      type: type ?? this.type,
      movedToDay: movedToDay == _unchanged
          ? this.movedToDay
          : movedToDay as CalendarDay?,
      movedToTargetTime: movedToTargetTime == _unchanged
          ? this.movedToTargetTime
          : movedToTargetTime as TimeOfDayMinutes?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Combines [wakePlan]'s natural repeat/holiday rules with per-occurrence
/// exceptions to decide whether [day] should render/schedule as a natural
/// occurrence. A day with any exception (skipped or moved) never shows up in
/// its natural slot — a moved occurrence is re-injected at its new day/time
/// by whatever built [exceptionsByOriginalDay] (see [OccurrencePlanner] and
/// the calendar block builders).
bool occursOnConsideringExceptions({
  required WakePlan wakePlan,
  required CalendarDay day,
  required Set<CalendarDay> holidays,
  required Map<CalendarDay, WakePlanOccurrenceException>
  exceptionsByOriginalDay,
}) {
  return wakePlan.occursOnConsideringHolidays(day, holidays) &&
      exceptionsByOriginalDay[day] == null;
}

void _validateId(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
}

const Object _unchanged = Object();
