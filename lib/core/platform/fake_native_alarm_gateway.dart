import 'native_alarm_gateway.dart';

typedef PlatformAlarmIdFactory =
    String Function(NativeAlarmScheduleRequest request);

class FakeNativeAlarmGateway implements NativeAlarmGateway {
  FakeNativeAlarmGateway({
    NativeAlarmCapability? capability,
    NativeAlarmPermissionResult? permissionResult,
    PlatformAlarmIdFactory? platformAlarmIdFactory,
    this.testAlarmPlatformId = 'test-platform-alarm',
  }) : capability =
           capability ??
           const NativeAlarmCapability(
             permissionStatus: NativeAlarmPermissionStatus.authorized,
             canScheduleAlarms: true,
             canRequestPermission: true,
             supportsInventory: true,
           ),
       permissionResult =
           permissionResult ??
           const NativeAlarmPermissionResult(
             status: NativeAlarmPermissionRequestStatus.granted,
             permissionStatus: NativeAlarmPermissionStatus.authorized,
           ),
       platformAlarmIdFactory =
           platformAlarmIdFactory ??
           ((request) => 'platform-${request.reservationId}');

  NativeAlarmCapability capability;
  NativeAlarmPermissionResult permissionResult;
  PlatformAlarmIdFactory platformAlarmIdFactory;
  String testAlarmPlatformId;
  ScheduleFailureReason? scheduleFailureReason;
  ScheduleFailureReason? testAlarmFailureReason;
  final Set<String> scheduleFailureOccurrenceIds = <String>{};
  final Set<String> scheduleFailureOccurrenceIdsWithPlatformAlarmIds =
      <String>{};
  final Set<String> cancelFailurePlatformAlarmIds = <String>{};
  final List<NativeAlarmScheduleRequest> scheduledRequests =
      <NativeAlarmScheduleRequest>[];
  final List<NativeAlarmCancelRequest> cancelledOccurrences =
      <NativeAlarmCancelRequest>[];
  final List<NativeAlarmCancelRequest> cancelledPlans =
      <NativeAlarmCancelRequest>[];
  final List<NativeTestAlarmScheduleRequest> scheduledTestAlarms =
      <NativeTestAlarmScheduleRequest>[];
  final List<NativeAlarmInventoryRow> inventoryRows =
      <NativeAlarmInventoryRow>[];
  final Map<String, _FakeReservationRetirement> retiredReservations =
      <String, _FakeReservationRetirement>{};
  final Map<String, NativeAlarmScheduleRequest> _activeRequests =
      <String, NativeAlarmScheduleRequest>{};
  final List<NativeAlarmEvent> pendingAlarmEvents = <NativeAlarmEvent>[];
  final List<String> acknowledgedAlarmEventIds = <String>[];
  NativeAlarmInventoryFailureReason? inventoryFailureReason;

  @override
  Future<NativeAlarmCapability> getCapability() async => capability;

  @override
  Future<NativeAlarmPermissionResult> requestPermission() async {
    return permissionResult;
  }

