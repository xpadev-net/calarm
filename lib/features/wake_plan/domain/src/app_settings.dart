import '../../../../core/time/time.dart';
import 'repeat_rule.dart';
import 'wake_plan.dart';

class AppSettings {
  factory AppSettings.initial() {
    return AppSettings(
      defaultStartOffset: defaultWakePlanStartOffset,
      defaultInterval: defaultWakePlanInterval,
      defaultSoundId: defaultWakePlanSoundId,
      defaultVibrationEnabled: defaultWakePlanVibrationEnabled,
      defaultRepeatType: RepeatType.oneTime,
    );
  }

  factory AppSettings({
    required Duration defaultStartOffset,
    required Duration defaultInterval,
    required String defaultSoundId,
    required bool defaultVibrationEnabled,
    required RepeatType defaultRepeatType,
    TimeOfDayMinutes? defaultTargetTime,
  }) {
    validateWakePlanTiming(
      startOffset: defaultStartOffset,
      interval: defaultInterval,
    );
    if (defaultStartOffset > maximumWakePlanStartOffset) {
      throw ArgumentError.value(
        defaultStartOffset,
        'defaultStartOffset',
        'must not be more than $maximumWakePlanStartOffset',
      );
    }
    if (defaultInterval > maximumWakePlanInterval) {
      throw ArgumentError.value(
        defaultInterval,
        'defaultInterval',
        'must not be more than $maximumWakePlanInterval',
      );
    }
    _validateDefaultSoundId(defaultSoundId);

    return AppSettings._(
      defaultStartOffset: defaultStartOffset,
      defaultInterval: defaultInterval,
      defaultSoundId: defaultSoundId,
      defaultVibrationEnabled: defaultVibrationEnabled,
      defaultRepeatType: defaultRepeatType,
      defaultTargetTime: defaultTargetTime,
    );
  }

  const AppSettings._({
    required this.defaultStartOffset,
    required this.defaultInterval,
    required this.defaultSoundId,
    required this.defaultVibrationEnabled,
    required this.defaultRepeatType,
    required this.defaultTargetTime,
  });

  final Duration defaultStartOffset;
  final Duration defaultInterval;
  final String defaultSoundId;
  final bool defaultVibrationEnabled;
  final RepeatType defaultRepeatType;
  final TimeOfDayMinutes? defaultTargetTime;

  RepeatRule repeatRuleForDate(CalendarDay date) {
    return switch (defaultRepeatType) {
      RepeatType.oneTime => RepeatRule.oneTime(date),
      RepeatType.weekly => RepeatRule.weekly({
        Weekday.fromDateTimeValue(date.weekday),
      }),
    };
  }

  AppSettings copyWith({
    Duration? defaultStartOffset,
    Duration? defaultInterval,
    String? defaultSoundId,
    bool? defaultVibrationEnabled,
    RepeatType? defaultRepeatType,
    Object? defaultTargetTime = _unchanged,
  }) {
    final nextDefaultTargetTime = defaultTargetTime == _unchanged
        ? this.defaultTargetTime
        : defaultTargetTime as TimeOfDayMinutes?;

    return AppSettings(
      defaultStartOffset: defaultStartOffset ?? this.defaultStartOffset,
      defaultInterval: defaultInterval ?? this.defaultInterval,
      defaultSoundId: defaultSoundId ?? this.defaultSoundId,
      defaultVibrationEnabled:
          defaultVibrationEnabled ?? this.defaultVibrationEnabled,
      defaultRepeatType: defaultRepeatType ?? this.defaultRepeatType,
      defaultTargetTime: nextDefaultTargetTime,
    );
  }
}

const Object _unchanged = Object();

AppSettings sanitizeAppSettings({
  Duration? defaultStartOffset,
  Duration? defaultInterval,
  String? defaultSoundId,
  bool? defaultVibrationEnabled,
  RepeatType? defaultRepeatType,
  TimeOfDayMinutes? defaultTargetTime,
}) {
  final fallback = AppSettings.initial();
  return AppSettings(
    defaultStartOffset: _clampWholeMinuteDuration(
      defaultStartOffset,
      min: Duration.zero,
      max: maximumWakePlanStartOffset,
      fallback: fallback.defaultStartOffset,
    ),
    defaultInterval: _clampWholeMinuteDuration(
      defaultInterval,
      min: minimumWakePlanInterval,
      max: maximumWakePlanInterval,
      fallback: fallback.defaultInterval,
    ),
    defaultSoundId: _sanitizeSoundId(defaultSoundId, fallback.defaultSoundId),
    defaultVibrationEnabled:
        defaultVibrationEnabled ?? fallback.defaultVibrationEnabled,
    defaultRepeatType: defaultRepeatType ?? fallback.defaultRepeatType,
    defaultTargetTime: defaultTargetTime ?? fallback.defaultTargetTime,
  );
}

void _validateDefaultSoundId(String value) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, 'defaultSoundId', 'must not be blank');
  }
  if (!_isSupportedSoundId(value.trim())) {
    throw ArgumentError.value(
      value,
      'defaultSoundId',
      'must be $defaultWakePlanSoundId',
    );
  }
}

Duration _clampWholeMinuteDuration(
  Duration? value, {
  required Duration min,
  required Duration max,
  required Duration fallback,
}) {
  if (value == null || value.inMicroseconds < 0) {
    return fallback;
  }

  final minutes = value.inMinutes;
  final wholeMinutes = Duration(minutes: minutes);
  if (wholeMinutes < min) {
    return min;
  }
  if (wholeMinutes > max) {
    return max;
  }

  return wholeMinutes;
}

String _sanitizeSoundId(String? value, String fallback) {
  if (value == null || value.trim().isEmpty) {
    return fallback;
  }

  final trimmed = value.trim();
  if (!_isSupportedSoundId(trimmed)) {
    return fallback;
  }

  return trimmed;
}

bool _isSupportedSoundId(String value) {
  return value == defaultWakePlanSoundId;
}
