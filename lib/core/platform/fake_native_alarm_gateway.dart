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
        return ScheduleOccurrenceResult.failure(
          occurrenceId: request.occurrenceId,
          wakePlanId: request.wakePlanId,
          reason: occurrenceFailureReason,
          platformAlarmId: failedPlatformAlarmId,
        );
      }

      return ScheduleOccurrenceResult.success(
        occurrenceId: request.occurrenceId,
        wakePlanId: request.wakePlanId,
        platformAlarmId: platformAlarmIdFactory(request),
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
    cancelledOccurrences.addAll(alarms);
    return _cancel(alarms);
  }

  @override
  Future<CancelResult> cancelPlan(List<NativeAlarmCancelRequest> alarms) async {
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

  CancelResult _cancel(List<NativeAlarmCancelRequest> alarms) {
    final results = alarms.map((alarm) {
      if (cancelFailurePlatformAlarmIds.contains(alarm.platformAlarmId)) {
        return CancelAlarmResult.failure(
          occurrenceId: alarm.occurrenceId,
          platformAlarmId: alarm.platformAlarmId,
          reason: CancelFailureReason.nativeError,
        );
      }

      return CancelAlarmResult.success(
        occurrenceId: alarm.occurrenceId,
        platformAlarmId: alarm.platformAlarmId,
      );
    }).toList();

    return CancelResult.fromRequestResults(requests: alarms, results: results);
  }
}
