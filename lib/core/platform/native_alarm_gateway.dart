abstract class NativeAlarmGateway {
  Future<NativeAlarmCapability> getCapability();

  Future<NativeAlarmPermissionResult> requestPermission();

  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  );

  Future<CancelResult> cancelOccurrences(List<NativeAlarmCancelRequest> alarms);

  Future<CancelResult> cancelPlan(List<NativeAlarmCancelRequest> alarms);

  Future<TestAlarmScheduleResult> scheduleTestAlarm(
    NativeTestAlarmScheduleRequest request,
  );
}

enum NativeAlarmPermissionStatus {
  unknown,
  notDetermined,
  authorized,
  denied,
  restricted,
  unavailable,
}

enum NativeAlarmPermissionRequestStatus { granted, denied, unavailable }

enum ScheduleResultStatus {
  success,
  permissionMissing,
  osConstraint,
  partialFailure,
  failure,
}

enum ScheduleOccurrenceStatus { success, failure }

enum ScheduleFailureReason {
  permissionMissing,
  osConstraint,
  invalidRequest,
  nativeError,
  unavailable,
  unknown,
}

enum CancelResultStatus { success, partialFailure, failure }

enum CancelAlarmStatus { success, failure }

enum CancelFailureReason {
  missingPlatformAlarmId,
  invalidRequest,
  nativeError,
  unavailable,
  unknown,
}

class NativeAlarmCapability {
  const NativeAlarmCapability({
    required this.permissionStatus,
    required this.canScheduleAlarms,
    required this.canRequestPermission,
    this.maxPendingAlarms,
    this.requiresExactAlarmPermission = false,
    this.requiresNotificationPermission = false,
    this.requiresFullScreenIntentPermission = false,
    this.requiresNotificationChannelSetup = false,
    this.supportsTestAlarm = true,
  });

  final NativeAlarmPermissionStatus permissionStatus;
  final bool canScheduleAlarms;
  final bool canRequestPermission;
  final int? maxPendingAlarms;
  final bool requiresExactAlarmPermission;
  final bool requiresNotificationPermission;
  final bool requiresFullScreenIntentPermission;
  final bool requiresNotificationChannelSetup;
  final bool supportsTestAlarm;
}

class NativeAlarmPermissionResult {
  const NativeAlarmPermissionResult({
    required this.status,
    required this.permissionStatus,
  });

  final NativeAlarmPermissionRequestStatus status;
  final NativeAlarmPermissionStatus permissionStatus;

  bool get isGranted => status == NativeAlarmPermissionRequestStatus.granted;
}

class NativeAlarmScheduleRequest {
  NativeAlarmScheduleRequest({
    required this.occurrenceId,
    required this.wakePlanId,
    required this.scheduledAt,
    required this.targetAt,
    required this.indexInPlan,
    required this.totalInPlan,
    required this.soundId,
    required this.vibrationEnabled,
  }) {
    if (occurrenceId.isEmpty) {
      throw ArgumentError.value(
        occurrenceId,
        'occurrenceId',
        'must not be empty',
      );
    }
    if (wakePlanId.isEmpty) {
      throw ArgumentError.value(wakePlanId, 'wakePlanId', 'must not be empty');
    }
    if (indexInPlan < 0) {
      throw RangeError.range(indexInPlan, 0, null, 'indexInPlan');
    }
    if (totalInPlan <= 0) {
      throw RangeError.range(totalInPlan, 1, null, 'totalInPlan');
    }
    if (indexInPlan >= totalInPlan) {
      throw ArgumentError.value(
        indexInPlan,
        'indexInPlan',
        'must be less than totalInPlan',
      );
    }
    if (soundId.isEmpty) {
      throw ArgumentError.value(soundId, 'soundId', 'must not be empty');
    }
  }

  final String occurrenceId;
  final String wakePlanId;
  final DateTime scheduledAt;
  final DateTime targetAt;
  final int indexInPlan;
  final int totalInPlan;
  final String soundId;
  final bool vibrationEnabled;
}

