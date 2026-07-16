import 'dart:async';
import 'dart:convert';

import 'package:calarm/core/platform/method_channel_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stable smoke correlation rejects a mismatched wake plan', (
    _,
  ) async {
    final row = NativeAlarmInventoryRow(
      reservationId: 'ci-smoke-reservation',
      occurrenceId: 'ci-smoke-occurrence',
      wakePlanId: 'different-plan',
      platformAlarmId: 'ci-smoke-platform-id',
      status: NativeAlarmReservationStatus.scheduled,
    );

    expect(
      _matchesStableScheduleTuple(
        row,
        reservationId: 'ci-smoke-reservation',
        occurrenceId: 'ci-smoke-occurrence',
        wakePlanId: 'ci-smoke-plan',
        platformAlarmId: 'ci-smoke-platform-id',
      ),
      isFalse,
    );
  });

  testWidgets(
    'stable post-cancel verification rejects a mismatched native row',
    (_) async {
      const channel = MethodChannel(nativeAlarmChannelName);
      var cancelCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getInventory') {
              return {
                'schemaVersion': nativeAlarmChannelSchemaVersion,
                'reservations': [
                  {
                    'reservationId': 'other-reservation',
                    'occurrenceId': 'other-occurrence',
                    'wakePlanId': 'stable-plan',
                    'platformAlarmId': 'stable-platform-id',
                    'status': 'scheduled',
                  },
                ],
              };
            }
            if (call.method == 'cancelOccurrences') {
              cancelCalls++;
              return {
                'schemaVersion': nativeAlarmChannelSchemaVersion,
                'alarms': [
                  {
                    'status': 'success',
                    'occurrenceId': 'other-occurrence',
                    'reservationId': 'other-reservation',
                    'platformAlarmId': 'stable-platform-id',
                  },
                ],
              };
            }
            throw MissingPluginException('Unexpected ${call.method}');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final verified = await _verifyStableScheduleCleanupAfterCancel(
        gateway: MethodChannelNativeAlarmGateway(channel: channel),
        occurrenceId: 'expected-occurrence',
        reservationId: 'expected-reservation',
        platformAlarmId: 'stable-platform-id',
        expectedWakePlanId: 'stable-plan',
        platform: 'test',
        evidenceLabel: 'TEST',
        cleanupLabel: 'stableMismatch',
      );

      expect(verified, isFalse);
      expect(cancelCalls, 0);
    },
  );

  testWidgets(
    'failed schedule ID is not cancelled before full tuple correlation',
    (_) async {
      const channel = MethodChannel(nativeAlarmChannelName);
      var cancelCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getInventory') {
              return {
                'schemaVersion': nativeAlarmChannelSchemaVersion,
                'reservations': [
                  {
                    'reservationId': 'foreign-reservation',
                    'occurrenceId': 'foreign-occurrence',
                    'wakePlanId': 'foreign-plan',
                    'platformAlarmId': 'failed-platform-id',
                    'status': 'scheduled',
                  },
                ],
              };
            }
            if (call.method == 'cancelOccurrences') {
              cancelCalls++;
              throw StateError('Uncorrelated cleanup must not cancel.');
            }
            throw MissingPluginException('Unexpected ${call.method}');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final verified = await _bestEffortCleanupTestAlarm(
        gateway: MethodChannelNativeAlarmGateway(channel: channel),
        occurrenceId: 'failed-occurrence',
        reservationId: 'failed-reservation',
        platformAlarmId: 'failed-platform-id',
        expectedWakePlanId: 'failed-plan',
        allowPlatformIdTupleDiscovery: false,
        platform: 'test',
        evidenceLabel: 'TEST',
        cleanupLabel: 'failedSchedule',
      );

      expect(verified, isFalse);
      expect(cancelCalls, 0);
    },
  );

  testWidgets('native alarm MethodChannel smoke', (_) async {
    final gateway = MethodChannelNativeAlarmGateway();
    const platform = String.fromEnvironment(
      'CALARM_NATIVE_SMOKE_PLATFORM',
      defaultValue: 'unknown',
    );
    const evidenceLabel = String.fromEnvironment(
      'CALARM_NATIVE_SMOKE_EVIDENCE_LABEL',
      defaultValue: 'UNKNOWN',
    );

    final capability = await gateway.getCapability().nativeSmokeTimeout(
      'getCapability',
    );
    _emitEvidence('capability', {
      'platform': platform,
      'evidenceLabel': evidenceLabel,
      'permissionStatus': capability.permissionStatus.name,
      'canScheduleAlarms': capability.canScheduleAlarms,
      'canRequestPermission': capability.canRequestPermission,
      'requiresExactAlarmPermission': capability.requiresExactAlarmPermission,
      'requiresNotificationPermission':
          capability.requiresNotificationPermission,
      'requiresFullScreenIntentPermission':
          capability.requiresFullScreenIntentPermission,
      'supportsTestAlarm': capability.supportsTestAlarm,
      'supportsInventory': capability.supportsInventory,
    });
    if (platform.toLowerCase().contains('ios')) {
      expect(
        capability.supportsInventory,
        isTrue,
        reason:
            'The production iOS MethodChannel must expose authoritative inventory for lost-reply reconciliation.',
      );
    }

    final scheduleRequest = NativeAlarmScheduleRequest(
      occurrenceId: 'ci-smoke-occurrence',
      reservationId: 'ci-smoke-reservation',
      wakePlanId: 'ci-smoke-plan',
      scheduledAt: DateTime.now().toUtc().add(const Duration(hours: 6)),
      targetAt: DateTime.now().toUtc().add(const Duration(hours: 6)),
      indexInPlan: 0,
      totalInPlan: 1,
      soundId: 'default',
      vibrationEnabled: false,
    );
    var scheduleSucceeded = false;
    var scheduleCancelSucceeded = false;
    var scheduleCleanupVerified = false;
    String? scheduledPlatformAlarmId;
    late ScheduleResult scheduleResult;
    try {
      scheduleResult = await gateway
          .scheduleOccurrences([scheduleRequest])
          .nativeSmokeTimeout('scheduleOccurrences');
      scheduleSucceeded = scheduleResult.isSuccess;
      if (scheduleResult.occurrences.length == 1) {
        scheduledPlatformAlarmId =
            scheduleResult.occurrences.single.platformAlarmId;
      }
      _emitEvidence('scheduleOccurrences', {
        'platform': platform,
        'evidenceLabel': evidenceLabel,
        'status': scheduleResult.status.name,
        'occurrences': scheduleResult.occurrences
            .map(_scheduleOccurrenceEvidence)
            .toList(),
      });

      final isAndroidRuntime = defaultTargetPlatform == TargetPlatform.android;
      if (isAndroidRuntime) {
        expect(
          platform.toLowerCase(),
          contains('android'),
          reason: 'Android smoke must declare an Android smoke platform.',
        );
      } else {
        expect(
          platform.toLowerCase(),
          isNot(contains('android')),
          reason: 'Non-Android smoke must not declare Android.',
        );
      }
      if (scheduleSucceeded) {
        final inventory = await gateway.getInventory().nativeSmokeTimeout(
          'getInventory',
        );
        _emitEvidence('getInventory', {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'status': inventory.status.name,
          'reservations': inventory.rows.map(_inventoryEvidence).toList(),
        });
        expect(
          inventory.isSuccess,
          isTrue,
          reason:
              'Successful native scheduling must expose authoritative inventory.',
        );
        final matchingRows = inventory.rows
            .where(
              (row) => _matchesStableScheduleTuple(
                row,
                reservationId: scheduleRequest.reservationId,
                occurrenceId: scheduleRequest.occurrenceId,
                wakePlanId: scheduleRequest.wakePlanId,
                platformAlarmId: scheduledPlatformAlarmId,
              ),
            )
            .toList();
        expect(matchingRows, hasLength(1));
        expect(
          matchingRows.single.status,
          anyOf(
            NativeAlarmReservationStatus.scheduled,
            NativeAlarmReservationStatus.ringing,
          ),
        );
      }

      if (scheduleSucceeded && scheduledPlatformAlarmId != null) {
        final cancelResult = await gateway
            .cancelOccurrences([
              NativeAlarmCancelRequest(
                occurrenceId: scheduleRequest.occurrenceId,
                reservationId: scheduleRequest.reservationId,
                platformAlarmId: scheduledPlatformAlarmId,
              ),
            ])
            .nativeSmokeTimeout('cancelOccurrences');
        _emitEvidence('cancelOccurrences', {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'status': cancelResult.status.name,
          'alarms': cancelResult.alarms.map(_cancelAlarmEvidence).toList(),
        });
        expect(cancelResult.alarms, hasLength(1));
        scheduleCancelSucceeded = cancelResult.isSuccess;
        if (scheduleCancelSucceeded) {
          scheduleCleanupVerified =
              await _verifyStableScheduleCleanupAfterCancel(
                gateway: gateway,
                occurrenceId: scheduleRequest.occurrenceId,
                reservationId: scheduleRequest.reservationId,
                platformAlarmId: scheduledPlatformAlarmId,
                expectedWakePlanId: scheduleRequest.wakePlanId,
                platform: platform,
                evidenceLabel: evidenceLabel,
                cleanupLabel: 'scheduleAfterCancel',
              );
        }
      } else {
        _emitEvidence('cancelOccurrences', {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'status': 'skipped',
          'reason': 'scheduleOccurrences did not return a platformAlarmId',
        });
      }
    } finally {
      if (!scheduleCleanupVerified) {
        scheduleCleanupVerified = await _bestEffortCleanupTestAlarm(
          gateway: gateway,
          occurrenceId: scheduleRequest.occurrenceId,
          reservationId: scheduleRequest.reservationId,
          platformAlarmId: scheduledPlatformAlarmId,
          expectedWakePlanId: scheduleRequest.wakePlanId,
          allowPlatformIdTupleDiscovery: false,
          platform: platform,
          evidenceLabel: evidenceLabel,
          cleanupLabel: 'schedule',
        );
      }
    }
    // A non-throwing lifecycle may continue as BLOCKED only after cleanup
    // authoritatively proves absence. This also covers failure results that
    // returned or revealed a recoverable platform ID.
    if (!scheduleCleanupVerified) {
      throw StateError(
        'Native schedule cleanup could not be authoritatively verified.',
      );
    }

    const testAlarmIdentity = 'ci-smoke-test-alarm';
    late TestAlarmScheduleResult testAlarmResult;
    var testOccurrenceId = testAlarmIdentity;
    var testReservationId = testAlarmIdentity;
    String? reportedTestPlatformAlarmId;
    String? testPlatformAlarmId;
    var testIdentityCorrelated = false;
    var testCorrelationRejected = false;
    var testAlarmSucceeded = false;
    var testCancelSucceeded = false;
    var testCleanupVerified = false;
    var testAlarmScheduleAttempted = false;
    try {
      final testInventoryBeforeSchedule = await gateway
          .getInventory()
          .nativeSmokeTimeout('getInventoryBeforeTestAlarm');
      _emitEvidence('getInventoryBeforeTestAlarm', {
        'platform': platform,
        'evidenceLabel': evidenceLabel,
        'status': testInventoryBeforeSchedule.status.name,
        'reservations': testInventoryBeforeSchedule.rows
            .map(_inventoryEvidence)
            .toList(),
      });
      expect(testInventoryBeforeSchedule.isSuccess, isTrue);
      final baselinePlatformAlarmIds = testInventoryBeforeSchedule.rows
          .map((row) => row.platformAlarmId)
          .toSet();

      testAlarmScheduleAttempted = true;
      testAlarmResult = await gateway
          .scheduleTestAlarm(
            NativeTestAlarmScheduleRequest(
              fireAfter: const Duration(minutes: 2),
              vibrationEnabled: false,
            ),
          )
          .nativeSmokeTimeout('scheduleTestAlarm');
      testAlarmSucceeded = testAlarmResult.isSuccess;
      reportedTestPlatformAlarmId = testAlarmResult.platformAlarmId;
      _emitEvidence('scheduleTestAlarm', {
        'platform': platform,
        'evidenceLabel': evidenceLabel,
        'status': testAlarmResult.status.name,
        'platformAlarmId': reportedTestPlatformAlarmId,
        'failureReason': testAlarmResult.failureReason?.name,
        'failureMessage': testAlarmResult.failureMessage,
      });
      if (testAlarmResult.isSuccess) {
        expect(testAlarmResult.platformAlarmId, isNotNull);
      } else {
        expect(testAlarmResult.failureReason, isNotNull);
      }

      final testInventory = await gateway.getInventory().nativeSmokeTimeout(
        'getInventoryTestAlarm',
      );
      _emitEvidence('getInventoryTestAlarm', {
        'platform': platform,
        'evidenceLabel': evidenceLabel,
        'status': testInventory.status.name,
        'reservations': testInventory.rows.map(_inventoryEvidence).toList(),
      });
      expect(testInventory.isSuccess, isTrue);
      final fallbackTestRows = testInventory.rows
          .where(
            (row) =>
                row.reservationId == testAlarmIdentity &&
                row.occurrenceId == testAlarmIdentity,
          )
          .toList();
      final matchingTestRows = fallbackTestRows
          .where((row) => row.wakePlanId == 'test')
          .toList();
      if (reportedTestPlatformAlarmId != null) {
        final platformRows = testInventory.rows
            .where((row) => row.platformAlarmId == reportedTestPlatformAlarmId)
            .toList();
        final staleFailureId =
            !testAlarmResult.isSuccess &&
            baselinePlatformAlarmIds.contains(reportedTestPlatformAlarmId);
        if (staleFailureId) {
          testCorrelationRejected = true;
          _emitEvidence('testAlarmIdentityFailure', {
            'platform': platform,
            'evidenceLabel': evidenceLabel,
            'reason':
                'A failed schedule returned a platform ID already present before this attempt.',
            'platformAlarmId': reportedTestPlatformAlarmId,
          });
        } else {
          if (platformRows.length != 1) testCorrelationRejected = true;
          expect(
            platformRows,
            hasLength(1),
            reason:
                'A returned test-alarm platform ID must map to exactly one inventory row.',
          );
          final row = platformRows.single;
          if (row.wakePlanId != 'test') testCorrelationRejected = true;
          expect(
            row.wakePlanId,
            'test',
            reason:
                'A returned test-alarm platform ID must retain the test wake plan.',
          );
          testOccurrenceId = row.occurrenceId;
          testReservationId = row.reservationId;
          testPlatformAlarmId = row.platformAlarmId;
          testIdentityCorrelated = true;
        }
      } else if (fallbackTestRows.isNotEmpty) {
        if (fallbackTestRows.length != 1 || matchingTestRows.length != 1) {
          testCorrelationRejected = true;
        }
        expect(
          fallbackTestRows,
          hasLength(1),
          reason:
              'The stable fallback tuple must map to exactly one test-alarm row.',
        );
        expect(matchingTestRows, hasLength(1));
        final row = matchingTestRows.single;
        final staleFailureFallback =
            !testAlarmResult.isSuccess &&
            baselinePlatformAlarmIds.contains(row.platformAlarmId);
        if (staleFailureFallback) {
          testCorrelationRejected = true;
          _emitEvidence('testAlarmIdentityFailure', {
            'platform': platform,
            'evidenceLabel': evidenceLabel,
            'reason':
                'A failed schedule matched a fallback platform ID already present before this attempt.',
            'platformAlarmId': row.platformAlarmId,
          });
        } else {
          testOccurrenceId = row.occurrenceId;
          testReservationId = row.reservationId;
          testPlatformAlarmId = row.platformAlarmId;
          testIdentityCorrelated = true;
        }
      }
      if (testAlarmResult.isSuccess) {
        expect(testIdentityCorrelated, isTrue);
      }

      if (testPlatformAlarmId != null && testIdentityCorrelated) {
        final cancelTestResult = await gateway
            .cancelOccurrences([
              NativeAlarmCancelRequest(
                occurrenceId: testOccurrenceId,
                reservationId: testReservationId,
                platformAlarmId: testPlatformAlarmId,
              ),
            ])
            .nativeSmokeTimeout('cancelTestAlarm');
        _emitEvidence('cancelTestAlarm', {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'status': cancelTestResult.status.name,
          'alarms': cancelTestResult.alarms.map(_cancelAlarmEvidence).toList(),
        });
        expect(cancelTestResult.alarms, hasLength(1));
        testCancelSucceeded = cancelTestResult.isSuccess;
        if (testCancelSucceeded) {
          testCleanupVerified = await _bestEffortCleanupTestAlarm(
            gateway: gateway,
            occurrenceId: testOccurrenceId,
            reservationId: testReservationId,
            platformAlarmId: testPlatformAlarmId,
            expectedWakePlanId: 'test',
            fallbackOccurrenceId: testAlarmIdentity,
            fallbackReservationId: testAlarmIdentity,
            allowTupleFallback: !testCorrelationRejected,
            platformAlarmIdAlreadyCorrelated: true,
            cancelBeforeVerification: false,
            platform: platform,
            evidenceLabel: evidenceLabel,
            cleanupLabel: 'testAlarmAfterCancel',
          );
        }
      } else {
        // The first inventory is only a recovery hint. Always run the
        // bounded final inventory in finally so a late native row cannot be
        // orphaned behind an incorrectly verified cleanup.
        testCleanupVerified = false;
      }
    } catch (error, stackTrace) {
      _emitEvidence('testAlarmLifecycleFailure', {
        'platform': platform,
        'evidenceLabel': evidenceLabel,
        'error': '$error',
      });
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!testCleanupVerified && testAlarmScheduleAttempted) {
        testCleanupVerified = await _bestEffortCleanupTestAlarm(
          gateway: gateway,
          occurrenceId: testOccurrenceId,
          reservationId: testReservationId,
          platformAlarmId: testPlatformAlarmId,
          expectedWakePlanId: 'test',
          fallbackOccurrenceId: testAlarmIdentity,
          fallbackReservationId: testAlarmIdentity,
          allowTupleFallback: !testCorrelationRejected,
          platform: platform,
          evidenceLabel: evidenceLabel,
          cleanupLabel: 'testAlarm',
        );
      } else if (!testAlarmScheduleAttempted) {
        testCleanupVerified = true;
      }
    }
    if (!testCleanupVerified) {
      throw StateError(
        'Native test-alarm cleanup could not be authoritatively verified.',
      );
    }

    final criticalOperationsSucceeded =
        scheduleSucceeded &&
        scheduleCancelSucceeded &&
        scheduleCleanupVerified &&
        testAlarmSucceeded &&
        testCancelSucceeded &&
        testCleanupVerified;
    final outcome = criticalOperationsSucceeded ? 'NEAR_DEVICE' : 'BLOCKED';
    _emitEvidence('nativeSmokeOutcome', {
      'platform': platform,
      'evidenceLabel': evidenceLabel,
      'outcome': outcome,
      'scheduleSucceeded': scheduleSucceeded,
      'scheduleCancelSucceeded': scheduleCancelSucceeded,
      'testAlarmSucceeded': testAlarmSucceeded,
      'testCancelSucceeded': testCancelSucceeded,
      'releaseApproval': false,
    });
    debugPrintSynchronously('CALARM_NATIVE_SMOKE_OUTCOME=$outcome');
  });
}

