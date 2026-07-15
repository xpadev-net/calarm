import 'dart:async';

import 'package:calarm/core/platform/method_channel_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.native_alarm');
  late List<MethodCall> calls;
  late MethodChannelNativeAlarmGateway gateway;

  setUp(() {
    calls = <MethodCall>[];
    gateway = MethodChannelNativeAlarmGateway(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getCapability calls MethodChannel with schema version', () async {
    _setHandler(channel, calls, (call) {
      expect(call.method, 'getCapability');
      expect(call.arguments, {'schemaVersion': 1});
      return {
        'schemaVersion': 1,
        'permissionStatus': 'authorized',
        'canScheduleAlarms': true,
        'canRequestPermission': false,
        'maxPendingAlarms': 64,
        'requiresExactAlarmPermission': true,
        'requiresNotificationPermission': true,
        'requiresFullScreenIntentPermission': false,
        'requiresNotificationChannelSetup': true,
        'supportsTestAlarm': true,
      };
    });

    final capability = await gateway.getCapability();

    expect(capability.permissionStatus, NativeAlarmPermissionStatus.authorized);
    expect(capability.canScheduleAlarms, isTrue);
    expect(capability.canRequestPermission, isFalse);
    expect(capability.maxPendingAlarms, 64);
    expect(capability.requiresExactAlarmPermission, isTrue);
    expect(capability.requiresNotificationPermission, isTrue);
    expect(capability.requiresFullScreenIntentPermission, isFalse);
    expect(capability.requiresNotificationChannelSetup, isTrue);
    expect(calls.single.method, 'getCapability');
  });

  test(
    'getCapability normalizes malformed response to typed failure',
    () async {
      _setHandler(channel, calls, (_) => {'schemaVersion': 1});

      await expectLater(
        gateway.getCapability(),
        throwsA(
          isA<NativeAlarmCapabilityException>().having(
            (error) => error.reason,
            'reason',
            NativeAlarmCapabilityFailureReason.malformedResponse,
          ),
        ),
      );
    },
  );

  test('getCapability normalizes channel failure to typed failure', () async {
    _setHandler(channel, calls, (_) {
      throw PlatformException(code: 'BROKEN', message: 'bridge failed');
    });

    await expectLater(
      gateway.getCapability(),
      throwsA(
        isA<NativeAlarmCapabilityException>().having(
          (error) => error.reason,
          'reason',
          NativeAlarmCapabilityFailureReason.transport,
        ),
      ),
    );
  });

  test(
    'getCapability keeps domain default for omitted test alarm support',
    () async {
      _setHandler(channel, calls, (_) {
        return {
          'schemaVersion': 1,
          'permissionStatus': 'authorized',
          'canScheduleAlarms': true,
          'canRequestPermission': true,
        };
      });

      final capability = await gateway.getCapability();

      expect(capability.supportsTestAlarm, isTrue);
      expect(capability.supportsInventory, isFalse);
    },
  );

  test('getInventory reads stable identities and native status', () async {
    _setHandler(channel, calls, (call) {
      expect(call.method, 'getInventory');
      expect(call.arguments, {'schemaVersion': 1});
      return {
        'schemaVersion': 1,
        'reservations': [
          {
            'reservationId': 'reservation-1',
            'occurrenceId': 'occ-1',
            'wakePlanId': 'plan-1',
            'platformAlarmId': 'platform-occ-1',
            'status': 'ringing',
          },
        ],
      };
    });

    final result = await gateway.getInventory();

    expect(result.status, NativeAlarmInventoryResultStatus.success);
    expect(result.rows.single.reservationId, 'reservation-1');
    expect(result.rows.single.status, NativeAlarmReservationStatus.ringing);
  });

  test(
    'getInventory treats old native implementations as unavailable',
    () async {
      _setHandler(channel, calls, (_) {
        throw MissingPluginException('getInventory is not implemented');
      });

      final result = await gateway.getInventory();

      expect(result.status, NativeAlarmInventoryResultStatus.unavailable);
      expect(
        result.failureReason,
        NativeAlarmInventoryFailureReason.unavailable,
      );
    },
  );

  test(
    'getInventory turns malformed rows into an explicit corrupt failure',
    () async {
      _setHandler(channel, calls, (_) {
        return {
          'schemaVersion': 1,
          'reservations': [
            {
              'reservationId': 'reservation-1',
              'occurrenceId': 'occ-1',
              'wakePlanId': 'plan-1',
              'platformAlarmId': 'platform-occ-1',
              'status': 'not-a-status',
            },
          ],
        };
      });

      final result = await gateway.getInventory();

      expect(result.status, NativeAlarmInventoryResultStatus.failure);
      expect(result.failureReason, NativeAlarmInventoryFailureReason.corrupt);
      expect(result.issues.single.type, NativeAlarmInventoryIssueType.corrupt);
    },
  );

  test(
    'getInventory classifies unknown native errors as read failures',
    () async {
      _setHandler(channel, calls, (_) {
        throw PlatformException(
          code: 'UNKNOWN',
          message: 'Native read failed.',
        );
      });

      final result = await gateway.getInventory();
      final reconciliation = result.reconcile(expected: const []);

      expect(
        result.failureReason,
        NativeAlarmInventoryFailureReason.nativeError,
      );
      expect(reconciliation.isAuthoritative, isFalse);
      expect(
        reconciliation.issues.single.type,
        NativeAlarmInventoryIssueType.readFailure,
      );
    },
  );

  test('requestPermission uses requestPermissionIfNeeded method', () async {
    _setHandler(channel, calls, (call) {
      expect(call.arguments, {'schemaVersion': 1});
      return {
        'schemaVersion': 1,
        'status': 'granted',
        'permissionStatus': 'authorized',
      };
    });

    final result = await gateway.requestPermission();

    expect(calls.single.method, 'requestPermissionIfNeeded');
    expect(result.status, NativeAlarmPermissionRequestStatus.granted);
    expect(result.permissionStatus, NativeAlarmPermissionStatus.authorized);
  });

  test('requestPermission normalizes exceptional response', () async {
    _setHandler(channel, calls, (_) {
      throw PlatformException(code: 'UNAVAILABLE');
    });

    final result = await gateway.requestPermission();

    expect(result.status, NativeAlarmPermissionRequestStatus.unavailable);
    expect(result.permissionStatus, NativeAlarmPermissionStatus.unknown);
  });

  test(
    'scheduleOccurrences sends fixed payload and correlates partial result',
    () async {
      _setHandler(channel, calls, (call) {
        expect(call.method, 'scheduleOccurrences');
        expect(call.arguments, {
          'schemaVersion': 1,
          'occurrences': [
            {
              'occurrenceId': 'occ-1',
              'reservationId': 'occ-1',
              'wakePlanId': 'plan-1',
              'scheduledAt': '2026-07-06T21:00:00.000Z',
              'targetAt': '2026-07-06T22:00:00.000Z',
              'indexInPlan': 0,
              'totalInPlan': 2,
              'soundId': 'default',
              'vibrationEnabled': true,
            },
            {
              'occurrenceId': 'occ-2',
              'reservationId': 'occ-2',
              'wakePlanId': 'plan-1',
              'scheduledAt': '2026-07-06T21:05:00.000Z',
              'targetAt': '2026-07-06T22:00:00.000Z',
              'indexInPlan': 1,
              'totalInPlan': 2,
              'soundId': 'default',
              'vibrationEnabled': false,
            },
          ],
        });
        return {
          'schemaVersion': 1,
          'occurrences': [
            {
              'occurrenceId': 'occ-1',
              'wakePlanId': 'plan-1',
              'status': 'success',
              'platformAlarmId': 'platform-occ-1',
            },
            {
              'occurrenceId': 'occ-2',
              'wakePlanId': 'plan-1',
              'status': 'failure',
              'failureReason': 'osConstraint',
              'failureMessage': 'Quota exceeded.',
            },
          ],
        };
      });

      final result = await gateway.scheduleOccurrences(_requests());

      expect(result.status, ScheduleResultStatus.partialFailure);
      expect(result.occurrences.first.platformAlarmId, 'platform-occ-1');
      final failed = result.occurrences.last;
      expect(failed.failureReason, ScheduleFailureReason.osConstraint);
      expect(failed.failureMessage, 'Quota exceeded.');
    },
  );

  test(
    'scheduleOccurrences maps native method error to each occurrence',
    () async {
      _setHandler(channel, calls, (_) {
        throw PlatformException(
          code: 'PERMISSION_MISSING',
          message: 'Exact alarm permission denied.',
        );
      });

      final result = await gateway.scheduleOccurrences(_requests());

      expect(result.status, ScheduleResultStatus.permissionMissing);
      expect(result.occurrences, hasLength(2));
      expect(result.occurrences.map((occurrence) => occurrence.failureReason), [
        ScheduleFailureReason.permissionMissing,
        ScheduleFailureReason.permissionMissing,
      ]);
      expect(result.occurrences.first.failureMessage, contains('Exact alarm'));
    },
  );

  test('scheduleOccurrences normalizes malformed result per request', () async {
    _setHandler(
      channel,
      calls,
      (_) => {'schemaVersion': 1, 'occurrences': 'bad'},
    );

    final result = await gateway.scheduleOccurrences(_requests());

    expect(result.status, ScheduleResultStatus.failure);
    expect(result.occurrences, hasLength(2));
    expect(
      result.occurrences.map((row) => row.failureReason),
      everyElement(ScheduleFailureReason.nativeError),
    );
  });

  test(
    'scheduleOccurrences rejects duplicate requests before native call',
    () async {
      final duplicateRequests = [_requests().first, _requests().first];
      _setHandler(channel, calls, (_) {
        fail('duplicate schedule batch reached the native channel');
      });

      await expectLater(
        gateway.scheduleOccurrences(duplicateRequests),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'cancelOccurrences sends occurrence to platform id correspondence',
    () async {
      _setHandler(channel, calls, (call) {
        expect(call.method, 'cancelOccurrences');
        expect(call.arguments, {
          'schemaVersion': 1,
          'alarms': [
            {
              'occurrenceId': 'occ-1',
              'reservationId': 'occ-1',
              'platformAlarmId': 'platform-occ-1',
            },
            {
              'occurrenceId': 'occ-2',
              'reservationId': 'occ-2',
              'platformAlarmId': 'platform-occ-2',
            },
          ],
        });
        return {
          'schemaVersion': 1,
          'alarms': [
            {
              'occurrenceId': 'occ-1',
              'platformAlarmId': 'platform-occ-1',
              'status': 'success',
            },
            {
              'occurrenceId': 'occ-2',
              'platformAlarmId': 'platform-occ-2',
              'status': 'failure',
              'failureReason': 'nativeError',
              'failureMessage': 'Already gone.',
            },
          ],
        };
      });

      final result = await gateway.cancelOccurrences(_cancelRequests());

      expect(result.status, CancelResultStatus.partialFailure);
      expect(result.alarms.last.failureReason, CancelFailureReason.nativeError);
      expect(result.alarms.last.failureMessage, 'Already gone.');
    },
  );

  test('cancelPlan requires resolved platform identities in payload', () async {
    _setHandler(channel, calls, (call) {
      expect(call.method, 'cancelPlan');
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments.containsKey('wakePlanId'), isFalse);
      expect(arguments, {
        'schemaVersion': 1,
        'alarms': [
          {
            'occurrenceId': 'occ-1',
            'reservationId': 'occ-1',
            'platformAlarmId': 'platform-occ-1',
          },
          {
            'occurrenceId': 'occ-2',
            'reservationId': 'occ-2',
            'platformAlarmId': 'platform-occ-2',
          },
        ],
      });
      return {
        'schemaVersion': 1,
        'alarms': [
          {
            'occurrenceId': 'occ-1',
            'platformAlarmId': 'platform-occ-1',
            'status': 'success',
          },
          {
            'occurrenceId': 'occ-2',
            'platformAlarmId': 'platform-occ-2',
            'status': 'success',
          },
        ],
      };
    });

    final result = await gateway.cancelPlan(_cancelRequests());

    expect(result.status, CancelResultStatus.success);
  });

  test(
    'cancelOccurrences rejects duplicate requests before native call',
    () async {
      final duplicateRequests = [
        _cancelRequests().first,
        _cancelRequests().first,
      ];
      _setHandler(channel, calls, (_) {
        fail('duplicate cancel batch reached the native channel');
      });

      await expectLater(
        gateway.cancelOccurrences(duplicateRequests),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'cancelPlan maps native method error per requested platform id',
    () async {
      _setHandler(channel, calls, (_) {
        throw PlatformException(
          code: 'MISSING_PLATFORM_ALARM_ID',
          message: 'Stored native id was empty.',
        );
      });

      final result = await gateway.cancelPlan(_cancelRequests());

      expect(result.status, CancelResultStatus.failure);
      expect(result.alarms.map((alarm) => alarm.failureReason), [
        CancelFailureReason.missingPlatformAlarmId,
        CancelFailureReason.missingPlatformAlarmId,
      ]);
      expect(result.alarms.first.platformAlarmId, 'platform-occ-1');
    },
  );

  test('scheduleTestAlarm sends schema version and parses success', () async {
    _setHandler(channel, calls, (call) {
      expect(call.method, 'scheduleTestAlarm');
      expect(call.arguments, {
        'schemaVersion': 1,
        'fireAfterMillis': 60000,
        'soundId': 'quiet',
        'vibrationEnabled': false,
      });
      return {
        'schemaVersion': 1,
        'status': 'success',
        'platformAlarmId': 'test-platform-id',
      };
    });

    final result = await gateway.scheduleTestAlarm(
      NativeTestAlarmScheduleRequest(
        fireAfter: const Duration(minutes: 1),
        soundId: 'quiet',
        vibrationEnabled: false,
      ),
    );

    expect(result.status, ScheduleResultStatus.success);
    expect(result.platformAlarmId, 'test-platform-id');
  });

  test('scheduleTestAlarm maps native error to failed result', () async {
    _setHandler(channel, calls, (_) {
      throw PlatformException(code: 'UNAVAILABLE', message: 'Unsupported.');
    });

    final result = await gateway.scheduleTestAlarm(
      NativeTestAlarmScheduleRequest(fireAfter: const Duration(seconds: 30)),
    );

    expect(result.status, ScheduleResultStatus.failure);
    expect(result.failureReason, ScheduleFailureReason.unavailable);
    expect(result.failureMessage, 'Unsupported.');
  });
}

void _setHandler(
  MethodChannel channel,
  List<MethodCall> calls,
  FutureOr<Object?> Function(MethodCall call) handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return Future<Object?>.value(handler(call));
      });
}

List<NativeAlarmScheduleRequest> _requests() {
  return [
    NativeAlarmScheduleRequest(
      occurrenceId: 'occ-1',
      wakePlanId: 'plan-1',
      scheduledAt: DateTime.utc(2026, 7, 6, 21),
      targetAt: DateTime.utc(2026, 7, 6, 22),
      indexInPlan: 0,
      totalInPlan: 2,
      soundId: 'default',
      vibrationEnabled: true,
    ),
    NativeAlarmScheduleRequest(
      occurrenceId: 'occ-2',
      wakePlanId: 'plan-1',
      scheduledAt: DateTime.utc(2026, 7, 6, 21, 5),
      targetAt: DateTime.utc(2026, 7, 6, 22),
      indexInPlan: 1,
      totalInPlan: 2,
      soundId: 'default',
      vibrationEnabled: false,
    ),
  ];
}

List<NativeAlarmCancelRequest> _cancelRequests() {
  return [
    NativeAlarmCancelRequest(
      occurrenceId: 'occ-1',
      platformAlarmId: 'platform-occ-1',
    ),
    NativeAlarmCancelRequest(
      occurrenceId: 'occ-2',
      platformAlarmId: 'platform-occ-2',
    ),
  ];
}