class NativeAlarmCancelRequest {
  NativeAlarmCancelRequest({
    required this.occurrenceId,
    required this.platformAlarmId,
  }) {
    if (occurrenceId.isEmpty) {
      throw ArgumentError.value(
        occurrenceId,
        'occurrenceId',
        'must not be empty',
      );
    }
    if (platformAlarmId.isEmpty) {
      throw ArgumentError.value(
        platformAlarmId,
        'platformAlarmId',
        'must not be empty',
      );
    }
  }

  final String occurrenceId;
  final String platformAlarmId;
}

class NativeTestAlarmScheduleRequest {
  NativeTestAlarmScheduleRequest({
    required this.fireAfter,
    this.soundId = 'default',
    this.vibrationEnabled = true,
  }) {
    if (fireAfter <= Duration.zero) {
      throw ArgumentError.value(fireAfter, 'fireAfter', 'must be positive');
    }
    if (soundId.isEmpty) {
      throw ArgumentError.value(soundId, 'soundId', 'must not be empty');
    }
  }

  final Duration fireAfter;
  final String soundId;
  final bool vibrationEnabled;
}

class ScheduleResult {
  ScheduleResult({
    required this.status,
    required List<ScheduleOccurrenceResult> occurrences,
  }) : occurrences = List.unmodifiable(occurrences);

  factory ScheduleResult.fromRequestResults({
    required List<NativeAlarmScheduleRequest> requests,
    required List<ScheduleOccurrenceResult> results,
  }) {
    final correlatedResults = _correlateRequestResults(
      requests: requests,
      results: results,
      requestKey: (request) => _scheduleKey(
        occurrenceId: request.occurrenceId,
        wakePlanId: request.wakePlanId,
      ),
      resultKey: (result) => _scheduleKey(
        occurrenceId: result.occurrenceId,
        wakePlanId: result.wakePlanId,
      ),
      missingResult: (request) => ScheduleOccurrenceResult.failure(
        occurrenceId: request.occurrenceId,
        wakePlanId: request.wakePlanId,
        reason: ScheduleFailureReason.nativeError,
        message: 'Missing native schedule result.',
      ),
      resultName: 'schedule result',
    );

    return ScheduleResult.fromOccurrences(correlatedResults);
  }

  factory ScheduleResult.fromOccurrences(
    List<ScheduleOccurrenceResult> occurrences,
  ) {
    final successCount = occurrences.where((result) => result.isSuccess).length;

    if (successCount == occurrences.length) {
      return ScheduleResult(
        status: ScheduleResultStatus.success,
        occurrences: occurrences,
      );
    }

    if (successCount > 0) {
      return ScheduleResult(
        status: ScheduleResultStatus.partialFailure,
        occurrences: occurrences,
      );
    }

    return ScheduleResult(
      status: _statusForFailureReason(
        _selectDominantFailureReason(occurrences),
      ),
      occurrences: occurrences,
    );
  }

  final ScheduleResultStatus status;
  final List<ScheduleOccurrenceResult> occurrences;

  bool get isSuccess => status == ScheduleResultStatus.success;

  bool get isPartialFailure => status == ScheduleResultStatus.partialFailure;

  static ScheduleResultStatus _statusForFailureReason(
    ScheduleFailureReason? reason,
  ) {
    return switch (reason) {
      ScheduleFailureReason.permissionMissing =>
        ScheduleResultStatus.permissionMissing,
      ScheduleFailureReason.osConstraint => ScheduleResultStatus.osConstraint,
      _ => ScheduleResultStatus.failure,
    };
  }
}

class ScheduleOccurrenceResult {
  const ScheduleOccurrenceResult._({
    required this.occurrenceId,
    required this.wakePlanId,
    required this.status,
    this.platformAlarmId,
    this.failureReason,
    this.failureMessage,
  });

  factory ScheduleOccurrenceResult.success({
    required String occurrenceId,
    required String wakePlanId,
    required String platformAlarmId,
  }) {
    _validateOccurrenceIds(occurrenceId: occurrenceId, wakePlanId: wakePlanId);
    if (platformAlarmId.isEmpty) {
      throw ArgumentError.value(
        platformAlarmId,
        'platformAlarmId',
        'must not be empty',
      );
    }

    return ScheduleOccurrenceResult._(
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
      status: ScheduleOccurrenceStatus.success,
      platformAlarmId: platformAlarmId,
    );
  }

