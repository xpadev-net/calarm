import 'dart:async';
import 'dart:convert';

import 'package:calarm/core/platform/method_channel_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native alarm MethodChannel smoke', (_) async {
    final gateway = MethodChannelNativeAlarmGateway();
    const platform = String.fromEnvironment(
      'CALARM_NATIVE_SMOKE_PLATFORM',
      defaultValue: 'unknown',
    );
    const evidenceLabel = String.fromEnvironment(
      'CALARM_NATIVE_SMOKE_EVIDENCE_LABEL',
      defaultValue: 'NEAR_DEVICE',
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
    });

    final scheduleRequest = NativeAlarmScheduleRequest(
      occurrenceId: 'ci-smoke-occurrence',
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
    _emitEvidence('scheduleOccurrences', {
      'platform': platform,
      'evidenceLabel': evidenceLabel,
      'status': scheduleResult.status.name,
      'occurrences': scheduleResult.occurrences
          .map(_scheduleOccurrenceEvidence)
          .toList(),
    });
    expect(scheduleResult.occurrences, hasLength(1));

    final scheduledPlatformAlarmId =
        scheduleResult.occurrences.single.platformAlarmId;
    if (scheduledPlatformAlarmId != null) {
      final cancelResult = await gateway
          .cancelOccurrences([
            NativeAlarmCancelRequest(
              occurrenceId: scheduleRequest.occurrenceId,
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
    _emitEvidence('scheduleTestAlarm', {
      'platform': platform,
      'evidenceLabel': evidenceLabel,
      'status': testAlarmResult.status.name,
      'platformAlarmId': testAlarmResult.platformAlarmId,
      'failureReason': testAlarmResult.failureReason?.name,
      'failureMessage': testAlarmResult.failureMessage,
    });

    final testPlatformAlarmId = testAlarmResult.platformAlarmId;
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
    }
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
  debugPrint(
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
    'platformAlarmId': result.platformAlarmId,
    'status': result.status.name,
    'failureReason': result.failureReason?.name,
    'failureMessage': result.failureMessage,
  };
}
