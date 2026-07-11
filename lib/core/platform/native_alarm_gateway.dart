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

  /// Reads the platform's current reservations without mutating them.
  ///
  /// Implementations deployed before the inventory contract may report an
  /// unavailable result while the Dart side rolls forward.
  Future<NativeAlarmInventoryResult> getInventory() async {
    return NativeAlarmInventoryResult.failure(
      reason: NativeAlarmInventoryFailureReason.unavailable,
      message: 'Native inventory is not implemented by this gateway.',
    );
  }
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
    this.supportsInventory = false,
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
  final bool supportsInventory;
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
    String? reservationId,
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
    _validateReservationId(reservationId ?? occurrenceId);
    this.reservationId = reservationId ?? occurrenceId;
  }

  final String occurrenceId;

  /// Stable logical identity for the native reservation.
  ///
  /// It defaults to [occurrenceId] for callers compiled against the original
  /// contract. New callers should persist and reuse this value across retry
  /// and process restarts.
  late final String reservationId;
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
    String? reservationId,
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
    _validateReservationId(reservationId ?? occurrenceId);
    this.reservationId = reservationId ?? occurrenceId;
  }

  final String occurrenceId;
  late final String reservationId;
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
    _validateUniqueReservationIds(
      requests.map((request) => request.reservationId),
      'requests',
    );
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

    for (var index = 0; index < requests.length; index++) {
      final request = requests[index];
      final result = correlatedResults[index];
      if (result.reservationId != request.reservationId &&
          result.reservationId != request.occurrenceId) {
        throw ArgumentError.value(
          result.reservationId,
          'schedule result',
          'does not match the requested reservationId',
        );
      }
      if (result.reservationId == request.occurrenceId &&
          request.reservationId != request.occurrenceId) {
        correlatedResults[index] = result.copyWith(
          reservationId: request.reservationId,
        );
      }
    }
    _validateUniqueReservationIds(
      correlatedResults.map((result) => result.reservationId),
      'schedule result',
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
    required this.reservationId,
    required this.status,
    this.platformAlarmId,
    this.failureReason,
    this.failureMessage,
  });

  factory ScheduleOccurrenceResult.success({
    required String occurrenceId,
    required String wakePlanId,
    required String platformAlarmId,
    String? reservationId,
  }) {
    _validateOccurrenceIds(occurrenceId: occurrenceId, wakePlanId: wakePlanId);
    final resolvedReservationId = reservationId ?? occurrenceId;
    _validateReservationId(resolvedReservationId);
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
      reservationId: resolvedReservationId,
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
    String? reservationId,
  }) {
    _validateOccurrenceIds(occurrenceId: occurrenceId, wakePlanId: wakePlanId);
    final resolvedReservationId = reservationId ?? occurrenceId;
    _validateReservationId(resolvedReservationId);
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
      reservationId: resolvedReservationId,
      status: ScheduleOccurrenceStatus.failure,
      platformAlarmId: platformAlarmId,
      failureReason: reason,
      failureMessage: message,
    );
  }

  final String occurrenceId;
  final String wakePlanId;
  final String reservationId;
  final ScheduleOccurrenceStatus status;
  final String? platformAlarmId;
  final ScheduleFailureReason? failureReason;
  final String? failureMessage;

  bool get isSuccess => status == ScheduleOccurrenceStatus.success;

  ScheduleOccurrenceResult copyWith({String? reservationId}) {
    final resolvedReservationId = reservationId ?? this.reservationId;
    _validateReservationId(resolvedReservationId);
    return ScheduleOccurrenceResult._(
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
      reservationId: resolvedReservationId,
      status: status,
      platformAlarmId: platformAlarmId,
      failureReason: failureReason,
      failureMessage: failureMessage,
    );
  }
}

class CancelResult {
  CancelResult({required this.status, required List<CancelAlarmResult> alarms})
    : alarms = List.unmodifiable(alarms);

