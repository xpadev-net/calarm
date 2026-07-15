import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/app_bootstrap.dart';
import '../../../core/platform/native_alarm_gateway.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';

final settingsNativeAlarmGatewayProvider = Provider<NativeAlarmGateway>((ref) {
  return ref.watch(appNativeAlarmGatewayProvider);
});

final alarmHealthProvider =
    AsyncNotifierProvider<AlarmHealthController, AlarmHealthState>(
      AlarmHealthController.new,
    );

class AlarmHealthController extends AsyncNotifier<AlarmHealthState> {
  static const testAlarmDelay = Duration(minutes: 1);
  var _capabilityRevision = 0;
  var _capabilityAuthorityGeneration = 0;
  var _permissionOperationGeneration = 0;
  var _testAlarmOperationGeneration = 0;

  @override
  Future<AlarmHealthState> build() async {
    final authorityGeneration = ++_capabilityAuthorityGeneration;
    try {
      final capability = await ref
          .watch(settingsNativeAlarmGatewayProvider)
          .getCapability();
      if (authorityGeneration != _capabilityAuthorityGeneration) {
        return state.value ?? _unknownCapabilityState;
      }
      return AlarmHealthState(
        capability: capability,
        capabilityRevision: ++_capabilityRevision,
      );
    } on Object catch (error) {
      debugPrint('Alarm capability check failed: $error');
      if (authorityGeneration != _capabilityAuthorityGeneration) {
        return state.value ?? _unknownCapabilityState;
      }
      return _unknownCapabilityState;
    }
  }

  Future<void> refresh() async {
    final authorityGeneration = ++_capabilityAuthorityGeneration;
    final previous = state.value;
    if (previous == null) {
      state = const AsyncLoading();
    } else {
      state = AsyncData(previous.copyWith(isRefreshing: true));
    }

    try {
      final capability = await ref
          .read(settingsNativeAlarmGatewayProvider)
          .getCapability();
      if (authorityGeneration != _capabilityAuthorityGeneration) {
        return;
      }
      final current = state.value ?? previous ?? _unknownCapabilityState;
      state = AsyncData(
        current.copyWith(
          capability: capability,
          isRefreshing: false,
          capabilityCheckFailed: false,
          capabilityRevision: ++_capabilityRevision,
        ),
      );
    } on Object catch (error) {
      debugPrint('Alarm capability refresh failed: $error');
      if (authorityGeneration != _capabilityAuthorityGeneration) {
        return;
      }
      final current = state.value ?? previous ?? _unknownCapabilityState;
      state = AsyncData(
        current.copyWith(isRefreshing: false, capabilityCheckFailed: true),
      );
    }
  }

  Future<void> requestPermission() async {
    final operationGeneration = ++_permissionOperationGeneration;
    final authorityGeneration = ++_capabilityAuthorityGeneration;
    final gateway = ref.read(settingsNativeAlarmGatewayProvider);
    final previous = state.value;
    if (previous != null) {
      state = AsyncData(
        previous.copyWith(isRefreshing: false, isRequestingPermission: true),
      );
    }

    final NativeAlarmPermissionResult permissionResult;
    try {
      permissionResult = await gateway.requestPermission();
    } on Object catch (error) {
      if (operationGeneration != _permissionOperationGeneration) {
        return;
      }
      debugPrint('Alarm permission request failed: $error');
      final current = state.value ?? previous;
      if (current != null) {
        state = AsyncData(
          current.copyWith(
            isRequestingPermission: false,
            capabilityCheckFailed:
                authorityGeneration == _capabilityAuthorityGeneration
                ? true
                : null,
          ),
        );
      }
      return;
    }
    if (operationGeneration != _permissionOperationGeneration) {
      return;
    }

    final current = state.value ?? previous;
    final capability =
        current?.capability ??
        const NativeAlarmCapability(
          permissionStatus: NativeAlarmPermissionStatus.unknown,
          canScheduleAlarms: false,
          canRequestPermission: true,
        );
    state = AsyncData(
      (current ??
              AlarmHealthState(
                capability: capability,
                lastPermissionResult: permissionResult,
              ))
          .copyWith(
            capability: capability,
            lastPermissionResult: permissionResult,
            isRequestingPermission: false,
            capabilityCheckFailed:
                authorityGeneration == _capabilityAuthorityGeneration &&
                    permissionResult.status ==
                        NativeAlarmPermissionRequestStatus.unavailable
                ? true
                : null,
          ),
    );
  }

