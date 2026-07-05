import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NativeAlarmScheduleRequest', () {
    test('validates occurrence identity fields', () {
      expect(
        () => NativeAlarmScheduleRequest(
          occurrenceId: '',
          wakePlanId: 'plan-1',
          scheduledAt: DateTime(2026, 7, 7, 6),
          targetAt: DateTime(2026, 7, 7, 7),
          indexInPlan: 0,
          totalInPlan: 1,
          soundId: 'default',
          vibrationEnabled: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ScheduleResult', () {
    test('treats an empty schedule batch as a successful no-op', () {
      final result = ScheduleResult.fromRequestResults(
        requests: [],
        results: [],
      );

      expect(result.status, ScheduleResultStatus.success);
      expect(result.occurrences, isEmpty);
    });

    test('represents full success with one platform id per occurrence', () {
      final result = ScheduleResult.fromRequestResults(
        requests: _requests(),
        results: [
          ScheduleOccurrenceResult.success(
            occurrenceId: 'occ-1',
            wakePlanId: 'plan-1',
            platformAlarmId: 'ios-uuid-1',
          ),
          ScheduleOccurrenceResult.success(
            occurrenceId: 'occ-2',
            wakePlanId: 'plan-1',
            platformAlarmId: 'ios-uuid-2',
          ),
        ],
      );

      expect(result.status, ScheduleResultStatus.success);
      expect(result.isSuccess, isTrue);
      expect(
        result.occurrences.map((occurrence) => occurrence.platformAlarmId),
        ['ios-uuid-1', 'ios-uuid-2'],
      );
    });

    test('represents partial failures per exact occurrence', () {
      final result = ScheduleResult.fromRequestResults(
        requests: _requests(),
        results: [
          ScheduleOccurrenceResult.success(
            occurrenceId: 'occ-1',
            wakePlanId: 'plan-1',
            platformAlarmId: 'android-pending-intent-1',
          ),
          ScheduleOccurrenceResult.failure(
            occurrenceId: 'occ-2',
            wakePlanId: 'plan-1',
            reason: ScheduleFailureReason.osConstraint,
          ),
        ],
      );

      expect(result.status, ScheduleResultStatus.partialFailure);
      expect(result.isPartialFailure, isTrue);
      expect(
        result.occurrences
            .singleWhere((item) => item.occurrenceId == 'occ-1')
            .platformAlarmId,
        'android-pending-intent-1',
      );
      final failed = result.occurrences.singleWhere(
        (item) => item.occurrenceId == 'occ-2',
      );
      expect(failed.status, ScheduleOccurrenceStatus.failure);
      expect(failed.failureReason, ScheduleFailureReason.osConstraint);
      expect(failed.platformAlarmId, isNull);
    });

    test('maps full permission failure to permissionMissing result', () {
      final result = ScheduleResult.fromRequestResults(
        requests: [_requests().first],
        results: [
          ScheduleOccurrenceResult.failure(
            occurrenceId: 'occ-1',
            wakePlanId: 'plan-1',
            reason: ScheduleFailureReason.permissionMissing,
          ),
        ],
      );

      expect(result.status, ScheduleResultStatus.permissionMissing);
    });

    test('prioritizes permission failures over generic failures', () {
      final result = ScheduleResult.fromRequestResults(
        requests: _requests(),
        results: [
          ScheduleOccurrenceResult.failure(
            occurrenceId: 'occ-1',
            wakePlanId: 'plan-1',
            reason: ScheduleFailureReason.nativeError,
          ),
          ScheduleOccurrenceResult.failure(
            occurrenceId: 'occ-2',
            wakePlanId: 'plan-1',
            reason: ScheduleFailureReason.permissionMissing,
          ),
        ],
      );

      expect(result.status, ScheduleResultStatus.permissionMissing);
    });

    test('prioritizes OS constraints over generic failures', () {
      final result = ScheduleResult.fromRequestResults(
        requests: _requests(),
        results: [
          ScheduleOccurrenceResult.failure(
            occurrenceId: 'occ-1',
            wakePlanId: 'plan-1',
            reason: ScheduleFailureReason.nativeError,
          ),
          ScheduleOccurrenceResult.failure(
            occurrenceId: 'occ-2',
            wakePlanId: 'plan-1',
            reason: ScheduleFailureReason.osConstraint,
          ),
        ],
      );

      expect(result.status, ScheduleResultStatus.osConstraint);
    });

    test('marks missing native schedule rows as per-occurrence failures', () {
      final result = ScheduleResult.fromRequestResults(
        requests: _requests(),
        results: [
          ScheduleOccurrenceResult.success(
            occurrenceId: 'occ-1',
            wakePlanId: 'plan-1',
            platformAlarmId: 'platform-occ-1',
          ),
        ],
      );

      expect(result.status, ScheduleResultStatus.partialFailure);
      final missing = result.occurrences.singleWhere(
        (item) => item.occurrenceId == 'occ-2',
      );
      expect(missing.failureReason, ScheduleFailureReason.nativeError);
      expect(missing.platformAlarmId, isNull);
    });

    test('rejects extra native schedule rows', () {
      expect(
        () => ScheduleResult.fromRequestResults(
          requests: [_requests().first],
          results: [
            ScheduleOccurrenceResult.success(
              occurrenceId: 'occ-2',
              wakePlanId: 'plan-1',
              platformAlarmId: 'platform-occ-2',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects schedule rows for the wrong wake plan id', () {
      expect(
        () => ScheduleResult.fromRequestResults(
          requests: [_requests().first],
          results: [
            ScheduleOccurrenceResult.success(
              occurrenceId: 'occ-1',
              wakePlanId: 'plan-2',
              platformAlarmId: 'platform-occ-1',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects result rows that cannot correlate to an occurrence', () {
      expect(
        () => ScheduleOccurrenceResult.success(
          occurrenceId: '',
          wakePlanId: 'plan-1',
          platformAlarmId: 'platform-occ-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => ScheduleOccurrenceResult.failure(
          occurrenceId: 'occ-1',
          wakePlanId: '',
          reason: ScheduleFailureReason.nativeError,
        ),
        throwsArgumentError,
      );
    });
  });

  group('FakeNativeAlarmGateway', () {
    test('schedules all occurrences and records native ids', () async {
      final gateway = FakeNativeAlarmGateway(
        platformAlarmIdFactory: (request) => 'native-${request.occurrenceId}',
      );

      final result = await gateway.scheduleOccurrences(_requests());

      expect(result.status, ScheduleResultStatus.success);
      expect(gateway.scheduledRequests.map((request) => request.occurrenceId), [
        'occ-1',
        'occ-2',
      ]);
      expect(
        result.occurrences.map((occurrence) => occurrence.platformAlarmId),
        ['native-occ-1', 'native-occ-2'],
      );
    });

    test('fails every schedule when permission is missing', () async {
      final gateway = FakeNativeAlarmGateway(
        capability: const NativeAlarmCapability(
          permissionStatus: NativeAlarmPermissionStatus.denied,
          canScheduleAlarms: false,
          canRequestPermission: true,
        ),
      );

      final result = await gateway.scheduleOccurrences(_requests());

      expect(result.status, ScheduleResultStatus.permissionMissing);
      expect(result.occurrences.map((occurrence) => occurrence.failureReason), [
        ScheduleFailureReason.permissionMissing,
        ScheduleFailureReason.permissionMissing,
      ]);
      expect(
        result.occurrences.map((occurrence) => occurrence.platformAlarmId),
        [isNull, isNull],
      );
    });

    test('supports a configured partial failure', () async {
      final gateway = FakeNativeAlarmGateway();
      gateway.scheduleFailureOccurrenceIds.add('occ-2');

      final result = await gateway.scheduleOccurrences(_requests());

      expect(result.status, ScheduleResultStatus.partialFailure);
      final successful = result.occurrences.singleWhere(
        (item) => item.occurrenceId == 'occ-1',
      );
      final failed = result.occurrences.singleWhere(
        (item) => item.occurrenceId == 'occ-2',
      );
      expect(successful.platformAlarmId, 'platform-occ-1');
      expect(failed.failureReason, ScheduleFailureReason.nativeError);
      expect(failed.platformAlarmId, isNull);
    });

    test(
      'preserves failed occurrence platform ids when native created one',
      () async {
        final gateway = FakeNativeAlarmGateway();
        gateway.scheduleFailureOccurrenceIds.add('occ-2');
        gateway.scheduleFailureOccurrenceIdsWithPlatformAlarmIds.add('occ-2');

        final result = await gateway.scheduleOccurrences(_requests());

        final failed = result.occurrences.singleWhere(
          (item) => item.occurrenceId == 'occ-2',
        );
        expect(failed.failureReason, ScheduleFailureReason.nativeError);
        expect(failed.platformAlarmId, 'platform-occ-2');
      },
    );

    test('chooses the dominant status when all fake schedules fail', () async {
      final gateway = FakeNativeAlarmGateway()
        ..scheduleFailureReason = ScheduleFailureReason.permissionMissing
        ..scheduleFailureOccurrenceIds.add('occ-2');

      final result = await gateway.scheduleOccurrences(_requests());

      expect(result.status, ScheduleResultStatus.permissionMissing);
      expect(result.occurrences.map((occurrence) => occurrence.failureReason), [
        ScheduleFailureReason.permissionMissing,
        ScheduleFailureReason.nativeError,
      ]);
    });

    test('cancels plans by resolved occurrence and platform ids', () async {
      final gateway = FakeNativeAlarmGateway();

      final result = await gateway.cancelPlan([
        NativeAlarmCancelRequest(
          occurrenceId: 'occ-1',
          platformAlarmId: 'platform-occ-1',
        ),
        NativeAlarmCancelRequest(
          occurrenceId: 'occ-2',
          platformAlarmId: 'platform-occ-2',
        ),
      ]);

      expect(result.status, CancelResultStatus.success);
      expect(gateway.cancelledPlans.map((request) => request.occurrenceId), [
        'occ-1',
        'occ-2',
      ]);
      expect(gateway.cancelledPlans.map((request) => request.platformAlarmId), [
        'platform-occ-1',
        'platform-occ-2',
      ]);
    });

    test('reports cancel partial failures per platform alarm id', () async {
      final gateway = FakeNativeAlarmGateway();
      gateway.cancelFailurePlatformAlarmIds.add('platform-occ-2');

      final result = await gateway.cancelOccurrences([
        NativeAlarmCancelRequest(
          occurrenceId: 'occ-1',
          platformAlarmId: 'platform-occ-1',
        ),
        NativeAlarmCancelRequest(
          occurrenceId: 'occ-2',
          platformAlarmId: 'platform-occ-2',
        ),
      ]);

      expect(result.status, CancelResultStatus.partialFailure);
      final failed = result.alarms.singleWhere(
        (alarm) => alarm.occurrenceId == 'occ-2',
      );
      expect(failed.failureReason, CancelFailureReason.nativeError);
      expect(failed.platformAlarmId, 'platform-occ-2');
    });

    test('cancel result rows require persisted platform alarm identity', () {
      expect(
        () => CancelAlarmResult.success(
          occurrenceId: 'occ-1',
          platformAlarmId: '',
        ),
        throwsArgumentError,
      );
    });

    test('marks missing native cancel rows as per-occurrence failures', () {
      final result = CancelResult.fromRequestResults(
        requests: [
          NativeAlarmCancelRequest(
            occurrenceId: 'occ-1',
            platformAlarmId: 'platform-occ-1',
          ),
          NativeAlarmCancelRequest(
            occurrenceId: 'occ-2',
            platformAlarmId: 'platform-occ-2',
          ),
        ],
        results: [
          CancelAlarmResult.success(
            occurrenceId: 'occ-1',
            platformAlarmId: 'platform-occ-1',
          ),
        ],
      );

      expect(result.status, CancelResultStatus.partialFailure);
      final missing = result.alarms.singleWhere(
        (alarm) => alarm.occurrenceId == 'occ-2',
      );
      expect(missing.failureReason, CancelFailureReason.nativeError);
      expect(missing.platformAlarmId, 'platform-occ-2');
    });

    test('rejects cancel rows for the wrong platform alarm id', () {
      expect(
        () => CancelResult.fromRequestResults(
          requests: [
            NativeAlarmCancelRequest(
              occurrenceId: 'occ-1',
              platformAlarmId: 'platform-occ-1',
            ),
          ],
          results: [
            CancelAlarmResult.success(
              occurrenceId: 'occ-1',
              platformAlarmId: 'platform-occ-2',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('schedules distinguishable test alarms', () async {
      final gateway = FakeNativeAlarmGateway(testAlarmPlatformId: 'test-id-1');

      final result = await gateway.scheduleTestAlarm(
        NativeTestAlarmScheduleRequest(fireAfter: const Duration(minutes: 1)),
      );

      expect(result.status, ScheduleResultStatus.success);
      expect(result.platformAlarmId, 'test-id-1');
      expect(
        gateway.scheduledTestAlarms.single.fireAfter,
        Duration(minutes: 1),
      );
    });

    test('reports permission missing for test alarm schedule', () async {
      final gateway = FakeNativeAlarmGateway(
        capability: const NativeAlarmCapability(
          permissionStatus: NativeAlarmPermissionStatus.denied,
          canScheduleAlarms: false,
          canRequestPermission: true,
        ),
      );

      final result = await gateway.scheduleTestAlarm(
        NativeTestAlarmScheduleRequest(fireAfter: const Duration(minutes: 1)),
      );

      expect(result.status, ScheduleResultStatus.permissionMissing);
      expect(result.failureReason, ScheduleFailureReason.permissionMissing);
      expect(result.platformAlarmId, isNull);
    });

    test('reports unsupported test alarms as unavailable', () async {
      final gateway = FakeNativeAlarmGateway(
        capability: const NativeAlarmCapability(
          permissionStatus: NativeAlarmPermissionStatus.authorized,
          canScheduleAlarms: true,
          canRequestPermission: true,
          supportsTestAlarm: false,
        ),
      );

      final result = await gateway.scheduleTestAlarm(
        NativeTestAlarmScheduleRequest(fireAfter: const Duration(minutes: 1)),
      );

      expect(result.status, ScheduleResultStatus.failure);
      expect(result.failureReason, ScheduleFailureReason.unavailable);
      expect(result.platformAlarmId, isNull);
    });
  });
}

List<NativeAlarmScheduleRequest> _requests() {
  return [
    NativeAlarmScheduleRequest(
      occurrenceId: 'occ-1',
      wakePlanId: 'plan-1',
      scheduledAt: DateTime(2026, 7, 7, 6),
      targetAt: DateTime(2026, 7, 7, 7),
      indexInPlan: 0,
      totalInPlan: 2,
      soundId: 'default',
      vibrationEnabled: true,
    ),
    NativeAlarmScheduleRequest(
      occurrenceId: 'occ-2',
      wakePlanId: 'plan-1',
      scheduledAt: DateTime(2026, 7, 7, 6, 5),
      targetAt: DateTime(2026, 7, 7, 7),
      indexInPlan: 1,
      totalInPlan: 2,
      soundId: 'default',
      vibrationEnabled: true,
    ),
  ];
}
