import '../../../../core/time/time.dart';

enum AlarmOccurrenceStatus {
  scheduled,
  userDisabled,
  userDisablePending,
  unknownPersisted,
  ringing,
  dismissed,
  missed,
  expired,
  cancelled,
  failed,
}

class AlarmOccurrence {
  factory AlarmOccurrence({
    required String id,
    required String wakePlanId,
    required DateMinute scheduledAt,
    required AlarmOccurrenceStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? platformAlarmId,
    DateTime? firedAt,
    DateTime? dismissedAt,
    String? failureReason,
  }) {
    _validateId(id, 'id');
    _validateId(wakePlanId, 'wakePlanId');
    _validatePlatformAlarmId(status: status, value: platformAlarmId);
    _validateFailureReason(status: status, failureReason: failureReason);
    _validateTimestamps(
      status: status,
      firedAt: firedAt,
      dismissedAt: dismissedAt,
    );

    return AlarmOccurrence._(
      id: id,
      wakePlanId: wakePlanId,
      scheduledAt: scheduledAt,
      status: status,
      platformAlarmId: platformAlarmId,
      firedAt: firedAt,
      dismissedAt: dismissedAt,
      failureReason: failureReason,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  const AlarmOccurrence._({
    required this.id,
    required this.wakePlanId,
    required this.scheduledAt,
    required this.status,
    required this.platformAlarmId,
    required this.firedAt,
    required this.dismissedAt,
    required this.failureReason,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String wakePlanId;
  final DateMinute scheduledAt;
  final AlarmOccurrenceStatus status;
  final String? platformAlarmId;
  final DateTime? firedAt;
  final DateTime? dismissedAt;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasNativeReservation => platformAlarmId != null;

  bool get isUserDisabled => status == AlarmOccurrenceStatus.userDisabled;

  bool isUserToggleEligibleAt(DateTime now) {
    if (!scheduledAt.toDateTime().isAfter(now)) {
      return false;
    }
    return isUserDisabled ||
        status == AlarmOccurrenceStatus.scheduled && hasNativeReservation;
  }

  AlarmOccurrence copyWith({
    String? id,
    String? wakePlanId,
    DateMinute? scheduledAt,
    AlarmOccurrenceStatus? status,
    Object? platformAlarmId = _unchanged,
    Object? firedAt = _unchanged,
    Object? dismissedAt = _unchanged,
    Object? failureReason = _unchanged,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AlarmOccurrence(
      id: id ?? this.id,
      wakePlanId: wakePlanId ?? this.wakePlanId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      status: status ?? this.status,
      platformAlarmId: platformAlarmId == _unchanged
          ? this.platformAlarmId
          : platformAlarmId as String?,
      firedAt: firedAt == _unchanged ? this.firedAt : firedAt as DateTime?,
      dismissedAt: dismissedAt == _unchanged
          ? this.dismissedAt
          : dismissedAt as DateTime?,
      failureReason: failureReason == _unchanged
          ? this.failureReason
          : failureReason as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const Object _unchanged = Object();

void _validateId(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
}

void _validatePlatformAlarmId({
  required AlarmOccurrenceStatus status,
  required String? value,
}) {
  if (value != null && value.trim().isEmpty) {
    throw ArgumentError.value(
      value,
      'platformAlarmId',
      'must be null or non-blank',
    );
  }
  if (status == AlarmOccurrenceStatus.userDisabled && value != null) {
    throw ArgumentError.value(
      value,
      'platformAlarmId',
      'must be null when status is userDisabled',
    );
  }
}

void _validateFailureReason({
  required AlarmOccurrenceStatus status,
  required String? failureReason,
}) {
  if (status == AlarmOccurrenceStatus.unknownPersisted) {
    return;
  }
  if (status == AlarmOccurrenceStatus.failed &&
      (failureReason == null || failureReason.trim().isEmpty)) {
    throw ArgumentError.value(
      failureReason,
      'failureReason',
      'is required when status is failed',
    );
  }
  if (status != AlarmOccurrenceStatus.failed && failureReason != null) {
    throw ArgumentError.value(
      failureReason,
      'failureReason',
      'is only valid when status is failed',
    );
  }
}

void _validateTimestamps({
  required AlarmOccurrenceStatus status,
  required DateTime? firedAt,
  required DateTime? dismissedAt,
}) {
  if (status == AlarmOccurrenceStatus.unknownPersisted) {
    return;
  }
  switch (status) {
    case AlarmOccurrenceStatus.scheduled:
    case AlarmOccurrenceStatus.userDisabled:
    case AlarmOccurrenceStatus.userDisablePending:
    case AlarmOccurrenceStatus.expired:
    case AlarmOccurrenceStatus.cancelled:
    case AlarmOccurrenceStatus.failed:
      if (firedAt != null) {
        throw ArgumentError.value(
          firedAt,
          'firedAt',
          'is only valid for ringing, dismissed, or missed occurrences',
        );
      }
      if (dismissedAt != null) {
        throw ArgumentError.value(
          dismissedAt,
          'dismissedAt',
          'is only valid for dismissed occurrences',
        );
      }
    case AlarmOccurrenceStatus.unknownPersisted:
      throw StateError('unknownPersisted is handled before the switch');
    case AlarmOccurrenceStatus.ringing:
      if (firedAt == null) {
        throw ArgumentError.value(
          firedAt,
          'firedAt',
          'is required when status is ringing',
        );
      }
      if (dismissedAt != null) {
        throw ArgumentError.value(
          dismissedAt,
          'dismissedAt',
          'is only valid for dismissed occurrences',
        );
      }
    case AlarmOccurrenceStatus.dismissed:
      if (firedAt == null) {
        throw ArgumentError.value(
          firedAt,
          'firedAt',
          'is required when status is dismissed',
        );
      }
      if (dismissedAt == null) {
        throw ArgumentError.value(
          dismissedAt,
          'dismissedAt',
          'is required when status is dismissed',
        );
      }
    case AlarmOccurrenceStatus.missed:
      if (dismissedAt != null) {
        throw ArgumentError.value(
          dismissedAt,
          'dismissedAt',
          'is only valid for dismissed occurrences',
        );
      }
  }
}
