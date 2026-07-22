import 'dart:async';

import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
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
            'reservationGeneration': 3,
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
    expect(result.rows.single.reservationGeneration, 3);
    expect(result.rows.single.status, NativeAlarmReservationStatus.ringing);
  });

  test(
    'getInventory defaults omitted generation and rejects negative values',
    () async {
      int? generation;
      _setHandler(channel, calls, (_) {
        return {
          'schemaVersion': 1,
          'reservations': [
            {
              'reservationId': 'reservation-1',
              'reservationGeneration': ?generation,
              'occurrenceId': 'occ-1',
              'wakePlanId': 'plan-1',
              'platformAlarmId': 'platform-occ-1',
              'status': 'scheduled',
            },
          ],
        };
      });

      final legacy = await gateway.getInventory();
      expect(legacy.isSuccess, isTrue);
      expect(legacy.rows.single.reservationGeneration, 0);

      generation = -1;
      final malformed = await gateway.getInventory();
      expect(malformed.isSuccess, isFalse);
      expect(
        malformed.failureReason,
        NativeAlarmInventoryFailureReason.corrupt,
      );
    },
  );

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

  test('fetchAlarmEvents decodes schema one rows non-destructively', () async {
    _setHandler(channel, calls, (call) {
      expect(call.method, 'fetchAlarmEvents');
      expect(call.arguments, {'schemaVersion': 1});
      return {
        'schemaVersion': 1,
        'events': [
          {
            'eventId': 'platform-1:delivered',
            'platformAlarmId': 'platform-1',
            'type': 'delivered',
            'timestampMillis': 1000,
          },
          {
            'eventId': 'platform-1:dismissed',
            'platformAlarmId': 'platform-1',
            'type': 'dismissed',
            'timestampMillis': 2000,
          },
        ],
      };
    });

    final events = await gateway.fetchAlarmEvents();

    expect(events, hasLength(2));
    expect(events.first.eventId, 'platform-1:delivered');
    expect(events.first.platformAlarmId, 'platform-1');
    expect(events.first.type, NativeAlarmEventType.delivered);
    expect(
      events.first.timestamp,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    expect(events.last.type, NativeAlarmEventType.dismissed);
  });

  test(
    'fetchAlarmEvents treats old plugins and platform failures as empty',
    () async {
      for (final error in <Object>[
        MissingPluginException('not implemented'),
        PlatformException(code: 'CORRUPT'),
      ]) {
        _setHandler(channel, calls, (_) => throw error);
        expect(await gateway.fetchAlarmEvents(), isEmpty);
      }
    },
  );

  test(
    'fetchAlarmEvents rejects malformed or duplicate batches safely',
    () async {
      final malformedResponses = <Object?>[
        null,
        {'schemaVersion': 2, 'events': <Object?>[]},
        {
          'schemaVersion': 1,
          'events': [
            {'eventId': 'missing-fields'},
          ],
        },
        {
          'schemaVersion': 1,
          'events': [
            {
              'eventId': '   ',
              'platformAlarmId': 'platform-1',
              'type': 'delivered',
              'timestampMillis': 1,
            },
          ],
        },
        {
          'schemaVersion': 1,
          'events': [
            {
              'eventId': 'unknown-type',
              'platformAlarmId': 'platform-1',
              'type': 'unknown',
              'timestampMillis': 1,
            },
          ],
        },
        {
          'schemaVersion': 1,
          'events': [
            {
              'eventId': 'negative-time',
              'platformAlarmId': 'platform-1',
              'type': 'delivered',
              'timestampMillis': -1,
            },
          ],
        },
        {
          'schemaVersion': 1,
          'events': [
            {
              'eventId': 'duplicate',
              'platformAlarmId': 'platform-1',
              'type': 'delivered',
              'timestampMillis': 1,
            },
            {
              'eventId': 'duplicate',
              'platformAlarmId': 'platform-2',
              'type': 'dismissed',
              'timestampMillis': 2,
            },
          ],
        },
      ];

      for (final response in malformedResponses) {
        _setHandler(channel, calls, (_) => response);
        expect(await gateway.fetchAlarmEvents(), isEmpty);
      }
    },
  );

  test('acknowledgeAlarmEvents sends only exact validated ids', () async {
    _setHandler(channel, calls, (call) {
      expect(call.method, 'acknowledgeAlarmEvents');
      expect(call.arguments, {
        'schemaVersion': 1,
        'eventIds': ['a', 'b'],
      });
      return {'schemaVersion': 1, 'status': 'success'};
    });

    await gateway.acknowledgeAlarmEvents(['a', 'b']);

    expect(calls.single.method, 'acknowledgeAlarmEvents');
  });

  test(
    'acknowledgeAlarmEvents validates input before channel mutation',
    () async {
      _setHandler(channel, calls, (_) {
        fail('invalid acknowledgement reached the platform');
      });

      await expectLater(
        gateway.acknowledgeAlarmEvents(['']),
        throwsArgumentError,
      );
      await expectLater(
        gateway.acknowledgeAlarmEvents(['duplicate', 'duplicate']),
        throwsArgumentError,
      );
      await gateway.acknowledgeAlarmEvents(const []);

      expect(calls, isEmpty);
    },
  );

  test(
    'acknowledgeAlarmEvents safely tolerates old plugins and malformed replies',
    () async {
      final failures = <FutureOr<Object?> Function()>[
        () => throw MissingPluginException('not implemented'),
        () => throw PlatformException(code: 'FAILED'),
        () => {'schemaVersion': 2, 'status': 'success'},
        () => {'schemaVersion': 1, 'status': 'failure'},
      ];

      for (final failure in failures) {
        _setHandler(channel, calls, (_) => failure());
        await gateway.acknowledgeAlarmEvents(['still-durable']);
      }
    },
  );

  test('fake event journal replays until exact acknowledgement', () async {
    final fake = FakeNativeAlarmGateway();
    fake.pendingAlarmEvents.addAll([
      NativeAlarmEvent(
        eventId: 'a',
        platformAlarmId: 'platform-a',
        type: NativeAlarmEventType.delivered,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
      ),
      NativeAlarmEvent(
        eventId: 'b',
        platformAlarmId: 'platform-b',
        type: NativeAlarmEventType.dismissed,
        timestamp: DateTime.fromMillisecondsSinceEpoch(2, isUtc: true),
      ),
    ]);

    expect(await fake.fetchAlarmEvents(), hasLength(2));
    expect(await fake.fetchAlarmEvents(), hasLength(2));
    await fake.acknowledgeAlarmEvents(['a', 'unknown']);

    expect(fake.acknowledgedAlarmEventIds, ['a', 'unknown']);
    expect((await fake.fetchAlarmEvents()).map((event) => event.eventId), [
      'b',
    ]);
  });

  test(
    'fake event journal mirrors native dedupe ordering cap and validation',
    () async {
      final fake = FakeNativeAlarmGateway();
      for (var index = 0; index < 205; index++) {
        fake.pendingAlarmEvents.add(
          NativeAlarmEvent(
            eventId: 'event-$index',
            platformAlarmId: 'platform-$index',
            type: NativeAlarmEventType.delivered,
            timestamp: DateTime.fromMillisecondsSinceEpoch(index, isUtc: true),
          ),
        );
      }
      fake.pendingAlarmEvents.add(
        NativeAlarmEvent(
          eventId: 'event-204',
          platformAlarmId: 'platform-204',
          type: NativeAlarmEventType.delivered,
          timestamp: DateTime.fromMillisecondsSinceEpoch(999, isUtc: true),
        ),
      );

      final events = await fake.fetchAlarmEvents();

      expect(events, hasLength(200));
      expect(events.first.eventId, 'event-5');
      expect(events.last.eventId, 'event-204');
      expect(events.last.timestamp.millisecondsSinceEpoch, 999);
      await fake.acknowledgeAlarmEvents(
        events.map((event) => event.eventId).toList(),
      );
      expect(await fake.fetchAlarmEvents(), isEmpty);

      fake.pendingAlarmEvents.add(
        NativeAlarmEvent(
          eventId: ' ',
          platformAlarmId: 'invalid',
          type: NativeAlarmEventType.delivered,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        ),
      );
      expect(await fake.fetchAlarmEvents(), isEmpty);
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
              'reservationGeneration': 0,
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
              'reservationGeneration': 0,
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

  test(
    'scheduleOccurrences parses and enforces reservation generation',
    () async {
      final base = _requests().first;
      final request = NativeAlarmScheduleRequest(
        occurrenceId: base.occurrenceId,
        reservationId: 'stable-slot',
        reservationGeneration: 5,
        wakePlanId: base.wakePlanId,
        scheduledAt: base.scheduledAt,
        targetAt: base.targetAt,
        indexInPlan: 0,
        totalInPlan: 1,
        soundId: base.soundId,
        vibrationEnabled: base.vibrationEnabled,
      );
      var responseGeneration = 5;
      _setHandler(channel, calls, (call) {
        final payload = call.arguments as Map<Object?, Object?>;
        final occurrence =
            (payload['occurrences'] as List<Object?>).single
                as Map<Object?, Object?>;
        expect(occurrence['reservationGeneration'], 5);
        return {
          'schemaVersion': 1,
          'occurrences': [
            {
              'occurrenceId': request.occurrenceId,
              'reservationId': request.reservationId,
              'reservationGeneration': responseGeneration,
              'wakePlanId': request.wakePlanId,
              'status': 'success',
              'platformAlarmId': 'native-5',
            },
          ],
        };
      });

      final exact = await gateway.scheduleOccurrences([request]);
      expect(exact.isSuccess, isTrue);
      expect(exact.occurrences.single.reservationGeneration, 5);

      responseGeneration = 4;
      final mismatched = await gateway.scheduleOccurrences([request]);
      expect(mismatched.isSuccess, isFalse);
      expect(
        mismatched.occurrences.single.failureReason,
        ScheduleFailureReason.nativeError,
      );
      expect(mismatched.occurrences.single.reservationGeneration, 5);
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
              'reservationGeneration': 0,
              'platformAlarmId': 'platform-occ-1',
            },
            {
              'occurrenceId': 'occ-2',
              'reservationId': 'occ-2',
              'reservationGeneration': 0,
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
            'reservationGeneration': 0,
            'platformAlarmId': 'platform-occ-1',
          },
          {
            'occurrenceId': 'occ-2',
            'reservationId': 'occ-2',
            'reservationGeneration': 0,
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
    'cancelOccurrences parses and enforces reservation generation',
    () async {
      final request = NativeAlarmCancelRequest(
        occurrenceId: 'occ-1',
        reservationId: 'stable-slot',
        reservationGeneration: 8,
        platformAlarmId: 'native-8',
      );
      var responseGeneration = 8;
      _setHandler(channel, calls, (call) {
        final payload = call.arguments as Map<Object?, Object?>;
        final alarm =
            (payload['alarms'] as List<Object?>).single
                as Map<Object?, Object?>;
        expect(alarm['reservationGeneration'], 8);
        return {
          'schemaVersion': 1,
          'alarms': [
            {
              'occurrenceId': request.occurrenceId,
              'reservationId': request.reservationId,
              'reservationGeneration': responseGeneration,
              'platformAlarmId': request.platformAlarmId,
              'status': 'success',
            },
          ],
        };
      });

      final exact = await gateway.cancelOccurrences([request]);
      expect(exact.isSuccess, isTrue);
      expect(exact.alarms.single.reservationGeneration, 8);

      responseGeneration = 7;
      final mismatched = await gateway.cancelOccurrences([request]);
      expect(mismatched.isSuccess, isFalse);
      expect(
        mismatched.alarms.single.failureReason,
        CancelFailureReason.nativeError,
      );
      expect(mismatched.alarms.single.reservationGeneration, 8);
    },
  );

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
    expect(result.platformAlarmId, isNull);
  });

  test(
    'scheduleTestAlarm preserves recoverable id on native failure',
    () async {
      _setHandler(channel, calls, (_) {
        return {
          'schemaVersion': 1,
          'status': 'failure',
          'failureReason': 'nativeError',
          'failureMessage': 'The native outcome is unknown.',
          'platformAlarmId': 'recoverable-test-id',
        };
      });

      final result = await gateway.scheduleTestAlarm(
        NativeTestAlarmScheduleRequest(fireAfter: const Duration(seconds: 30)),
      );

      expect(result.status, ScheduleResultStatus.failure);
      expect(result.failureReason, ScheduleFailureReason.nativeError);
      expect(result.failureMessage, 'The native outcome is unknown.');
      expect(result.platformAlarmId, 'recoverable-test-id');
    },
  );

  test('scheduleTestAlarm accepts failure without a recoverable id', () async {
    _setHandler(channel, calls, (_) {
      return {
        'schemaVersion': 1,
        'status': 'failure',
        'failureReason': 'nativeError',
      };
    });

    final result = await gateway.scheduleTestAlarm(
      NativeTestAlarmScheduleRequest(fireAfter: const Duration(seconds: 30)),
    );

    expect(result.status, ScheduleResultStatus.failure);
    expect(result.failureReason, ScheduleFailureReason.nativeError);
    expect(result.platformAlarmId, isNull);
  });

  test('scheduleTestAlarm drops an empty or malformed failure id', () async {
    for (final value in ['', 42]) {
      _setHandler(channel, calls, (_) {
        return {
          'schemaVersion': 1,
          'status': 'failure',
          'failureReason': 'nativeError',
          'platformAlarmId': value,
        };
      });

      final result = await gateway.scheduleTestAlarm(
        NativeTestAlarmScheduleRequest(fireAfter: const Duration(seconds: 30)),
      );
      expect(result.status, ScheduleResultStatus.failure);
      expect(result.failureReason, ScheduleFailureReason.nativeError);
      expect(result.platformAlarmId, isNull);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
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
