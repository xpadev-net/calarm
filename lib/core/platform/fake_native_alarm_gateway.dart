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
           ((request) => 'platform-${request.occurrenceId}');

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
        );
        if (failedPlatformAlarmId != null) {
          _upsertInventoryRow(request, failedPlatformAlarmId);
        }
        return result;
      }

      final platformAlarmId = platformAlarmIdFactory(request);
      _upsertInventoryRow(request, platformAlarmId);
      return ScheduleOccurrenceResult.success(
        occurrenceId: request.occurrenceId,
        wakePlanId: request.wakePlanId,
        platformAlarmId: platformAlarmId,
        reservationId: request.reservationId,
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

  CancelResult _cancel(List<NativeAlarmCancelRequest> alarms) {
    final results = alarms.map((alarm) {
      if (cancelFailurePlatformAlarmIds.contains(alarm.platformAlarmId)) {
        return CancelAlarmResult.failure(
          occurrenceId: alarm.occurrenceId,
          platformAlarmId: alarm.platformAlarmId,
          reason: CancelFailureReason.nativeError,
          reservationId: alarm.reservationId,
        );
      }

      final relatedRows = inventoryRows.where(
        (row) =>
            row.reservationId == alarm.reservationId ||
            row.occurrenceId == alarm.occurrenceId ||
            row.platformAlarmId == alarm.platformAlarmId,
      );
      final hasExactRow = relatedRows.any(
        (row) =>
            row.reservationId == alarm.reservationId &&
            row.occurrenceId == alarm.occurrenceId &&
            row.platformAlarmId == alarm.platformAlarmId,
      );
      if (relatedRows.isNotEmpty && (relatedRows.length != 1 || !hasExactRow)) {
        return CancelAlarmResult.failure(
          occurrenceId: alarm.occurrenceId,
          platformAlarmId: alarm.platformAlarmId,
          reservationId: alarm.reservationId,
          reason: CancelFailureReason.invalidRequest,
          message: 'Cancel identity does not match fake inventory.',
        );
      }

      inventoryRows.removeWhere(
        (row) =>
            row.reservationId == alarm.reservationId &&
            row.occurrenceId == alarm.occurrenceId &&
            row.platformAlarmId == alarm.platformAlarmId,
      );
      return CancelAlarmResult.success(
        occurrenceId: alarm.occurrenceId,
        platformAlarmId: alarm.platformAlarmId,
        reservationId: alarm.reservationId,
      );
    }).toList();

    return CancelResult.fromRequestResults(requests: alarms, results: results);
  }

  void _upsertInventoryRow(
    NativeAlarmScheduleRequest request,
    String platformAlarmId,
  ) {
    inventoryRows.removeWhere(
      (row) => row.reservationId == request.reservationId,
    );
    inventoryRows.add(
      NativeAlarmInventoryRow.create(
        reservationId: request.reservationId,
        occurrenceId: request.occurrenceId,
        wakePlanId: request.wakePlanId,
        platformAlarmId: platformAlarmId,
        status: NativeAlarmReservationStatus.scheduled,
      ),
    );
  }
}