  Future<void> scheduleTestAlarm(AppSettings settings) async {
    final previous = state.value;
    if (previous == null) {
      return;
    }
    final operationGeneration = ++_testAlarmOperationGeneration;
    final authorityGeneration = ++_capabilityAuthorityGeneration;

    state = AsyncData(
      previous.copyWith(isRefreshing: false, isSchedulingTestAlarm: true),
    );
    final TestAlarmScheduleResult result;
    try {
      result = await ref
          .read(settingsNativeAlarmGatewayProvider)
          .scheduleTestAlarm(
            NativeTestAlarmScheduleRequest(
              fireAfter: testAlarmDelay,
              soundId: settings.defaultSoundId,
              vibrationEnabled: settings.defaultVibrationEnabled,
            ),
          );
    } catch (error) {
      if (operationGeneration != _testAlarmOperationGeneration) {
        return;
      }
      final failure = TestAlarmScheduleResult.failure(
        reason: ScheduleFailureReason.nativeError,
        message: error.toString(),
      );
      final current = state.value ?? previous;
      state = AsyncData(
        current.copyWith(
          isSchedulingTestAlarm: false,
          lastTestAlarmResult: failure,
        ),
      );
      return;
    }

    NativeAlarmCapability? capability;
    Object? capabilityError;
    if (authorityGeneration == _capabilityAuthorityGeneration) {
      try {
        capability = await ref
            .read(settingsNativeAlarmGatewayProvider)
            .getCapability();
      } on Object catch (error) {
        debugPrint('Alarm capability refresh after test alarm failed: $error');
        capabilityError = error;
      }
    }
    if (operationGeneration != _testAlarmOperationGeneration) {
      return;
    }

    final current = state.value ?? previous;
    final canApplyCapability =
        authorityGeneration == _capabilityAuthorityGeneration;
    if (canApplyCapability && capability != null) {
      _capabilityRevision += 1;
    }
    state = AsyncData(
      current.copyWith(
        capability: canApplyCapability ? capability : null,
        isSchedulingTestAlarm: false,
        lastTestAlarmResult: result,
        capabilityCheckFailed: canApplyCapability
            ? capabilityError != null
            : null,
        capabilityRevision: canApplyCapability && capability != null
            ? _capabilityRevision
            : null,
      ),
    );
  }
}

const _unknownCapabilityState = AlarmHealthState(
  capability: NativeAlarmCapability(
    permissionStatus: NativeAlarmPermissionStatus.unknown,
    canScheduleAlarms: false,
    canRequestPermission: true,
  ),
  capabilityCheckFailed: true,
  capabilityRevision: 0,
);

class AlarmHealthState {
  const AlarmHealthState({
    required this.capability,
    this.lastPermissionResult,
    this.lastTestAlarmResult,
    this.isSchedulingTestAlarm = false,
    this.isRefreshing = false,
    this.isRequestingPermission = false,
    this.capabilityCheckFailed = false,
    this.capabilityRevision = 0,
  });

  final NativeAlarmCapability capability;
  final NativeAlarmPermissionResult? lastPermissionResult;
  final TestAlarmScheduleResult? lastTestAlarmResult;
  final bool isSchedulingTestAlarm;
  final bool isRefreshing;
  final bool isRequestingPermission;
  final bool capabilityCheckFailed;
  final int capabilityRevision;

  AlarmReadinessStatus get readinessStatus {
    if (isRefreshing) {
      return AlarmReadinessStatus.checking;
    }
    if (capabilityCheckFailed) {
      return AlarmReadinessStatus.checkFailed;
    }
    if (capability.isReady) {
      return AlarmReadinessStatus.ready;
    }
    return AlarmReadinessStatus.actionRequired;
  }

  bool get hasWarnings => warnings.isNotEmpty || hasFailedTestAlarm;

  bool get hasFailedTestAlarm => lastTestAlarmResult?.isSuccess == false;

  bool get isBusy =>
      isSchedulingTestAlarm || isRefreshing || isRequestingPermission;

