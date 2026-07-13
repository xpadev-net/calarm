import 'dart:async';
import 'dart:convert';

import 'package:calarm/core/platform/method_channel_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
              (row) =>
                  row.reservationId == scheduleRequest.reservationId &&
                  row.occurrenceId == scheduleRequest.occurrenceId,
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

      if (scheduledPlatformAlarmId != null) {
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
          final inventoryAfterCancel = await gateway
              .getInventory()
              .nativeSmokeTimeout('getInventoryAfterCancel');
          _emitEvidence('getInventoryAfterCancel', {
            'platform': platform,
            'evidenceLabel': evidenceLabel,
            'status': inventoryAfterCancel.status.name,
            'reservations': inventoryAfterCancel.rows
                .map(_inventoryEvidence)
                .toList(),
          });
          expect(inventoryAfterCancel.isSuccess, isTrue);
          expect(
            inventoryAfterCancel.rows.where(
              (row) =>
                  row.reservationId == scheduleRequest.reservationId &&
                  row.occurrenceId == scheduleRequest.occurrenceId,
            ),
            isEmpty,
            reason:
                'Cancelled native reservations must disappear from inventory.',
          );
          scheduleCleanupVerified = true;
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
          platform: platform,
          evidenceLabel: evidenceLabel,
          cleanupLabel: 'schedule',
        );
      }
    }

    const testAlarmIdentity = 'ci-smoke-test-alarm';
    late TestAlarmScheduleResult testAlarmResult;
    String? testPlatformAlarmId;
    var testAlarmSucceeded = false;
    var testCancelSucceeded = false;
    var testCleanupVerified = false;
    try {
      testAlarmResult = await gateway
          .scheduleTestAlarm(
            NativeTestAlarmScheduleRequest(
              fireAfter: const Duration(minutes: 2),
              vibrationEnabled: false,
            ),
          )
          .nativeSmokeTimeout('scheduleTestAlarm');
      testAlarmSucceeded = testAlarmResult.isSuccess;
      testPlatformAlarmId = testAlarmResult.platformAlarmId;
      _emitEvidence('scheduleTestAlarm', {
        'platform': platform,
        'evidenceLabel': evidenceLabel,
        'status': testAlarmResult.status.name,
        'platformAlarmId': testAlarmResult.platformAlarmId,
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
      final matchingTestRows = testInventory.rows
          .where(
            (row) =>
                row.reservationId == testAlarmIdentity &&
                row.occurrenceId == testAlarmIdentity,
          )
          .toList();
      if (matchingTestRows.isNotEmpty) {
        expect(matchingTestRows, hasLength(1));
        testPlatformAlarmId ??= matchingTestRows.single.platformAlarmId;
      }
      if (testAlarmResult.isSuccess) {
        expect(matchingTestRows, hasLength(1));
        expect(matchingTestRows.single.platformAlarmId, testPlatformAlarmId);
      }

      if (testPlatformAlarmId != null) {
        final cancelTestResult = await gateway
            .cancelOccurrences([
              NativeAlarmCancelRequest(
                occurrenceId: testAlarmIdentity,
                reservationId: testAlarmIdentity,
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
          final testInventoryAfterCancel = await gateway
              .getInventory()
              .nativeSmokeTimeout('getInventoryTestAlarmAfterCancel');
          _emitEvidence('getInventoryTestAlarmAfterCancel', {
            'platform': platform,
            'evidenceLabel': evidenceLabel,
            'status': testInventoryAfterCancel.status.name,
            'reservations': testInventoryAfterCancel.rows
                .map(_inventoryEvidence)
                .toList(),
          });
          expect(testInventoryAfterCancel.isSuccess, isTrue);
          expect(
            testInventoryAfterCancel.rows.where(
              (row) => row.reservationId == testAlarmIdentity,
            ),
            isEmpty,
          );
          testCleanupVerified = true;
        }
      } else {
        testCleanupVerified = matchingTestRows.isEmpty;
      }
    } catch (error, stackTrace) {
      _emitEvidence('testAlarmLifecycleFailure', {
        'platform': platform,
        'evidenceLabel': evidenceLabel,
        'error': '$error',
      });
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!testCleanupVerified) {
        testCleanupVerified = await _bestEffortCleanupTestAlarm(
          gateway: gateway,
          occurrenceId: testAlarmIdentity,
          reservationId: testAlarmIdentity,
          platformAlarmId: testPlatformAlarmId,
          platform: platform,
          evidenceLabel: evidenceLabel,
          cleanupLabel: 'testAlarm',
        );
      }
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

Future<bool> _bestEffortCleanupTestAlarm({
  required MethodChannelNativeAlarmGateway gateway,
  required String occurrenceId,
  required String reservationId,
  required String? platformAlarmId,
  required String platform,
  required String evidenceLabel,
  required String cleanupLabel,
}) async {
  String? recoveredPlatformAlarmId = platformAlarmId;
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
      final matching = inventory.rows
          .where(
            (row) =>
                row.reservationId == reservationId &&
                row.occurrenceId == occurrenceId,
          )
          .toList();
      if (matching.length > 1) {
        _emitEvidence('cleanup${cleanupLabel}Failure', {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'reason': 'multiple matching test alarms',
        });
        return false;
      }
      recoveredPlatformAlarmId ??= matching.isEmpty
          ? null
          : matching.single.platformAlarmId;
    }
  } catch (error) {
    _emitEvidence('cleanup${cleanupLabel}InventoryFailure', {
      'platform': platform,
      'evidenceLabel': evidenceLabel,
      'error': '$error',
    });
  }

  if (recoveredPlatformAlarmId != null) {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final cancel = await gateway
            .cancelOccurrences([
              NativeAlarmCancelRequest(
                occurrenceId: occurrenceId,
                reservationId: reservationId,
                platformAlarmId: recoveredPlatformAlarmId,
              ),
            ])
            .nativeSmokeTimeout('cleanup${cleanupLabel}Cancel$attempt');
        _emitEvidence('cleanup${cleanupLabel}Cancel', {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'attempt': attempt,
          'status': cancel.status.name,
          'alarms': cancel.alarms.map(_cancelAlarmEvidence).toList(),
        });
        if (cancel.isSuccess) break;
      } catch (error) {
        _emitEvidence('cleanup${cleanupLabel}CancelFailure', {
          'platform': platform,
          'evidenceLabel': evidenceLabel,
          'attempt': attempt,
          'error': '$error',
        });
      }
    }
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
    return finalInventory.isSuccess &&
        finalInventory.rows.every(
          (row) =>
              !(row.reservationId == reservationId &&
                  row.occurrenceId == occurrenceId),
        );
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