  @override
  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  ) async {
    ScheduleResult.validateRequests(occurrences);
    scheduledRequests.addAll(occurrences);

    final permissionMissing =
        capability.permissionStatus != NativeAlarmPermissionStatus.authorized ||
        !capability.canScheduleAlarms;
    final globalFailureReason = permissionMissing
        ? ScheduleFailureReason.permissionMissing
        : scheduleFailureReason;

    final results = occurrences.map((request) {
      final platformAlarmId = platformAlarmIdFactory(request);
      final relatedRows = inventoryRows
          .where(
            (row) =>
                row.reservationId == request.reservationId ||
                row.occurrenceId == request.occurrenceId ||
                row.platformAlarmId == platformAlarmId,
          )
          .toList(growable: false);
      final canRebind =
          relatedRows.length <= 1 &&
          relatedRows.every(
            (row) =>
                row.reservationId == request.reservationId &&
                row.wakePlanId == request.wakePlanId &&
                (row.occurrenceId == request.occurrenceId
                    ? request.reservationGeneration >
                              row.reservationGeneration ||
                          (request.reservationGeneration ==
                                  row.reservationGeneration &&
                              _sameSchedulePayload(
                                _activeRequests[row.reservationId],
                                request,
                              ))
                    : request.reservationGeneration >
                          row.reservationGeneration),
          );
      final retirement = retiredReservations[request.reservationId];
      final canAdvanceRetirement = retirement == null
          ? true
          : retirement.wakePlanId == request.wakePlanId &&
                request.reservationGeneration > retirement.generation;
      if (!canRebind || (relatedRows.isEmpty && !canAdvanceRetirement)) {
        return ScheduleOccurrenceResult.failure(
          occurrenceId: request.occurrenceId,
          wakePlanId: request.wakePlanId,
          reason: ScheduleFailureReason.invalidRequest,
          reservationId: request.reservationId,
          reservationGeneration: request.reservationGeneration,
          message: 'Fake native alarm identity conflicts with the request.',
        );
      }
      final occurrenceFailureReason =
          scheduleFailureOccurrenceIds.contains(request.occurrenceId)
          ? ScheduleFailureReason.nativeError
          : globalFailureReason;
      if (occurrenceFailureReason != null) {
        final failedPlatformAlarmId =
            scheduleFailureOccurrenceIdsWithPlatformAlarmIds.contains(
              request.occurrenceId,
            )
            ? platformAlarmIdFactory(request)
            : null;
        final result = ScheduleOccurrenceResult.failure(
          occurrenceId: request.occurrenceId,
          wakePlanId: request.wakePlanId,
          reason: occurrenceFailureReason,
          platformAlarmId: failedPlatformAlarmId,
          reservationId: request.reservationId,
          reservationGeneration: request.reservationGeneration,
        );
        if (failedPlatformAlarmId != null) {
          _upsertInventoryRow(request, failedPlatformAlarmId);
        }
        return result;
      }

      _upsertInventoryRow(request, platformAlarmId);
      return ScheduleOccurrenceResult.success(
        occurrenceId: request.occurrenceId,
        wakePlanId: request.wakePlanId,
        platformAlarmId: platformAlarmId,
        reservationId: request.reservationId,
        reservationGeneration: request.reservationGeneration,
      );
    }).toList();

    return ScheduleResult.fromRequestResults(
      requests: occurrences,
      results: results,
    );
  }

  @override
  Future<CancelResult> cancelOccurrences(
    List<NativeAlarmCancelRequest> alarms,
  ) async {
    CancelResult.validateRequests(alarms);
    cancelledOccurrences.addAll(alarms);
    return _cancel(alarms);
  }

  @override
  Future<CancelResult> cancelPlan(List<NativeAlarmCancelRequest> alarms) async {
    CancelResult.validateRequests(alarms);
    cancelledPlans.addAll(alarms);
    return _cancel(alarms);
  }

  @override
  Future<TestAlarmScheduleResult> scheduleTestAlarm(
    NativeTestAlarmScheduleRequest request,
  ) async {
    scheduledTestAlarms.add(request);

    final permissionMissing =
        capability.permissionStatus != NativeAlarmPermissionStatus.authorized ||
        !capability.canScheduleAlarms;
    final failureReason = permissionMissing
        ? ScheduleFailureReason.permissionMissing
        : !capability.supportsTestAlarm
        ? ScheduleFailureReason.unavailable
        : testAlarmFailureReason;
    if (failureReason != null) {
      return TestAlarmScheduleResult.failure(reason: failureReason);
    }

    return TestAlarmScheduleResult.success(
      platformAlarmId: testAlarmPlatformId,
    );
  }

  @override
  Future<NativeAlarmInventoryResult> getInventory() async {
    if (!capability.supportsInventory) {
      return NativeAlarmInventoryResult.failure(
        reason: NativeAlarmInventoryFailureReason.unavailable,
        message: 'Native inventory is not supported by this fake.',
      );
    }
    final failureReason = inventoryFailureReason;
    if (failureReason != null) {
      return NativeAlarmInventoryResult.failure(reason: failureReason);
    }
    return NativeAlarmInventoryResult.success(rows: inventoryRows);
  }

  @override
  Future<List<NativeAlarmEvent>> fetchAlarmEvents() async {
    final retained = _normalizePendingAlarmEvents();
    if (retained == null) return const [];
    return List<NativeAlarmEvent>.unmodifiable(retained);
  }

  List<NativeAlarmEvent>? _normalizePendingAlarmEvents() {
    final retainedById = <String, NativeAlarmEvent>{};
    for (final event in pendingAlarmEvents) {
      if (event.eventId.trim().isEmpty ||
          event.platformAlarmId.trim().isEmpty ||
          event.timestamp.millisecondsSinceEpoch < 0) {
        return null;
      }
      retainedById[event.eventId] = event;
      if (retainedById.length > 200) {
        final oldest = retainedById.values
            .where((candidate) => candidate.eventId != event.eventId)
            .reduce(_olderAlarmEvent);
        retainedById.remove(oldest.eventId);
      }
    }
    final retained = retainedById.values.toList()..sort(_compareAlarmEvents);
    pendingAlarmEvents
      ..clear()
      ..addAll(retained);
    return retained;
  }

  @override
  Future<void> acknowledgeAlarmEvents(List<String> eventIds) async {
    if (eventIds.any((eventId) => eventId.trim().isEmpty)) {
      throw ArgumentError.value(
        eventIds,
        'eventIds',
        'must contain only non-empty strings',
      );
    }
    if (eventIds.toSet().length != eventIds.length) {
      throw ArgumentError.value(eventIds, 'eventIds', 'must be unique');
    }
    acknowledgedAlarmEventIds.addAll(eventIds);
    if (_normalizePendingAlarmEvents() == null) return;
    pendingAlarmEvents.removeWhere((event) => eventIds.contains(event.eventId));
  }

  NativeAlarmEvent _olderAlarmEvent(
    NativeAlarmEvent left,
    NativeAlarmEvent right,
  ) {
    return _compareAlarmEvents(left, right) <= 0 ? left : right;
  }

  int _compareAlarmEvents(NativeAlarmEvent left, NativeAlarmEvent right) {
    final timestampComparison = left.timestamp.compareTo(right.timestamp);
    return timestampComparison != 0
        ? timestampComparison
        : left.eventId.compareTo(right.eventId);
  }

  CancelResult _cancel(List<NativeAlarmCancelRequest> alarms) {
    final results = alarms.map((alarm) {
      if (cancelFailurePlatformAlarmIds.contains(alarm.platformAlarmId)) {
        return CancelAlarmResult.failure(
          occurrenceId: alarm.occurrenceId,
          platformAlarmId: alarm.platformAlarmId,
          reason: CancelFailureReason.nativeError,
          reservationId: alarm.reservationId,
          reservationGeneration: alarm.reservationGeneration,
        );
      }

      final relatedRows = inventoryRows
          .where(
            (row) =>
                row.reservationId == alarm.reservationId ||
                row.occurrenceId == alarm.occurrenceId ||
                row.platformAlarmId == alarm.platformAlarmId,
          )
          .toList(growable: false);
      final hasExactRow = relatedRows.any(
        (row) =>
            row.reservationId == alarm.reservationId &&
            row.occurrenceId == alarm.occurrenceId &&
            row.platformAlarmId == alarm.platformAlarmId &&
            row.reservationGeneration == alarm.reservationGeneration,
      );
      final retired = retiredReservations[alarm.reservationId];
      final matchesRetirement =
          retired == null || retired.generation == alarm.reservationGeneration;
      if (relatedRows.isNotEmpty && (relatedRows.length != 1 || !hasExactRow)) {
        return CancelAlarmResult.failure(
          occurrenceId: alarm.occurrenceId,
          platformAlarmId: alarm.platformAlarmId,
          reservationId: alarm.reservationId,
          reservationGeneration: alarm.reservationGeneration,
          reason: CancelFailureReason.invalidRequest,
          message: 'Cancel identity does not match fake inventory.',
        );
      }
      if (relatedRows.isEmpty && !matchesRetirement) {
        return CancelAlarmResult.failure(
          occurrenceId: alarm.occurrenceId,
          platformAlarmId: alarm.platformAlarmId,
          reservationId: alarm.reservationId,
          reservationGeneration: alarm.reservationGeneration,
          reason: CancelFailureReason.invalidRequest,
          message: 'Cancel generation does not match fake retirement state.',
        );
      }

      inventoryRows.removeWhere(
        (row) =>
            row.reservationId == alarm.reservationId &&
            row.occurrenceId == alarm.occurrenceId &&
            row.platformAlarmId == alarm.platformAlarmId,
      );
      _activeRequests.remove(alarm.reservationId);
      if (relatedRows.isNotEmpty) {
        retiredReservations[alarm.reservationId] = _FakeReservationRetirement(
          wakePlanId: relatedRows.single.wakePlanId,
          generation: alarm.reservationGeneration,
        );
      }
      return CancelAlarmResult.success(
        occurrenceId: alarm.occurrenceId,
        platformAlarmId: alarm.platformAlarmId,
        reservationId: alarm.reservationId,
        reservationGeneration: alarm.reservationGeneration,
      );
    }).toList();

    return CancelResult.fromRequestResults(requests: alarms, results: results);
  }

  void _upsertInventoryRow(
    NativeAlarmScheduleRequest request,
    String platformAlarmId,
  ) {
    final previous = inventoryRows
        .where((row) => row.reservationId == request.reservationId)
        .firstOrNull;
    if (previous != null &&
        previous.reservationGeneration < request.reservationGeneration) {
      retiredReservations[request.reservationId] = _FakeReservationRetirement(
        wakePlanId: previous.wakePlanId,
        generation: previous.reservationGeneration,
      );
    }
    inventoryRows.removeWhere(
      (row) => row.reservationId == request.reservationId,
    );
    _activeRequests[request.reservationId] = request;
    inventoryRows.add(
      NativeAlarmInventoryRow.create(
        reservationId: request.reservationId,
        occurrenceId: request.occurrenceId,
        wakePlanId: request.wakePlanId,
        platformAlarmId: platformAlarmId,
        status: NativeAlarmReservationStatus.scheduled,
        reservationGeneration: request.reservationGeneration,
      ),
    );
  }

  bool _sameSchedulePayload(
    NativeAlarmScheduleRequest? left,
    NativeAlarmScheduleRequest right,
  ) {
    return left != null &&
        left.occurrenceId == right.occurrenceId &&
        left.reservationId == right.reservationId &&
        left.reservationGeneration == right.reservationGeneration &&
        left.wakePlanId == right.wakePlanId &&
        left.scheduledAt == right.scheduledAt &&
        left.targetAt == right.targetAt &&
        left.indexInPlan == right.indexInPlan &&
        left.totalInPlan == right.totalInPlan &&
        left.soundId == right.soundId &&
        left.vibrationEnabled == right.vibrationEnabled;
  }
}

class _FakeReservationRetirement {
  const _FakeReservationRetirement({
    required this.wakePlanId,
    required this.generation,
  });

  final String wakePlanId;
  final int generation;
}