  factory ScheduleOccurrenceResult.failure({
    required String occurrenceId,
    required String wakePlanId,
    required ScheduleFailureReason reason,
    String? message,
    String? platformAlarmId,
  }) {
    _validateOccurrenceIds(occurrenceId: occurrenceId, wakePlanId: wakePlanId);
    if (platformAlarmId != null && platformAlarmId.isEmpty) {
      throw ArgumentError.value(
        platformAlarmId,
        'platformAlarmId',
        'must not be empty when provided',
      );
    }

    return ScheduleOccurrenceResult._(
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
      status: ScheduleOccurrenceStatus.failure,
      platformAlarmId: platformAlarmId,
      failureReason: reason,
      failureMessage: message,
    );
  }

  final String occurrenceId;
  final String wakePlanId;
  final ScheduleOccurrenceStatus status;
  final String? platformAlarmId;
  final ScheduleFailureReason? failureReason;
  final String? failureMessage;

  bool get isSuccess => status == ScheduleOccurrenceStatus.success;
}

class CancelResult {
  CancelResult({required this.status, required List<CancelAlarmResult> alarms})
    : alarms = List.unmodifiable(alarms);

  factory CancelResult.fromRequestResults({
    required List<NativeAlarmCancelRequest> requests,
    required List<CancelAlarmResult> results,
  }) {
    final correlatedResults = _correlateRequestResults(
      requests: requests,
      results: results,
      requestKey: (request) => _alarmKey(
        occurrenceId: request.occurrenceId,
        platformAlarmId: request.platformAlarmId,
      ),
      resultKey: (result) => _alarmKey(
        occurrenceId: result.occurrenceId,
        platformAlarmId: result.platformAlarmId,
      ),
      missingResult: (request) => CancelAlarmResult.failure(
        occurrenceId: request.occurrenceId,
        platformAlarmId: request.platformAlarmId,
        reason: CancelFailureReason.nativeError,
        message: 'Missing native cancel result.',
      ),
      resultName: 'cancel result',
    );

    return CancelResult.fromAlarms(correlatedResults);
  }

  factory CancelResult.fromAlarms(List<CancelAlarmResult> alarms) {
    final successCount = alarms.where((result) => result.isSuccess).length;

    final status = switch ((alarms.isEmpty, successCount)) {
      (true, _) => CancelResultStatus.success,
      (false, final count) when count == alarms.length =>
        CancelResultStatus.success,
      (false, 0) => CancelResultStatus.failure,
      _ => CancelResultStatus.partialFailure,
    };

    return CancelResult(status: status, alarms: alarms);
  }

  final CancelResultStatus status;
  final List<CancelAlarmResult> alarms;

  bool get isSuccess => status == CancelResultStatus.success;
}

class CancelAlarmResult {
  const CancelAlarmResult._({
    required this.occurrenceId,
    required this.platformAlarmId,
    required this.status,
    this.failureReason,
    this.failureMessage,
  });

  factory CancelAlarmResult.success({
    required String occurrenceId,
    required String platformAlarmId,
  }) {
    _validateOccurrenceId(occurrenceId);
    _validatePlatformAlarmId(platformAlarmId);
    return CancelAlarmResult._(
      occurrenceId: occurrenceId,
      platformAlarmId: platformAlarmId,
      status: CancelAlarmStatus.success,
    );
  }

  factory CancelAlarmResult.failure({
    required String occurrenceId,
    required String platformAlarmId,
    required CancelFailureReason reason,
    String? message,
  }) {
    _validateOccurrenceId(occurrenceId);
    _validatePlatformAlarmId(platformAlarmId);
    return CancelAlarmResult._(
      occurrenceId: occurrenceId,
      platformAlarmId: platformAlarmId,
      status: CancelAlarmStatus.failure,
      failureReason: reason,
      failureMessage: message,
    );
  }

  final String occurrenceId;
  final String platformAlarmId;
  final CancelAlarmStatus status;
  final CancelFailureReason? failureReason;
  final String? failureMessage;