bool _matchesStableScheduleTuple(
  NativeAlarmInventoryRow row, {
  required String reservationId,
  required String occurrenceId,
  required String wakePlanId,
  required String? platformAlarmId,
}) {
  return row.reservationId == reservationId &&
      row.occurrenceId == occurrenceId &&
      row.wakePlanId == wakePlanId &&
      (platformAlarmId == null || row.platformAlarmId == platformAlarmId);
}

Future<bool> _verifyStableScheduleCleanupAfterCancel({
  required MethodChannelNativeAlarmGateway gateway,
  required String occurrenceId,
  required String reservationId,
  required String? platformAlarmId,
  required String expectedWakePlanId,
  required String platform,
  required String evidenceLabel,
  required String cleanupLabel,
}) {
  return _bestEffortCleanupTestAlarm(
    gateway: gateway,
    occurrenceId: occurrenceId,
    reservationId: reservationId,
    platformAlarmId: platformAlarmId,
    expectedWakePlanId: expectedWakePlanId,
    allowPlatformIdTupleDiscovery: false,
    platformAlarmIdAlreadyCorrelated: true,
    cancelBeforeVerification: false,
    platform: platform,
    evidenceLabel: evidenceLabel,
    cleanupLabel: cleanupLabel,
  );
}

Future<bool> _bestEffortCleanupTestAlarm({
  required MethodChannelNativeAlarmGateway gateway,
  required String occurrenceId,
  required String reservationId,
  required String? platformAlarmId,
  required String expectedWakePlanId,
  String? fallbackOccurrenceId,
  String? fallbackReservationId,
  bool allowTupleFallback = true,
  bool allowPlatformIdTupleDiscovery = true,
  bool platformAlarmIdAlreadyCorrelated = false,
  bool cancelBeforeVerification = true,
  required String platform,
  required String evidenceLabel,
  required String cleanupLabel,
}) async {
  String? recoveredPlatformAlarmId = platformAlarmId;
  var recoveredOccurrenceId = occurrenceId;
  var recoveredReservationId = reservationId;
  var platformCorrelationVerified =
      platformAlarmId == null || platformAlarmIdAlreadyCorrelated;

  bool isExactRow(NativeAlarmInventoryRow row) {
    return allowTupleFallback &&
        (recoveredPlatformAlarmId == null ||
            row.platformAlarmId == recoveredPlatformAlarmId) &&
        row.occurrenceId == recoveredOccurrenceId &&
        row.reservationId == recoveredReservationId &&
        row.wakePlanId == expectedWakePlanId;
  }

  bool isPotentialCandidate(NativeAlarmInventoryRow row) {
    return row.wakePlanId == expectedWakePlanId ||
        (recoveredPlatformAlarmId != null &&
            row.platformAlarmId == recoveredPlatformAlarmId) ||
        (row.occurrenceId == recoveredOccurrenceId &&
            row.reservationId == recoveredReservationId) ||
        (allowTupleFallback &&
            fallbackOccurrenceId != null &&
            fallbackReservationId != null &&
            row.occurrenceId == fallbackOccurrenceId &&
            row.reservationId == fallbackReservationId);
  }

  Future<bool> cancelExact(String id, String phase) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final cancel = await gateway
            .cancelOccurrences([
              NativeAlarmCancelRequest(
                occurrenceId: recoveredOccurrenceId,
                reservationId: recoveredReservationId,
                platformAlarmId: id,
              ),
            ])
            .nativeSmokeTimeout('$phase$attempt');
        _emitEvidence(phase, {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'attempt': attempt,
          'status': cancel.status.name,
          'alarms': cancel.alarms.map(_cancelAlarmEvidence).toList(),
        });
        if (cancel.isSuccess) return true;
      } catch (error) {
        _emitEvidence('${phase}Failure', {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'attempt': attempt,
          'error': '$error',
        });
      }
    }
    return false;
  }

  try {
    final inventory = await gateway.getInventory().nativeSmokeTimeout(
      'cleanup${cleanupLabel}Inventory',
    );
    _emitEvidence('cleanup${cleanupLabel}Inventory', {
      'platform': platform,
      'evidenceLabel': evidenceLabel,
      'status': inventory.status.name,
      'reservations': inventory.rows.map(_inventoryEvidence).toList(),
    });
    if (inventory.isSuccess) {
      if (recoveredPlatformAlarmId != null) {
        final idMatches = inventory.rows
            .where((row) => row.platformAlarmId == recoveredPlatformAlarmId)
            .toList();
        if (idMatches.length > 1) {
          _emitEvidence('cleanup${cleanupLabel}Failure', {
            'platform': platform,
            'evidenceLabel': evidenceLabel,
            'reason': 'multiple rows for returned test-alarm platform ID',
          });
          return false;
        }
        if (idMatches.length == 1) {
          final row = idMatches.single;
          final rowMatchesExpectedTuple = _matchesStableScheduleTuple(
            row,
            reservationId: recoveredReservationId,
            occurrenceId: recoveredOccurrenceId,
            wakePlanId: expectedWakePlanId,
            platformAlarmId: recoveredPlatformAlarmId,
          );
          if (!allowPlatformIdTupleDiscovery && !rowMatchesExpectedTuple) {
            _emitEvidence('cleanup${cleanupLabel}Failure', {
              'platform': platform,
              'evidenceLabel': evidenceLabel,
              'reason':
                  'stable returned platform ID does not match the expected tuple',
            });
            return false;
          }
          if (allowPlatformIdTupleDiscovery &&
              row.wakePlanId != expectedWakePlanId) {
            _emitEvidence('cleanup${cleanupLabel}Failure', {
              'platform': platform,
              'evidenceLabel': evidenceLabel,
              'reason':
                  'returned test-alarm platform ID has mismatched wake plan',
            });
            return false;
          }
          if (allowPlatformIdTupleDiscovery) {
            recoveredOccurrenceId = row.occurrenceId;
            recoveredReservationId = row.reservationId;
          }
          platformCorrelationVerified = true;
        }
      } else if (allowTupleFallback) {
        final tupleCandidateRows = inventory.rows
            .where(
              (row) =>
                  row.reservationId == recoveredReservationId &&
                  row.occurrenceId == recoveredOccurrenceId,
            )
            .toList();
        final tupleMatches = tupleCandidateRows
            .where((row) => row.wakePlanId == expectedWakePlanId)
            .toList();
        if (tupleCandidateRows.length != tupleMatches.length) {
          _emitEvidence('cleanup${cleanupLabel}Failure', {
            'platform': platform,
            'evidenceLabel': evidenceLabel,
            'reason': 'fallback tuple has a mismatched wake plan',
          });
          return false;
        }
        if (tupleMatches.length > 1) {
          _emitEvidence('cleanup${cleanupLabel}Failure', {
            'platform': platform,
            'evidenceLabel': evidenceLabel,
            'reason': 'multiple matching test alarms',
          });
          return false;
        }
        if (tupleMatches.length == 1) {
          recoveredPlatformAlarmId = tupleMatches.single.platformAlarmId;
          platformCorrelationVerified = true;
        }
      }
    }
  } catch (error) {
    _emitEvidence('cleanup${cleanupLabel}InventoryFailure', {
      'platform': platform,
      'evidenceLabel': evidenceLabel,
      'error': '$error',
    });
  }

  if (cancelBeforeVerification &&
      recoveredPlatformAlarmId != null &&
      platformCorrelationVerified) {
    await cancelExact(recoveredPlatformAlarmId, 'cleanup${cleanupLabel}Cancel');
  }

  try {
    final finalInventory = await gateway.getInventory().nativeSmokeTimeout(
      'cleanup${cleanupLabel}FinalInventory',
    );
    _emitEvidence('cleanup${cleanupLabel}FinalInventory', {
      'platform': platform,
      'evidenceLabel': evidenceLabel,
      'status': finalInventory.status.name,
      'reservations': finalInventory.rows.map(_inventoryEvidence).toList(),
    });
    if (!finalInventory.isSuccess) return false;
    if (recoveredPlatformAlarmId != null) {
      final idMatches = finalInventory.rows
          .where((row) => row.platformAlarmId == recoveredPlatformAlarmId)
          .toList();
      if (idMatches.length > 1) {
        _emitEvidence('cleanup${cleanupLabel}Failure', {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'reason': 'multiple rows for returned test-alarm platform ID',
        });
        return false;
      }
      if (idMatches.length == 1 && !platformCorrelationVerified) {
        final row = idMatches.single;
        final rowMatchesExpectedTuple = _matchesStableScheduleTuple(
          row,
          reservationId: recoveredReservationId,
          occurrenceId: recoveredOccurrenceId,
          wakePlanId: expectedWakePlanId,
          platformAlarmId: recoveredPlatformAlarmId,
        );
        if (!allowPlatformIdTupleDiscovery && !rowMatchesExpectedTuple) {
          _emitEvidence('cleanup${cleanupLabel}Failure', {
            'platform': platform,
            'evidenceLabel': evidenceLabel,
            'reason':
                'stable returned platform ID does not match the expected tuple',
          });
          return false;
        }
        if (allowPlatformIdTupleDiscovery &&
            row.wakePlanId != expectedWakePlanId) {
          _emitEvidence('cleanup${cleanupLabel}Failure', {
            'platform': platform,
            'evidenceLabel': evidenceLabel,
            'reason':
                'returned test-alarm platform ID has mismatched wake plan',
          });
          return false;
        }
        if (allowPlatformIdTupleDiscovery) {
          recoveredOccurrenceId = row.occurrenceId;
          recoveredReservationId = row.reservationId;
        }
        platformCorrelationVerified = true;
      }
      if (idMatches.isEmpty && !platformCorrelationVerified) return false;
    } else if (allowTupleFallback) {
      final tupleCandidateRows = finalInventory.rows
          .where(
            (row) =>
                row.reservationId == recoveredReservationId &&
                row.occurrenceId == recoveredOccurrenceId,
          )
          .toList();
      final tupleMatches = tupleCandidateRows
          .where((row) => row.wakePlanId == expectedWakePlanId)
          .toList();
      if (tupleMatches.length > 1) {
        _emitEvidence('cleanup${cleanupLabel}Failure', {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'reason': 'multiple matching test alarms in final inventory',
        });
        return false;
      }
      if (tupleMatches.length == 1) {
        recoveredPlatformAlarmId = tupleMatches.single.platformAlarmId;
        platformCorrelationVerified = true;
      }
    }
    final matching = finalInventory.rows.where(isExactRow).toList();
    final ambiguousRows = finalInventory.rows.any(
      (row) => isPotentialCandidate(row) && !isExactRow(row),
    );
    if (matching.isEmpty && !ambiguousRows) return true;
    if (matching.length > 1 || ambiguousRows) {
      _emitEvidence('cleanup${cleanupLabel}Failure', {
        'platform': platform,
        'evidenceLabel': evidenceLabel,
        'reason': 'ambiguous or mismatched test-alarm inventory rows',
      });
      return false;
    }

    // A row may appear between the first cancellation and final inventory.
    // Cancel only the exact full-tuple match, then verify once more.
    if (!await cancelExact(
      matching.single.platformAlarmId,
      'cleanup${cleanupLabel}LateCancel',
    )) {
      return false;
    }
    try {
      final finalFinalInventory = await gateway
          .getInventory()
          .nativeSmokeTimeout('cleanup${cleanupLabel}FinalFinalInventory');
      _emitEvidence('cleanup${cleanupLabel}FinalFinalInventory', {
        'platform': platform,
        'evidenceLabel': evidenceLabel,
        'status': finalFinalInventory.status.name,
        'reservations': finalFinalInventory.rows
            .map(_inventoryEvidence)
            .toList(),
      });
      if (!finalFinalInventory.isSuccess) return false;
      final finalFinalMatching = finalFinalInventory.rows
          .where(isExactRow)
          .toList();
      final finalFinalAmbiguous = finalFinalInventory.rows.any(
        (row) => isPotentialCandidate(row) && !isExactRow(row),
      );
      return finalFinalMatching.isEmpty && !finalFinalAmbiguous;
    } catch (error) {
      _emitEvidence('cleanup${cleanupLabel}FinalFinalInventoryFailure', {
        'platform': platform,
        'evidenceLabel': evidenceLabel,
        'error': '$error',
      });
      return false;
    }
  } catch (error) {
    _emitEvidence('cleanup${cleanupLabel}FinalInventoryFailure', {
      'platform': platform,
      'evidenceLabel': evidenceLabel,
      'error': '$error',
    });
    return false;
  }
}

