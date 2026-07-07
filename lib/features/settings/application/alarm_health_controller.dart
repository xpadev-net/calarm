import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/method_channel_native_alarm_gateway.dart';
import '../../../core/platform/native_alarm_gateway.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';

final settingsNativeAlarmGatewayProvider = Provider<NativeAlarmGateway>((ref) {
  return MethodChannelNativeAlarmGateway();
});

final alarmHealthProvider =
    AsyncNotifierProvider<AlarmHealthController, AlarmHealthState>(
      AlarmHealthController.new,
    );

class AlarmHealthController extends AsyncNotifier<AlarmHealthState> {
  static const testAlarmDelay = Duration(minutes: 1);

  @override
  Future<AlarmHealthState> build() async {
    try {
      return AlarmHealthState(
        capability: await ref
            .watch(settingsNativeAlarmGatewayProvider)
            .getCapability(),
      );
    } on Object catch (error) {
      debugPrint('Alarm capability check failed: $error');
      return const AlarmHealthState(
        capability: NativeAlarmCapability(
          permissionStatus: NativeAlarmPermissionStatus.unknown,
          canScheduleAlarms: false,
          canRequestPermission: true,
        ),
        capabilityCheckFailed: true,
      );
    }
  }

  Future<void> refresh() async {
    final previous = state.value;
    if (previous == null) {
      state = const AsyncLoading();
      state = await AsyncValue.guard(build);
      return;
    }

    state = AsyncData(previous.copyWith(isRefreshing: true));
    try {
      final capability = await ref
          .read(settingsNativeAlarmGatewayProvider)
          .getCapability();
      final current = state.value ?? previous;
      state = AsyncData(
        current.copyWith(
          capability: capability,
          isRefreshing: false,
          capabilityCheckFailed: false,
        ),
      );
    } on Object catch (error) {
      debugPrint('Alarm capability refresh failed: $error');
      final current = state.value ?? previous;
      state = AsyncData(
        current.copyWith(isRefreshing: false, capabilityCheckFailed: true),
      );
      rethrow;
    }
  }

  Future<void> requestPermission() async {
    final gateway = ref.read(settingsNativeAlarmGatewayProvider);
    final previous = state.value;
    if (previous != null) {
      state = AsyncData(previous.copyWith(isRequestingPermission: true));
    }

    final NativeAlarmPermissionResult permissionResult;
    try {
      permissionResult = await gateway.requestPermission();
    } on Object {
      final current = state.value ?? previous;
      if (current != null) {
        state = AsyncData(current.copyWith(isRequestingPermission: false));
      }
      rethrow;
    }

    var capabilityCheckFailed = previous?.capabilityCheckFailed ?? false;
    var capability =
        previous?.capability ??
        const NativeAlarmCapability(
          permissionStatus: NativeAlarmPermissionStatus.unknown,
          canScheduleAlarms: false,
          canRequestPermission: true,
        );
    try {
      capability = await gateway.getCapability();
      capabilityCheckFailed = false;
    } on Object catch (error) {
      debugPrint('Alarm capability refresh after permission failed: $error');
      capabilityCheckFailed = true;
      // The permission request result is authoritative for the user action.
      // A follow-up refresh failure must not claim settings failed to open.
    }

    final current = state.value ?? previous;
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
            capabilityCheckFailed: capabilityCheckFailed,
          ),
    );
  }

  Future<void> scheduleTestAlarm(AppSettings settings) async {
    final previous = state.value;
    if (previous == null) {
      return;
    }

    state = AsyncData(previous.copyWith(isSchedulingTestAlarm: true));
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

    var capability = previous.capability;
    var capabilityCheckFailed = previous.capabilityCheckFailed;
    try {
      capability = await ref
          .read(settingsNativeAlarmGatewayProvider)
          .getCapability();
      capabilityCheckFailed = false;
    } on Object catch (error) {
      debugPrint('Alarm capability refresh after test alarm failed: $error');
      capabilityCheckFailed = true;
      // Keep the scheduling result authoritative. A post-schedule refresh failure
      // must not claim that an already-created native alarm failed to schedule.
    }

    final current = state.value ?? previous;
    state = AsyncData(
      current.copyWith(
        capability: capability,
        isSchedulingTestAlarm: false,
        lastTestAlarmResult: result,
        capabilityCheckFailed: capabilityCheckFailed,
      ),
    );
  }
}

class AlarmHealthState {
  const AlarmHealthState({
    required this.capability,
    this.lastPermissionResult,
    this.lastTestAlarmResult,
    this.isSchedulingTestAlarm = false,
    this.isRefreshing = false,
    this.isRequestingPermission = false,
    this.capabilityCheckFailed = false,
  });

  final NativeAlarmCapability capability;
  final NativeAlarmPermissionResult? lastPermissionResult;
  final TestAlarmScheduleResult? lastTestAlarmResult;
  final bool isSchedulingTestAlarm;
  final bool isRefreshing;
  final bool isRequestingPermission;
  final bool capabilityCheckFailed;

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
    );
  }
}

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