  bool get isSuccess => status == CancelAlarmStatus.success;
}

class TestAlarmScheduleResult {
  const TestAlarmScheduleResult({
    required this.status,
    this.platformAlarmId,
    this.failureReason,
    this.failureMessage,
  });

  factory TestAlarmScheduleResult.success({required String platformAlarmId}) {
    if (platformAlarmId.isEmpty) {
      throw ArgumentError.value(
        platformAlarmId,
        'platformAlarmId',
        'must not be empty',
      );
    }

    return TestAlarmScheduleResult(
      status: ScheduleResultStatus.success,
      platformAlarmId: platformAlarmId,
    );
  }

  factory TestAlarmScheduleResult.failure({
    required ScheduleFailureReason reason,
    String? message,
  }) {
    return TestAlarmScheduleResult(
      status: ScheduleResult._statusForFailureReason(reason),
      failureReason: reason,
      failureMessage: message,
    );
  }

  final ScheduleResultStatus status;
  final String? platformAlarmId;
  final ScheduleFailureReason? failureReason;
  final String? failureMessage;

  bool get isSuccess => status == ScheduleResultStatus.success;
}

void _validateOccurrenceIds({
  required String occurrenceId,
  required String wakePlanId,
}) {
  _validateOccurrenceId(occurrenceId);
  if (wakePlanId.isEmpty) {
    throw ArgumentError.value(wakePlanId, 'wakePlanId', 'must not be empty');
  }
}

void _validateOccurrenceId(String occurrenceId) {
  if (occurrenceId.isEmpty) {
    throw ArgumentError.value(
      occurrenceId,
      'occurrenceId',
      'must not be empty',
    );
  }
}

void _validatePlatformAlarmId(String platformAlarmId) {
  if (platformAlarmId.isEmpty) {
    throw ArgumentError.value(
      platformAlarmId,
      'platformAlarmId',
      'must not be empty',
    );
  }
}

List<TResult> _correlateRequestResults<TRequest, TResult, TKey>({
  required List<TRequest> requests,
  required List<TResult> results,
  required TKey Function(TRequest request) requestKey,
  required TKey Function(TResult result) resultKey,
  required TResult Function(TRequest request) missingResult,
  required String resultName,
}) {
  final requestKeys = <TKey>{};
  for (final request in requests) {
    final key = requestKey(request);
    if (!requestKeys.add(key)) {
      throw ArgumentError.value(
        key,
        'requests',
        'contains a duplicate request key',
      );
    }
  }

  final resultKeys = <TKey>{};
  final resultsByKey = <TKey, TResult>{};
  for (final result in results) {
    final key = resultKey(result);
    if (!resultKeys.add(key)) {
      throw ArgumentError.value(
        key,
        resultName,
        'contains a duplicate result key',
      );
    }
    if (!requestKeys.contains(key)) {
      throw ArgumentError.value(
        key,
        resultName,
        'does not match any request key',
      );
    }
    resultsByKey[key] = result;
  }

  return requests.map((request) {
    return resultsByKey[requestKey(request)] ?? missingResult(request);
  }).toList();
}

ScheduleFailureReason? _selectDominantFailureReason(
  List<ScheduleOccurrenceResult> occurrences,
) {
  final reasons = occurrences
      .where((result) => !result.isSuccess)
      .map((result) => result.failureReason)
      .whereType<ScheduleFailureReason>()
      .toSet();

  if (reasons.contains(ScheduleFailureReason.permissionMissing)) {
    return ScheduleFailureReason.permissionMissing;
  }
  if (reasons.contains(ScheduleFailureReason.osConstraint)) {
    return ScheduleFailureReason.osConstraint;
  }
  if (reasons.isNotEmpty) {
    return reasons.first;
  }
  return null;
}

String _alarmKey({
  required String occurrenceId,
  required String platformAlarmId,
}) {
  return '$occurrenceId\u0000$platformAlarmId';
}

String _scheduleKey({
  required String occurrenceId,
  required String wakePlanId,
}) {
  return '$occurrenceId\u0000$wakePlanId';
}