  factory CancelResult.fromRequestResults({
    required List<NativeAlarmCancelRequest> requests,
    required List<CancelAlarmResult> results,
  }) {
    _validateUniqueReservationIds(
      requests.map((request) => request.reservationId),
      'requests',
    );
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

    for (var index = 0; index < requests.length; index++) {
      final request = requests[index];
      final result = correlatedResults[index];
      if (result.reservationId != request.reservationId &&
          result.reservationId != request.occurrenceId) {
        throw ArgumentError.value(
          result.reservationId,
          'cancel result',
          'does not match the requested reservationId',
        );
      }
      if (result.reservationId == request.occurrenceId &&
          request.reservationId != request.occurrenceId) {
        correlatedResults[index] = result.copyWith(
          reservationId: request.reservationId,
        );
      }
    }
    _validateUniqueReservationIds(
      correlatedResults.map((result) => result.reservationId),
      'cancel result',
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
    required this.reservationId,
    required this.status,
    this.failureReason,
    this.failureMessage,
  });

  factory CancelAlarmResult.success({
    required String occurrenceId,
    required String platformAlarmId,
    String? reservationId,
  }) {
    _validateOccurrenceId(occurrenceId);
    final resolvedReservationId = reservationId ?? occurrenceId;
    _validateReservationId(resolvedReservationId);
    _validatePlatformAlarmId(platformAlarmId);
    return CancelAlarmResult._(
      occurrenceId: occurrenceId,
      platformAlarmId: platformAlarmId,
      reservationId: resolvedReservationId,
      status: CancelAlarmStatus.success,
    );
  }

  factory CancelAlarmResult.failure({
    required String occurrenceId,
    required String platformAlarmId,
    required CancelFailureReason reason,
    String? message,
    String? reservationId,
  }) {
    _validateOccurrenceId(occurrenceId);
    final resolvedReservationId = reservationId ?? occurrenceId;
    _validateReservationId(resolvedReservationId);
    _validatePlatformAlarmId(platformAlarmId);
    return CancelAlarmResult._(
      occurrenceId: occurrenceId,
      platformAlarmId: platformAlarmId,
      reservationId: resolvedReservationId,
      status: CancelAlarmStatus.failure,
      failureReason: reason,
      failureMessage: message,
    );
  }

  final String occurrenceId;
  final String reservationId;
  final String platformAlarmId;
  final CancelAlarmStatus status;
  final CancelFailureReason? failureReason;
  final String? failureMessage;

  bool get isSuccess => status == CancelAlarmStatus.success;

  CancelAlarmResult copyWith({String? reservationId}) {
    final resolvedReservationId = reservationId ?? this.reservationId;
    _validateReservationId(resolvedReservationId);
    return CancelAlarmResult._(
      occurrenceId: occurrenceId,
      platformAlarmId: platformAlarmId,
      reservationId: resolvedReservationId,
      status: status,
      failureReason: failureReason,
      failureMessage: failureMessage,
    );
  }
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

enum NativeAlarmInventoryResultStatus { success, unavailable, failure }

enum NativeAlarmInventoryFailureReason {
  unavailable,
  nativeError,
  corrupt,
  unknown,
}

enum NativeAlarmReservationStatus { scheduled, ringing, stopped, unknown }

enum NativeAlarmInventoryIssueType {
  unknown,
  missing,
  duplicate,
  corrupt,
  extra,
}

class NativeAlarmInventoryRow {
  factory NativeAlarmInventoryRow({
    required String reservationId,
    required String occurrenceId,
    required String wakePlanId,
    required String platformAlarmId,
    required NativeAlarmReservationStatus status,
  }) {
    return NativeAlarmInventoryRow.create(
      reservationId: reservationId,
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
      platformAlarmId: platformAlarmId,
      status: status,
    );
  }

  const NativeAlarmInventoryRow._({
    required this.reservationId,
    required this.occurrenceId,
    required this.wakePlanId,
    required this.platformAlarmId,
    required this.status,
  });

  factory NativeAlarmInventoryRow.create({
    required String reservationId,
    required String occurrenceId,
    required String wakePlanId,
    required String platformAlarmId,
    required NativeAlarmReservationStatus status,
  }) {
    _validateReservationId(reservationId);
    _validateOccurrenceId(occurrenceId);
    if (wakePlanId.isEmpty) {
      throw ArgumentError.value(wakePlanId, 'wakePlanId', 'must not be empty');
    }
    _validatePlatformAlarmId(platformAlarmId);
    return NativeAlarmInventoryRow._(
      reservationId: reservationId,
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
      platformAlarmId: platformAlarmId,
      status: status,
    );
  }

