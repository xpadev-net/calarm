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
    final scheduleResult = await gateway
        .scheduleOccurrences([scheduleRequest])
        .nativeSmokeTimeout('scheduleOccurrences');
    final scheduleSucceeded = scheduleResult.isSuccess;
    _emitEvidence('scheduleOccurrences', {
      'platform': platform,
      'evidenceLabel': evidenceLabel,
      'status': scheduleResult.status.name,
      'occurrences': scheduleResult.occurrences
          .map(_scheduleOccurrenceEvidence)
          .toList(),
    });
    expect(scheduleResult.occurrences, hasLength(1));

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

    final scheduledPlatformAlarmId =
        scheduleResult.occurrences.single.platformAlarmId;
    var scheduleCancelSucceeded = false;
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
            (row) => row.reservationId == scheduleRequest.reservationId,
          ),
          isEmpty,
          reason:
              'Cancelled native reservations must disappear from inventory.',
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

    final testAlarmResult = await gateway
        .scheduleTestAlarm(
          NativeTestAlarmScheduleRequest(
            fireAfter: const Duration(minutes: 2),
            vibrationEnabled: false,
          ),
        )
        .nativeSmokeTimeout('scheduleTestAlarm');
    final testAlarmSucceeded = testAlarmResult.isSuccess;
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

    final testPlatformAlarmId = testAlarmResult.platformAlarmId;
    var testCancelSucceeded = false;
    if (testPlatformAlarmId != null) {
      final cancelTestResult = await gateway
          .cancelOccurrences([
            NativeAlarmCancelRequest(
              occurrenceId: 'ci-smoke-test-alarm',
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
    }

    final criticalOperationsSucceeded =
        scheduleSucceeded &&
        scheduleCancelSucceeded &&
        testAlarmSucceeded &&
        testCancelSucceeded;
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