extension NativeSmokeTimeout<T> on Future<T> {
  Future<T> nativeSmokeTimeout(String operation) {
    return timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        '$operation did not complete within the native smoke timeout.',
      ),
    );
  }
}

void _emitEvidence(String operation, Map<String, Object?> payload) {
  debugPrintSynchronously(
    jsonEncode({
      'operation': operation,
      'runtimeEvidence': 'SIMULATOR_OR_EMULATOR_ONLY',
      ...payload,
    }),
  );
}

Map<String, Object?> _scheduleOccurrenceEvidence(
  ScheduleOccurrenceResult result,
) {
  return {
    'occurrenceId': result.occurrenceId,
    'reservationId': result.reservationId,
    'wakePlanId': result.wakePlanId,
    'status': result.status.name,
    'platformAlarmId': result.platformAlarmId,
    'failureReason': result.failureReason?.name,
    'failureMessage': result.failureMessage,
  };
}

Map<String, Object?> _cancelAlarmEvidence(CancelAlarmResult result) {
  return {
    'occurrenceId': result.occurrenceId,
    'reservationId': result.reservationId,
    'platformAlarmId': result.platformAlarmId,
    'status': result.status.name,
    'failureReason': result.failureReason?.name,
    'failureMessage': result.failureMessage,
  };
}

Map<String, Object?> _inventoryEvidence(NativeAlarmInventoryRow row) {
  return {
    'reservationId': row.reservationId,
    'occurrenceId': row.occurrenceId,
    'wakePlanId': row.wakePlanId,
    'platformAlarmId': row.platformAlarmId,
    'status': row.status.name,
  };
}
