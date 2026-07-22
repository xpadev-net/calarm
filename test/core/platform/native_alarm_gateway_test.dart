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

    test('defaults the stable reservation id to occurrence id', () {
      final request = _requests().first;

      expect(request.reservationId, request.occurrenceId);
    });

    test('accepts a caller-persisted stable reservation id', () {
      final request = NativeAlarmScheduleRequest(
        occurrenceId: 'occ-1',
        reservationId: 'reservation-1',
        wakePlanId: 'plan-1',
        scheduledAt: DateTime(2026, 7, 7, 6),
        targetAt: DateTime(2026, 7, 7, 7),
        indexInPlan: 0,
        totalInPlan: 1,
        soundId: 'default',
        vibrationEnabled: true,
      );

      expect(request.reservationId, 'reservation-1');
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

    test('restores the requested reservation id from a legacy native row', () {
      final request = _requests().first;
      final customRequest = NativeAlarmScheduleRequest(
        occurrenceId: request.occurrenceId,
        reservationId: 'reservation-1',
        wakePlanId: request.wakePlanId,
        scheduledAt: request.scheduledAt,
        targetAt: request.targetAt,
        indexInPlan: request.indexInPlan,
        totalInPlan: request.totalInPlan,
        soundId: request.soundId,
        vibrationEnabled: request.vibrationEnabled,
      );

      final result = ScheduleResult.fromRequestResults(
        requests: [customRequest],
        results: [
          ScheduleOccurrenceResult.success(
            occurrenceId: customRequest.occurrenceId,
            wakePlanId: customRequest.wakePlanId,
            platformAlarmId: 'platform-occ-1',
          ),
        ],
      );

      expect(result.occurrences.single.reservationId, 'reservation-1');
    });

    test('rejects duplicate logical or native result identities', () {
      final first = _requests().first;
      final second = NativeAlarmScheduleRequest(
        occurrenceId: first.occurrenceId,
        reservationId: 'reservation-2',
        wakePlanId: 'plan-2',
        scheduledAt: first.scheduledAt,
        targetAt: first.targetAt,
        indexInPlan: 0,
        totalInPlan: 1,
        soundId: first.soundId,
        vibrationEnabled: first.vibrationEnabled,
      );

      expect(
        () => ScheduleResult.fromRequestResults(
          requests: [first, second],
          results: [
            ScheduleOccurrenceResult.success(
              occurrenceId: first.occurrenceId,
              wakePlanId: first.wakePlanId,
              platformAlarmId: 'platform-1',
            ),
            ScheduleOccurrenceResult.success(
              occurrenceId: second.occurrenceId,
              wakePlanId: second.wakePlanId,
              platformAlarmId: 'platform-2',
              reservationId: second.reservationId,
            ),
          ],
        ),
        throwsArgumentError,
      );

      expect(
        () => ScheduleResult.fromRequestResults(
          requests: _requests(),
          results: [
            ScheduleOccurrenceResult.success(
              occurrenceId: 'occ-1',
              wakePlanId: 'plan-1',
              platformAlarmId: 'shared-platform',
            ),
            ScheduleOccurrenceResult.success(
              occurrenceId: 'occ-2',
              wakePlanId: 'plan-1',
              platformAlarmId: 'shared-platform',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('NativeAlarmInventoryResult', () {
    test('accepts a stable reservation rebound to a different occurrence', () {
      final result = NativeAlarmInventoryResult.success(
        rows: [
          NativeAlarmInventoryRow.create(
            reservationId: 'stable-slot',
            occurrenceId: 'current-occurrence',
            wakePlanId: 'plan-1',
            platformAlarmId: 'current-platform',
            status: NativeAlarmReservationStatus.scheduled,
          ),
        ],
      );

      final reconciliation = result.reconcile(
        expected: [
          NativeAlarmInventoryExpectedReservation(
            reservationId: 'stable-slot',
            occurrenceId: 'current-occurrence',
            wakePlanId: 'plan-1',
          ),
        ],
      );

      expect(result.isSuccess, isTrue);
      expect(reconciliation.isAuthoritative, isTrue);
      expect(reconciliation.issues, isEmpty);
    });

    test('reports duplicate, unknown, missing, extra, and corrupt rows', () {
      final result = NativeAlarmInventoryResult.success(
        rows: [
          _inventoryRow('unknown-reservation', occurrenceId: 'occ-1'),
          _inventoryRow('extra-reservation', occurrenceId: 'other-occ'),
          _inventoryRow('reservation-2', occurrenceId: 'wrong-occ'),
        ],
      );

      final reconciliation = result.reconcile(
        expected: [
          NativeAlarmInventoryExpectedReservation(
            reservationId: 'reservation-1',
            occurrenceId: 'occ-1',
            wakePlanId: 'plan-1',
          ),
          NativeAlarmInventoryExpectedReservation(
            reservationId: 'missing-reservation',
            occurrenceId: 'missing-occ',
            wakePlanId: 'plan-1',
          ),
          NativeAlarmInventoryExpectedReservation(
            reservationId: 'reservation-2',
            occurrenceId: 'occ-2',
            wakePlanId: 'plan-1',
          ),
        ],
      );

      expect(reconciliation.isAuthoritative, isFalse);
      expect(
        reconciliation.issues.map((issue) => issue.type),
        containsAll(<NativeAlarmInventoryIssueType>[
          NativeAlarmInventoryIssueType.unknown,
          NativeAlarmInventoryIssueType.extra,
          NativeAlarmInventoryIssueType.missing,
          NativeAlarmInventoryIssueType.corrupt,
        ]),
      );
    });

    test('rejects distinct rows that reuse native or logical identities', () {
      final result = NativeAlarmInventoryResult.success(
        rows: [
          _inventoryRow('reservation-1', occurrenceId: 'occ-1'),
          NativeAlarmInventoryRow.create(
            reservationId: 'reservation-2',
            occurrenceId: 'occ-2',
            wakePlanId: 'plan-1',
            platformAlarmId: 'platform-reservation-1',
            status: NativeAlarmReservationStatus.scheduled,
          ),
          NativeAlarmInventoryRow.create(
            reservationId: 'reservation-3',
            occurrenceId: 'occ-1',
            wakePlanId: 'plan-1',
            platformAlarmId: 'platform-reservation-3',
            status: NativeAlarmReservationStatus.scheduled,
          ),
        ],
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.issues
            .where(
              (issue) => issue.type == NativeAlarmInventoryIssueType.duplicate,
            )
            .length,
        greaterThanOrEqualTo(2),
      );
    });

    test('unavailable inventory is not an empty successful snapshot', () {
      final result = NativeAlarmInventoryResult.failure(
        reason: NativeAlarmInventoryFailureReason.unavailable,
      );

      expect(result.status, NativeAlarmInventoryResultStatus.unavailable);
      expect(result.isSuccess, isFalse);
      expect(result.rows, isEmpty);
      final reconciliation = result.reconcile(expected: const []);
      expect(reconciliation.isAuthoritative, isFalse);
      expect(
        reconciliation.issues.single.type,
        NativeAlarmInventoryIssueType.readFailure,
      );
    });

    test('corrupt inventory issues are not relabeled as read failures', () {
      final result = NativeAlarmInventoryResult.success(
        rows: [
          _inventoryRow('reservation-1', occurrenceId: 'occ-1'),
          _inventoryRow('reservation-1', occurrenceId: 'occ-2'),
        ],
      );

      final reconciliation = result.reconcile(expected: const []);

      expect(reconciliation.isAuthoritative, isFalse);
      expect(
        reconciliation.issues.every(
          (issue) => issue.type != NativeAlarmInventoryIssueType.readFailure,
        ),
        isTrue,
      );
      expect(
        reconciliation.issues.any(
          (issue) => issue.type == NativeAlarmInventoryIssueType.duplicate,
        ),
        isTrue,
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

    test('rejects duplicate schedule requests before fake mutation', () async {
      final gateway = FakeNativeAlarmGateway();
      final duplicateRequests = [_requests().first, _requests().first];

      await expectLater(
        gateway.scheduleOccurrences(duplicateRequests),
        throwsArgumentError,
      );

      expect(gateway.scheduledRequests, isEmpty);
      expect(gateway.inventoryRows, isEmpty);
    });

    test(
      'keeps stable inventory identity across duplicate schedule calls',
      () async {
        final gateway = FakeNativeAlarmGateway();
        final request = NativeAlarmScheduleRequest(
          occurrenceId: 'occ-1',
          reservationId: 'reservation-1',
          wakePlanId: 'plan-1',
          scheduledAt: DateTime(2026, 7, 7, 6),
          targetAt: DateTime(2026, 7, 7, 7),
          indexInPlan: 0,
          totalInPlan: 1,
          soundId: 'default',
          vibrationEnabled: true,
        );

        await gateway.scheduleOccurrences([request]);
        await gateway.scheduleOccurrences([request]);
        final inventory = await gateway.getInventory();

        expect(inventory.isSuccess, isTrue);
        expect(inventory.rows, hasLength(1));
        expect(inventory.rows.single.reservationId, 'reservation-1');
        expect(inventory.rows.single.platformAlarmId, 'platform-reservation-1');
      },
    );

    test(
      'fake atomically rebinds one reservation to a recreated occurrence',
      () async {
        final gateway = FakeNativeAlarmGateway();
        final original = _requests().first;
        final retried = NativeAlarmScheduleRequest(
          occurrenceId: 'occ-2',
          reservationId: original.reservationId,
          wakePlanId: original.wakePlanId,
          scheduledAt: original.scheduledAt,
          targetAt: original.targetAt,
          indexInPlan: original.indexInPlan,
          totalInPlan: original.totalInPlan,
          soundId: original.soundId,
          vibrationEnabled: original.vibrationEnabled,
        );

        await gateway.scheduleOccurrences([original]);
        final result = await gateway.scheduleOccurrences([retried]);

        expect(result.isSuccess, isTrue);
        final inventory = await gateway.getInventory();
        expect(inventory.rows, hasLength(1));
        expect(inventory.rows.single.reservationId, original.reservationId);
        expect(inventory.rows.single.occurrenceId, retried.occurrenceId);
        expect(inventory.rows.single.wakePlanId, retried.wakePlanId);
        final cancel = await gateway.cancelOccurrences([
          NativeAlarmCancelRequest(
            occurrenceId: original.occurrenceId,
            reservationId: original.reservationId,
            platformAlarmId: 'platform-occ-1',
          ),
        ]);
        expect(cancel.status, CancelResultStatus.failure);
        expect(
          cancel.alarms.single.failureReason,
          CancelFailureReason.invalidRequest,
        );
        expect((await gateway.getInventory()).rows, hasLength(1));
      },
    );

    test(
      'fake recreation side effect with a lost reply retains only the new generation',
      () async {
        final gateway = FakeNativeAlarmGateway();
        final original = _requests().first;
        final recreated = NativeAlarmScheduleRequest(
          occurrenceId: 'occ-recreated-after-side-effect',
          reservationId: original.reservationId,
          wakePlanId: original.wakePlanId,
          scheduledAt: original.scheduledAt,
          targetAt: original.targetAt,
          indexInPlan: original.indexInPlan,
          totalInPlan: original.totalInPlan,
          soundId: original.soundId,
          vibrationEnabled: original.vibrationEnabled,
        );
        await gateway.scheduleOccurrences([original]);
        gateway.scheduleFailureOccurrenceIds.add(recreated.occurrenceId);
        gateway.scheduleFailureOccurrenceIdsWithPlatformAlarmIds.add(
          recreated.occurrenceId,
        );

        final result = await gateway.scheduleOccurrences([recreated]);
        final inventory = await gateway.getInventory();

        expect(result.isSuccess, isFalse);
        expect(result.occurrences.single.platformAlarmId, isNotNull);
        expect(inventory.rows, hasLength(1));
        expect(inventory.rows.single.reservationId, original.reservationId);
        expect(inventory.rows.single.occurrenceId, recreated.occurrenceId);
      },
    );

    test(
      'fake rejects cross-plan reservation rebinding without mutation',
      () async {
        final gateway = FakeNativeAlarmGateway();
        final original = _requests().first;
        await gateway.scheduleOccurrences([original]);

        final result = await gateway.scheduleOccurrences([
          NativeAlarmScheduleRequest(
            occurrenceId: 'occ-recreated',
            reservationId: original.reservationId,
            wakePlanId: 'other-plan',
            scheduledAt: original.scheduledAt,
            targetAt: original.targetAt,
            indexInPlan: 0,
            totalInPlan: 1,
            soundId: original.soundId,
            vibrationEnabled: original.vibrationEnabled,
          ),
        ]);

        expect(result.isSuccess, isFalse);
        expect(
          result.occurrences.single.failureReason,
          ScheduleFailureReason.invalidRequest,
        );
        final inventory = await gateway.getInventory();
        expect(inventory.rows, hasLength(1));
        expect(inventory.rows.single.occurrenceId, original.occurrenceId);
        expect(inventory.rows.single.wakePlanId, original.wakePlanId);
      },
    );

    test(
      'fake rejects an occurrence already owned by another reservation',
      () async {
        final gateway = FakeNativeAlarmGateway();
        final original = _requests().first;
        await gateway.scheduleOccurrences([original]);

        final result = await gateway.scheduleOccurrences([
          NativeAlarmScheduleRequest(
            occurrenceId: original.occurrenceId,
            reservationId: 'foreign-reservation',
            wakePlanId: original.wakePlanId,
            scheduledAt: original.scheduledAt,
            targetAt: original.targetAt,
            indexInPlan: 0,
            totalInPlan: 1,
            soundId: original.soundId,
            vibrationEnabled: original.vibrationEnabled,
          ),
        ]);

        expect(result.isSuccess, isFalse);
        expect((await gateway.getInventory()).rows, hasLength(1));
      },
    );

    test(
      'rejects a stale platform id while the reservation is inventoried',
      () async {
        final gateway = FakeNativeAlarmGateway();
        await gateway.scheduleOccurrences([_requests().first]);

        final result = await gateway.cancelOccurrences([
          NativeAlarmCancelRequest(
            occurrenceId: 'occ-1',
            reservationId: 'occ-1',
            platformAlarmId: 'stale-platform-id',
          ),
        ]);

        expect(result.status, CancelResultStatus.failure);
        expect(
          result.alarms.single.failureReason,
          CancelFailureReason.invalidRequest,
        );
        expect((await gateway.getInventory()).rows, hasLength(1));
      },
    );

    test(
      'rejects cancellation when the inventory has a conflicting duplicate',
      () async {
        final gateway = FakeNativeAlarmGateway();
        await gateway.scheduleOccurrences([_requests().first]);
        gateway.inventoryRows.add(
          NativeAlarmInventoryRow.create(
            reservationId: 'occ-1',
            occurrenceId: 'occ-1',
            wakePlanId: 'plan-1',
            platformAlarmId: 'conflicting-platform-id',
            status: NativeAlarmReservationStatus.scheduled,
          ),
        );

        final result = await gateway.cancelOccurrences([
          NativeAlarmCancelRequest(
            occurrenceId: 'occ-1',
            platformAlarmId: 'platform-occ-1',
          ),
        ]);

        expect(result.status, CancelResultStatus.failure);
        expect((await gateway.getInventory()).rows, hasLength(2));
      },
    );

    test('fake inventory honors unsupported capability', () async {
      final gateway = FakeNativeAlarmGateway(
        capability: const NativeAlarmCapability(
          permissionStatus: NativeAlarmPermissionStatus.authorized,
          canScheduleAlarms: true,
          canRequestPermission: true,
          supportsInventory: false,
        ),
      );

      final result = await gateway.getInventory();

      expect(result.status, NativeAlarmInventoryResultStatus.unavailable);
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

    test('rejects duplicate cancel requests before fake mutation', () async {
      final gateway = FakeNativeAlarmGateway();
      final duplicateRequests = [
        NativeAlarmCancelRequest(
          occurrenceId: 'occ-1',
          platformAlarmId: 'platform-occ-1',
        ),
        NativeAlarmCancelRequest(
          occurrenceId: 'occ-1',
          platformAlarmId: 'platform-occ-1',
        ),
      ];

      await expectLater(
        gateway.cancelOccurrences(duplicateRequests),
        throwsArgumentError,
      );

      expect(gateway.cancelledOccurrences, isEmpty);
      expect(gateway.inventoryRows, isEmpty);
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

    test('rejects an empty recoverable test alarm id', () {
      expect(
        () => TestAlarmScheduleResult.failure(
          reason: ScheduleFailureReason.nativeError,
          platformAlarmId: '  ',
        ),
        throwsArgumentError,
      );
    });

    test('retains a non-empty recoverable test alarm id on failure', () {
      final result = TestAlarmScheduleResult.failure(
        reason: ScheduleFailureReason.nativeError,
        platformAlarmId: 'recoverable-test-id',
      );

      expect(result.status, ScheduleResultStatus.failure);
      expect(result.platformAlarmId, 'recoverable-test-id');
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

NativeAlarmInventoryRow _inventoryRow(
  String reservationId, {
  required String occurrenceId,
}) {
  return NativeAlarmInventoryRow.create(
    reservationId: reservationId,
    occurrenceId: occurrenceId,
    wakePlanId: 'plan-1',
    platformAlarmId: 'platform-$reservationId',
    status: NativeAlarmReservationStatus.scheduled,
  );
}
