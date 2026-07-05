import '../../../../core/time/time.dart';
import 'repeat_rule.dart';
import 'wake_plan.dart';

class AppSettings {
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
    _validateSoundId(defaultSoundId);

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

void _validateSoundId(String value) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, 'soundId', 'must not be blank');
  }
}