  final String reservationId;
  final String occurrenceId;
  final String wakePlanId;
  final String platformAlarmId;
  final NativeAlarmReservationStatus status;
}

class NativeAlarmInventoryExpectedReservation {
  factory NativeAlarmInventoryExpectedReservation({
    required String reservationId,
    required String occurrenceId,
    required String wakePlanId,
  }) {
    return NativeAlarmInventoryExpectedReservation.create(
      reservationId: reservationId,
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
    );
  }

  const NativeAlarmInventoryExpectedReservation._({
    required this.reservationId,
    required this.occurrenceId,
    required this.wakePlanId,
  });

  factory NativeAlarmInventoryExpectedReservation.create({
    required String reservationId,
    required String occurrenceId,
    required String wakePlanId,
  }) {
    _validateReservationId(reservationId);
    _validateOccurrenceId(occurrenceId);
    if (wakePlanId.isEmpty) {
      throw ArgumentError.value(wakePlanId, 'wakePlanId', 'must not be empty');
    }
    return NativeAlarmInventoryExpectedReservation._(
      reservationId: reservationId,
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
    );
  }

  final String reservationId;
  final String occurrenceId;
  final String wakePlanId;
}

class NativeAlarmInventoryIssue {
  const NativeAlarmInventoryIssue({
    required this.type,
    required this.message,
    this.reservationId,
  });

  final NativeAlarmInventoryIssueType type;
  final String message;
  final String? reservationId;
}

class NativeAlarmInventoryReconciliation {
  NativeAlarmInventoryReconciliation({
    required List<NativeAlarmInventoryRow> rows,
    required List<NativeAlarmInventoryIssue> issues,
    required this.sourceWasSuccessful,
  }) : rows = List.unmodifiable(rows),
       issues = List.unmodifiable(issues);

  final List<NativeAlarmInventoryRow> rows;
  final List<NativeAlarmInventoryIssue> issues;
  final bool sourceWasSuccessful;

  bool get isAuthoritative => sourceWasSuccessful && issues.isEmpty;
}

class NativeAlarmInventoryResult {
  NativeAlarmInventoryResult({
    required this.status,
    required List<NativeAlarmInventoryRow> rows,
    required List<NativeAlarmInventoryIssue> issues,
    this.failureReason,
    this.failureMessage,
  }) : rows = List.unmodifiable(rows),
       issues = List.unmodifiable(issues);

  factory NativeAlarmInventoryResult.success({
    required List<NativeAlarmInventoryRow> rows,
  }) {
    final duplicateIds = <String>{};
    final seenIds = <String>{};
    for (final row in rows) {
      if (!seenIds.add(row.reservationId)) {
        duplicateIds.add(row.reservationId);
      }
    }
    final unknownStatusRows = rows
        .where((row) => row.status == NativeAlarmReservationStatus.unknown)
        .map((row) => row.reservationId)
        .toSet();
    final issues = <NativeAlarmInventoryIssue>[
      for (final reservationId in duplicateIds)
        NativeAlarmInventoryIssue(
          type: NativeAlarmInventoryIssueType.duplicate,
          reservationId: reservationId,
          message: 'Duplicate native inventory row.',
        ),
      for (final reservationId in unknownStatusRows)
        NativeAlarmInventoryIssue(
          type: NativeAlarmInventoryIssueType.unknown,
          reservationId: reservationId,
          message: 'Native inventory row has an unknown status.',
        ),
    ];
    return NativeAlarmInventoryResult(
      status: issues.isEmpty
          ? NativeAlarmInventoryResultStatus.success
          : NativeAlarmInventoryResultStatus.failure,
      rows: rows,
      issues: issues,
      failureReason: duplicateIds.isNotEmpty
          ? NativeAlarmInventoryFailureReason.corrupt
          : unknownStatusRows.isNotEmpty
          ? NativeAlarmInventoryFailureReason.unknown
          : null,
      failureMessage: issues.isEmpty ? null : issues.first.message,
    );
  }

