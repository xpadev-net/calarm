import '../../../../core/time/time.dart';
import 'repeat_rule.dart';

enum WakePlanStatus { scheduled, active, finished, skipped, deleted }

const Duration minimumWakePlanInterval = Duration(minutes: 5);
const Duration defaultWakePlanStartOffset = Duration(minutes: 60);
const Duration maximumWakePlanStartOffset = Duration(hours: 3);
const Duration defaultWakePlanInterval = Duration(minutes: 5);
const Duration maximumWakePlanInterval = Duration(minutes: 30);
const String defaultWakePlanSoundId = 'default';
const bool defaultWakePlanVibrationEnabled = true;

class WakePlan {
  factory WakePlan({
    required String id,
    required String title,
    required TimeOfDayMinutes targetTime,
    required Duration startOffset,
    required Duration interval,
    required RepeatRule repeatRule,
    required bool isEnabled,
    required WakePlanStatus status,
    required String soundId,
    required bool vibrationEnabled,
    required DateTime createdAt,
    required DateTime updatedAt,
    CalendarDay? skipNextDate,
  }) {
    _validateId(id, 'id');
    _validateTitle(title);
    _validateSoundId(soundId);
    validateWakePlanTiming(startOffset: startOffset, interval: interval);
    if (status == WakePlanStatus.deleted && isEnabled) {
      throw ArgumentError.value(
        isEnabled,
        'isEnabled',
        'deleted plans must not be enabled',
      );
    }
    if (status == WakePlanStatus.skipped && skipNextDate == null) {
      throw ArgumentError.value(
        status,
        'status',
        'skipped plans must include skipNextDate',
      );
    }
    if (status != WakePlanStatus.skipped && skipNextDate != null) {
      throw ArgumentError.value(
        skipNextDate,
        'skipNextDate',
        'is only valid when status is skipped',
      );
    }

    return WakePlan._(
      id: id,
      title: title,
      targetTime: targetTime,
      startOffset: startOffset,
      interval: interval,
      repeatRule: repeatRule,
      isEnabled: isEnabled,
      status: status,
      skipNextDate: skipNextDate,
      soundId: soundId,
      vibrationEnabled: vibrationEnabled,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  const WakePlan._({
    required this.id,
    required this.title,
    required this.targetTime,
    required this.startOffset,
    required this.interval,
    required this.repeatRule,
    required this.isEnabled,
    required this.status,
    required this.skipNextDate,
    required this.soundId,
    required this.vibrationEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final TimeOfDayMinutes targetTime;
  final Duration startOffset;
  final Duration interval;
  final RepeatRule repeatRule;
  final bool isEnabled;
  final WakePlanStatus status;
  final CalendarDay? skipNextDate;
  final String soundId;
  final bool vibrationEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDeleted => status == WakePlanStatus.deleted;

  bool get hasSkippedNextDate => skipNextDate != null;

  DateTime targetAt(CalendarDay day) {
    return day.at(targetTime);
  }

  DateTime startAt(CalendarDay day) {
    return targetStartAt(targetAt: targetAt(day), startOffset: startOffset);
  }

  bool occursOn(CalendarDay day) {
    return !isDeleted &&
        isEnabled &&
        status != WakePlanStatus.finished &&
        skipNextDate != day &&
        repeatRule.includes(day);
  }

  WakePlan copyWith({
    String? id,
    String? title,
    TimeOfDayMinutes? targetTime,
    Duration? startOffset,
    Duration? interval,
    RepeatRule? repeatRule,
    bool? isEnabled,
    WakePlanStatus? status,
    Object? skipNextDate = _unchanged,
    String? soundId,
    bool? vibrationEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final nextSkipNextDate = skipNextDate == _unchanged
        ? this.skipNextDate
        : skipNextDate as CalendarDay?;

    return WakePlan(
      id: id ?? this.id,
      title: title ?? this.title,
      targetTime: targetTime ?? this.targetTime,
      startOffset: startOffset ?? this.startOffset,
      interval: interval ?? this.interval,
      repeatRule: repeatRule ?? this.repeatRule,
      isEnabled: isEnabled ?? this.isEnabled,
      status: status ?? this.status,
      skipNextDate: nextSkipNextDate,
      soundId: soundId ?? this.soundId,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const Object _unchanged = Object();

void validateWakePlanTiming({
  required Duration startOffset,
  required Duration interval,
}) {
  if (startOffset < Duration.zero) {
    throw ArgumentError.value(
      startOffset,
      'startOffset',
      'must not be negative',
    );
  }
  if (interval <= Duration.zero) {
    throw ArgumentError.value(interval, 'interval', 'must be positive');
  }
  if (interval < minimumWakePlanInterval) {
    throw ArgumentError.value(
      interval,
      'interval',
      'must be at least $minimumWakePlanInterval',
    );
  }
  if (startOffset.inMicroseconds % Duration.microsecondsPerMinute != 0) {
    throw ArgumentError.value(
      startOffset,
      'startOffset',
      'must use whole-minute precision',
    );
  }
  if (interval.inMicroseconds % Duration.microsecondsPerMinute != 0) {
    throw ArgumentError.value(
      interval,
      'interval',
      'must use whole-minute precision',
    );
  }
}

void _validateId(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
}

void _validateTitle(String value) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, 'title', 'must not be blank');
  }
}

void _validateSoundId(String value) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, 'soundId', 'must not be blank');
  }
}