  List<AlarmHealthWarning> get warnings {
    if (capabilityCheckFailed) {
      return const <AlarmHealthWarning>[];
    }
    final warnings = <AlarmHealthWarning>[];
    switch (capability.permissionStatus) {
      case NativeAlarmPermissionStatus.authorized:
        break;
      case NativeAlarmPermissionStatus.notDetermined:
        warnings.add(
          const AlarmHealthWarning(
            kind: AlarmHealthWarningKind.permission,
            message: 'Alarm permission has not been granted yet.',
          ),
        );
      case NativeAlarmPermissionStatus.denied:
        warnings.add(
          const AlarmHealthWarning(
            kind: AlarmHealthWarningKind.permission,
            message: 'Alarm permission is denied.',
          ),
        );
      case NativeAlarmPermissionStatus.restricted:
        warnings.add(
          const AlarmHealthWarning(
            kind: AlarmHealthWarningKind.permission,
            message: 'Alarm permission is restricted by the operating system.',
          ),
        );
      case NativeAlarmPermissionStatus.unavailable:
        warnings.add(
          const AlarmHealthWarning(
            kind: AlarmHealthWarningKind.permission,
            message: 'Native alarm scheduling is unavailable on this device.',
          ),
        );
      case NativeAlarmPermissionStatus.unknown:
        warnings.add(
          const AlarmHealthWarning(
            kind: AlarmHealthWarningKind.permission,
            message: 'Alarm permission state could not be confirmed.',
          ),
        );
    }

    if (capability.requiresExactAlarmPermission) {
      warnings.add(
        const AlarmHealthWarning(
          kind: AlarmHealthWarningKind.exactAlarm,
          message: 'Android exact alarm permission is required.',
        ),
      );
    }
    if (capability.requiresNotificationPermission) {
      warnings.add(
        const AlarmHealthWarning(
          kind: AlarmHealthWarningKind.notification,
          message: 'Android notification permission is required.',
        ),
      );
    }
    if (capability.requiresFullScreenIntentPermission) {
      warnings.add(
        const AlarmHealthWarning(
          kind: AlarmHealthWarningKind.fullScreenIntent,
          message: 'Android full-screen alarm permission is required.',
        ),
      );
    }
    if (capability.requiresNotificationChannelSetup) {
      warnings.add(
        const AlarmHealthWarning(
          kind: AlarmHealthWarningKind.notificationChannel,
          message: 'Android wake alarm notification channel is disabled.',
        ),
      );
    }
    if (!capability.supportsTestAlarm) {
      warnings.add(
        const AlarmHealthWarning(
          kind: AlarmHealthWarningKind.testAlarm,
          message: 'This device does not support test alarms.',
        ),
      );
    }
    if (!capability.canScheduleAlarms && warnings.isEmpty) {
      warnings.add(
        const AlarmHealthWarning(
          kind: AlarmHealthWarningKind.scheduling,
          message: 'Native alarms cannot be scheduled right now.',
        ),
      );
    }
    return warnings;
  }

  String? get testAlarmMessage {
    final result = lastTestAlarmResult;
    if (result == null) {
      return null;
    }
    if (result.isSuccess) {
      return 'Test alarm scheduled for 1 minute from now.';
    }
    final detail = result.failureMessage;
    final reason = _scheduleFailureReasonText(result.failureReason);
    if (detail == null) {
      return 'Test alarm could not be scheduled: $reason.';
    }
    return 'Test alarm could not be scheduled: $reason. $detail';
  }

  AlarmHealthState copyWith({
    NativeAlarmCapability? capability,
    NativeAlarmPermissionResult? lastPermissionResult,
    TestAlarmScheduleResult? lastTestAlarmResult,
    bool? isSchedulingTestAlarm,
    bool? isRefreshing,
    bool? isRequestingPermission,
    bool? capabilityCheckFailed,
    int? capabilityRevision,
  }) {
    return AlarmHealthState(
      capability: capability ?? this.capability,
      lastPermissionResult: lastPermissionResult ?? this.lastPermissionResult,
      lastTestAlarmResult: lastTestAlarmResult ?? this.lastTestAlarmResult,
      isSchedulingTestAlarm:
          isSchedulingTestAlarm ?? this.isSchedulingTestAlarm,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isRequestingPermission:
          isRequestingPermission ?? this.isRequestingPermission,
      capabilityCheckFailed:
          capabilityCheckFailed ?? this.capabilityCheckFailed,
      capabilityRevision: capabilityRevision ?? this.capabilityRevision,
    );
  }
}

enum AlarmReadinessStatus { checking, actionRequired, checkFailed, ready }

class AlarmHealthWarning {
  const AlarmHealthWarning({required this.kind, required this.message});

  final AlarmHealthWarningKind kind;
  final String message;
}

enum AlarmHealthWarningKind {
  permission,
  exactAlarm,
  notification,
  fullScreenIntent,
  notificationChannel,
  testAlarm,
  scheduling,
}

String _scheduleFailureReasonText(ScheduleFailureReason? reason) {
  return switch (reason) {
    ScheduleFailureReason.permissionMissing => 'permission is missing',
    ScheduleFailureReason.osConstraint => 'the operating system blocked it',
    ScheduleFailureReason.invalidRequest => 'the request was invalid',
    ScheduleFailureReason.nativeError => 'the native scheduler failed',
    ScheduleFailureReason.unavailable => 'test alarms are unavailable',
    ScheduleFailureReason.unknown || null => 'unknown reason',
  };
}