  factory NativeAlarmInventoryResult.failure({
    required NativeAlarmInventoryFailureReason reason,
    String? message,
  }) {
    final issueType = switch (reason) {
      NativeAlarmInventoryFailureReason.corrupt =>
        NativeAlarmInventoryIssueType.corrupt,
      NativeAlarmInventoryFailureReason.unknown =>
        NativeAlarmInventoryIssueType.unknown,
      _ => null,
    };
    return NativeAlarmInventoryResult(
      status: reason == NativeAlarmInventoryFailureReason.unavailable
          ? NativeAlarmInventoryResultStatus.unavailable
          : NativeAlarmInventoryResultStatus.failure,
      rows: const [],
      issues: [
        if (issueType != null)
          NativeAlarmInventoryIssue(
            type: issueType,
            message: message ?? 'Native inventory read failed.',
          ),
      ],
      failureReason: reason,
      failureMessage: message,
    );
  }

  final NativeAlarmInventoryResultStatus status;
  final List<NativeAlarmInventoryRow> rows;
  final List<NativeAlarmInventoryIssue> issues;
  final NativeAlarmInventoryFailureReason? failureReason;
  final String? failureMessage;

  bool get isSuccess => status == NativeAlarmInventoryResultStatus.success;

  NativeAlarmInventoryReconciliation reconcile({
    required List<NativeAlarmInventoryExpectedReservation> expected,
  }) {
    final expectedById = <String, NativeAlarmInventoryExpectedReservation>{};
    final issues = <NativeAlarmInventoryIssue>[...this.issues];
    for (final item in expected) {
      if (expectedById.containsKey(item.reservationId)) {
        issues.add(
          NativeAlarmInventoryIssue(
            type: NativeAlarmInventoryIssueType.duplicate,
            reservationId: item.reservationId,
            message: 'Duplicate expected reservation identity.',
          ),
        );
      } else {
        expectedById[item.reservationId] = item;
      }
    }

    final presentIds = <String>{};
    for (final row in rows) {
      final expectedRow = expectedById[row.reservationId];
      if (expectedRow == null) {
        final hasKnownOccurrence = expected.any(
          (item) => item.occurrenceId == row.occurrenceId,
        );
        issues.add(
          NativeAlarmInventoryIssue(
            type: hasKnownOccurrence
                ? NativeAlarmInventoryIssueType.unknown
                : NativeAlarmInventoryIssueType.extra,
            reservationId: row.reservationId,
            message: hasKnownOccurrence
                ? 'Native row has an unknown stable reservation id.'
                : 'Native row is not represented by the expected inventory.',
          ),
        );
        continue;
      }
      presentIds.add(row.reservationId);
      if (row.occurrenceId != expectedRow.occurrenceId ||
          row.wakePlanId != expectedRow.wakePlanId) {
        issues.add(
          NativeAlarmInventoryIssue(
            type: NativeAlarmInventoryIssueType.corrupt,
            reservationId: row.reservationId,
            message: 'Native row identity metadata does not match Flutter.',
          ),
        );
      }
    }

    for (final item in expected) {
      if (!presentIds.contains(item.reservationId)) {
        issues.add(
          NativeAlarmInventoryIssue(
            type: NativeAlarmInventoryIssueType.missing,
            reservationId: item.reservationId,
            message: 'Expected native reservation is missing from inventory.',
          ),
        );
      }
    }

    return NativeAlarmInventoryReconciliation(
      rows: rows,
      issues: issues,
      sourceWasSuccessful: isSuccess,
    );
  }
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

void _validateReservationId(String reservationId) {
  if (reservationId.isEmpty) {
    throw ArgumentError.value(
      reservationId,
      'reservationId',
      'must not be empty',
    );
  }
}

void _validateUniqueReservationIds(
  Iterable<String> reservationIds,
  String name,
) {
  final seenIds = <String>{};
  for (final reservationId in reservationIds) {
    if (!seenIds.add(reservationId)) {
      throw ArgumentError.value(
        reservationId,
        name,
        'contains a duplicate reservationId',
      );
    }
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
