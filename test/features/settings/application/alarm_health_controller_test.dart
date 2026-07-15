import 'dart:async';

import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/features/settings/application/alarm_health_controller.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeNativeAlarmGateway gateway;
  late ProviderContainer container;

  setUp(() {
    gateway = FakeNativeAlarmGateway();
    container = ProviderContainer(
      overrides: [
        settingsNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('detects permission and Android OS setting warnings', () async {
    gateway.capability = const NativeAlarmCapability(
      permissionStatus: NativeAlarmPermissionStatus.denied,
      canScheduleAlarms: false,
      canRequestPermission: true,
      requiresExactAlarmPermission: true,
      requiresNotificationPermission: true,
      requiresFullScreenIntentPermission: true,
      requiresNotificationChannelSetup: true,
    );

    final state = await container.read(alarmHealthProvider.future);

    expect(
      state.warnings.map((warning) => warning.kind),
      containsAll([
        AlarmHealthWarningKind.permission,
        AlarmHealthWarningKind.exactAlarm,
        AlarmHealthWarningKind.notification,
        AlarmHealthWarningKind.fullScreenIntent,
        AlarmHealthWarningKind.notificationChannel,
      ]),
    );
    expect(state.hasWarnings, isTrue);
    expect(state.readinessStatus, AlarmReadinessStatus.actionRequired);
  });

  test(
    'successful fresh capability checks advance readiness revision',
    () async {
      final initial = await container.read(alarmHealthProvider.future);

      await container.read(alarmHealthProvider.notifier).refresh();
      final refreshed = container.read(alarmHealthProvider).value!;

      expect(initial.readinessStatus, AlarmReadinessStatus.ready);
      expect(initial.capabilityRevision, 1);
      expect(refreshed.capabilityRevision, 2);
    },
  );

  test('schedules a one minute test alarm with defaults', () async {
    await container.read(alarmHealthProvider.future);

    await container
        .read(alarmHealthProvider.notifier)
        .scheduleTestAlarm(AppSettings.initial());

    expect(gateway.scheduledTestAlarms, hasLength(1));
    expect(
      gateway.scheduledTestAlarms.single.fireAfter,
      AlarmHealthController.testAlarmDelay,
    );
    expect(
      container.read(alarmHealthProvider).value!.testAlarmMessage,
      'Test alarm scheduled for 1 minute from now.',
    );
  });

  test('preserves test alarm failure reason in state', () async {
    gateway.testAlarmFailureReason = ScheduleFailureReason.osConstraint;
    await container.read(alarmHealthProvider.future);

    await container
        .read(alarmHealthProvider.notifier)
        .scheduleTestAlarm(AppSettings.initial());

    final state = container.read(alarmHealthProvider).value!;

    expect(state.hasFailedTestAlarm, isTrue);
    expect(
      state.lastTestAlarmResult!.failureReason,
      ScheduleFailureReason.osConstraint,
    );
    expect(
      state.testAlarmMessage,
      'Test alarm could not be scheduled: the operating system blocked it.',
    );
  });

  test('preserves test alarm success when capability refresh fails', () async {
    final flakyGateway = _CapabilityRefreshFailureGateway();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        settingsNativeAlarmGatewayProvider.overrideWith((ref) => flakyGateway),
      ],
    );
    final initial = await container.read(alarmHealthProvider.future);

    flakyGateway.failCapabilityRefresh = true;
    await container
        .read(alarmHealthProvider.notifier)
        .scheduleTestAlarm(AppSettings.initial());

    final state = container.read(alarmHealthProvider).value!;

    expect(flakyGateway.scheduledTestAlarms, hasLength(1));
    expect(state.lastTestAlarmResult!.isSuccess, isTrue);
    expect(
      state.testAlarmMessage,
      'Test alarm scheduled for 1 minute from now.',
    );
    expect(state.capability, same(initial.capability));
    expect(state.capabilityCheckFailed, isTrue);
    expect(state.isSchedulingTestAlarm, isFalse);
  });

  test(
    'refresh preserves test alarm success while updating capability',
    () async {
      final controlledGateway = _ControlledCapabilityGateway();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          settingsNativeAlarmGatewayProvider.overrideWith(
            (ref) => controlledGateway,
          ),
        ],
      );

      await container.read(alarmHealthProvider.future);
      await container
          .read(alarmHealthProvider.notifier)
          .scheduleTestAlarm(AppSettings.initial());

      final capabilityRefresh = Completer<NativeAlarmCapability>();
      controlledGateway.nextCapability = capabilityRefresh.future;
      final refresh = container.read(alarmHealthProvider.notifier).refresh();
      await pumpEventQueue();

      var state = container.read(alarmHealthProvider).value!;
      expect(state.isRefreshing, isTrue);
      expect(state.lastTestAlarmResult!.isSuccess, isTrue);

      capabilityRefresh.complete(
        const NativeAlarmCapability(
          permissionStatus: NativeAlarmPermissionStatus.denied,
          canScheduleAlarms: false,
          canRequestPermission: true,
        ),
      );
      await refresh;

      state = container.read(alarmHealthProvider).value!;
      expect(state.isRefreshing, isFalse);
      expect(state.lastTestAlarmResult!.isSuccess, isTrue);
      expect(state.warnings.single.kind, AlarmHealthWarningKind.permission);
    },
  );

  test('surfaces capability check failure as explicit state', () async {
    final flakyGateway = _CapabilityRefreshFailureGateway()
      ..failCapabilityRefresh = true;
    container.dispose();
    container = ProviderContainer(
      overrides: [
        settingsNativeAlarmGatewayProvider.overrideWith((ref) => flakyGateway),
      ],
    );

    final state = await container.read(alarmHealthProvider.future);

    expect(state.capabilityCheckFailed, isTrue);
    expect(state.warnings, isEmpty);
    expect(state.readinessStatus, AlarmReadinessStatus.checkFailed);
  });

  test('refresh failure updates state without throwing', () async {
    final flakyGateway = _CapabilityRefreshFailureGateway();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        settingsNativeAlarmGatewayProvider.overrideWith((ref) => flakyGateway),
      ],
    );
    final initial = await container.read(alarmHealthProvider.future);

    flakyGateway.failCapabilityRefresh = true;
    await container.read(alarmHealthProvider.notifier).refresh();

    final state = container.read(alarmHealthProvider).value!;
    expect(state.capability, same(initial.capability));
    expect(state.capabilityCheckFailed, isTrue);
    expect(state.isRefreshing, isFalse);
  });

  test('newer missing refresh wins when older ready completes last', () async {
    final controlledGateway = _QueuedCapabilityGateway();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        settingsNativeAlarmGatewayProvider.overrideWith(
          (ref) => controlledGateway,
        ),
      ],
    );
    final initial = await container.read(alarmHealthProvider.future);
    final olderReady = Completer<NativeAlarmCapability>();
    final newerMissing = Completer<NativeAlarmCapability>();
    controlledGateway.pendingCapabilities.addAll([
      olderReady.future,
      newerMissing.future,
    ]);

    final olderRefresh = container.read(alarmHealthProvider.notifier).refresh();
    await pumpEventQueue();
    final newerRefresh = container.read(alarmHealthProvider.notifier).refresh();
    await pumpEventQueue();
    expect(container.read(alarmHealthProvider).value!.isRefreshing, isTrue);

    newerMissing.complete(_missingExactAlarmCapability);
    await newerRefresh;
    olderReady.complete(_readyCapability);
    await olderRefresh;

    final state = container.read(alarmHealthProvider).value!;
    expect(state.capability, same(_missingExactAlarmCapability));
    expect(state.readinessStatus, AlarmReadinessStatus.actionRequired);
    expect(state.isRefreshing, isFalse);
    expect(state.capabilityRevision, initial.capabilityRevision + 1);
  });

  test('newer refresh failure wins when older ready completes last', () async {
    final controlledGateway = _QueuedCapabilityGateway();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        settingsNativeAlarmGatewayProvider.overrideWith(
          (ref) => controlledGateway,
        ),
      ],
    );
    final initial = await container.read(alarmHealthProvider.future);
    final olderReady = Completer<NativeAlarmCapability>();
    final newerFailure = Completer<NativeAlarmCapability>();
    controlledGateway.pendingCapabilities.addAll([
      olderReady.future,
      newerFailure.future,
    ]);

    final olderRefresh = container.read(alarmHealthProvider.notifier).refresh();
    await pumpEventQueue();
    final newerRefresh = container.read(alarmHealthProvider.notifier).refresh();
    await pumpEventQueue();
    newerFailure.completeError(StateError('newer capability failed'));
    await newerRefresh;
    olderReady.complete(_readyCapability);
    await olderRefresh;

    final state = container.read(alarmHealthProvider).value!;
    expect(state.capability, same(initial.capability));
    expect(state.readinessStatus, AlarmReadinessStatus.checkFailed);
    expect(state.isRefreshing, isFalse);
    expect(state.capabilityRevision, initial.capabilityRevision);
  });

  test('permission request invalidates an older capability response', () async {
    final controlledGateway = _QueuedCapabilityGateway(
      capability: _missingExactAlarmCapability,
      permissionResult: const NativeAlarmPermissionResult(
        status: NativeAlarmPermissionRequestStatus.denied,
        permissionStatus: NativeAlarmPermissionStatus.denied,
      ),
    );
    container.dispose();
    container = ProviderContainer(
      overrides: [
        settingsNativeAlarmGatewayProvider.overrideWith(
          (ref) => controlledGateway,
        ),
      ],
    );
    await container.read(alarmHealthProvider.future);
    final olderReady = Completer<NativeAlarmCapability>();
    controlledGateway.pendingCapabilities.add(olderReady.future);

    final refresh = container.read(alarmHealthProvider.notifier).refresh();
    await pumpEventQueue();
    await container.read(alarmHealthProvider.notifier).requestPermission();
    olderReady.complete(_readyCapability);
    await refresh;

    final state = container.read(alarmHealthProvider).value!;
    expect(state.capability, same(_missingExactAlarmCapability));
    expect(state.readinessStatus, AlarmReadinessStatus.actionRequired);
    expect(state.isRefreshing, isFalse);
    expect(state.isRequestingPermission, isFalse);
    expect(
      state.lastPermissionResult?.status,
      NativeAlarmPermissionRequestStatus.denied,
    );
  });

  test(
    'newer refresh wins over test alarm post-schedule capability check',
    () async {
      final controlledGateway = _QueuedCapabilityGateway();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          settingsNativeAlarmGatewayProvider.overrideWith(
            (ref) => controlledGateway,
          ),
        ],
      );
      await container.read(alarmHealthProvider.future);
      final olderReady = Completer<NativeAlarmCapability>();
      final newerMissing = Completer<NativeAlarmCapability>();
      controlledGateway.pendingCapabilities.addAll([
        olderReady.future,
        newerMissing.future,
      ]);

      final schedule = container
          .read(alarmHealthProvider.notifier)
          .scheduleTestAlarm(AppSettings.initial());
      await pumpEventQueue();
      final refresh = container.read(alarmHealthProvider.notifier).refresh();
      await pumpEventQueue();
      newerMissing.complete(_missingExactAlarmCapability);
      await refresh;
      olderReady.complete(_readyCapability);
      await schedule;

      final state = container.read(alarmHealthProvider).value!;
      expect(state.capability, same(_missingExactAlarmCapability));
      expect(state.readinessStatus, AlarmReadinessStatus.actionRequired);
      expect(state.lastTestAlarmResult?.isSuccess, isTrue);
      expect(state.isSchedulingTestAlarm, isFalse);
      expect(state.isRefreshing, isFalse);
    },
  );

  test('permission result waits for a fresh capability refresh', () async {
    gateway.capability = const NativeAlarmCapability(
      permissionStatus: NativeAlarmPermissionStatus.notDetermined,
      canScheduleAlarms: false,
      canRequestPermission: true,
    );
    gateway.permissionResult = const NativeAlarmPermissionResult(
      status: NativeAlarmPermissionRequestStatus.granted,
      permissionStatus: NativeAlarmPermissionStatus.authorized,
    );

    await container.read(alarmHealthProvider.future);
    gateway.capability = const NativeAlarmCapability(
      permissionStatus: NativeAlarmPermissionStatus.authorized,
      canScheduleAlarms: true,
      canRequestPermission: false,
    );

    await container.read(alarmHealthProvider.notifier).requestPermission();

    var state = container.read(alarmHealthProvider).value!;
    expect(state.lastPermissionResult!.isGranted, isTrue);
    expect(state.readinessStatus, AlarmReadinessStatus.actionRequired);

    await container.read(alarmHealthProvider.notifier).refresh();
    state = container.read(alarmHealthProvider).value!;
    expect(state.warnings, isEmpty);
    expect(state.readinessStatus, AlarmReadinessStatus.ready);
  });

  test('does not perform an immediate stale capability refresh', () async {
    final flakyGateway = _CapabilityRefreshFailureGateway()
      ..capability = const NativeAlarmCapability(
        permissionStatus: NativeAlarmPermissionStatus.notDetermined,
        canScheduleAlarms: false,
        canRequestPermission: true,
      )
      ..permissionResult = const NativeAlarmPermissionResult(
        status: NativeAlarmPermissionRequestStatus.granted,
        permissionStatus: NativeAlarmPermissionStatus.authorized,
      );
    container.dispose();
    container = ProviderContainer(
      overrides: [
        settingsNativeAlarmGatewayProvider.overrideWith((ref) => flakyGateway),
      ],
    );
    final initial = await container.read(alarmHealthProvider.future);

    flakyGateway.failCapabilityRefresh = true;
    await container.read(alarmHealthProvider.notifier).requestPermission();

    final state = container.read(alarmHealthProvider).value!;

    expect(state.lastPermissionResult!.isGranted, isTrue);
    expect(state.capability, same(initial.capability));
    expect(state.capabilityCheckFailed, isFalse);
    expect(state.isRequestingPermission, isFalse);

    await container.read(alarmHealthProvider.notifier).refresh();
    expect(
      container.read(alarmHealthProvider).value!.capabilityCheckFailed,
      isTrue,
    );
  });
}

class _CapabilityRefreshFailureGateway extends FakeNativeAlarmGateway {
  bool failCapabilityRefresh = false;

  @override
  Future<NativeAlarmCapability> getCapability() async {
    if (failCapabilityRefresh) {
      throw StateError('Capability refresh failed.');
    }
    return super.getCapability();
  }
}

class _ControlledCapabilityGateway extends FakeNativeAlarmGateway {
  Future<NativeAlarmCapability>? nextCapability;

  @override
  Future<NativeAlarmCapability> getCapability() {
    final pending = nextCapability;
    if (pending != null) {
      nextCapability = null;
      return pending;
    }
    return super.getCapability();
  }
}

const _readyCapability = NativeAlarmCapability(
  permissionStatus: NativeAlarmPermissionStatus.authorized,
  canScheduleAlarms: true,
  canRequestPermission: false,
);

const _missingExactAlarmCapability = NativeAlarmCapability(
  permissionStatus: NativeAlarmPermissionStatus.denied,
  canScheduleAlarms: false,
  canRequestPermission: true,
  requiresExactAlarmPermission: true,
);

class _QueuedCapabilityGateway extends FakeNativeAlarmGateway {
  _QueuedCapabilityGateway({super.capability, super.permissionResult});

  final pendingCapabilities = <Future<NativeAlarmCapability>>[];

  @override
  Future<NativeAlarmCapability> getCapability() {
    if (pendingCapabilities.isNotEmpty) {
      return pendingCapabilities.removeAt(0);
    }
    return super.getCapability();
  }
}
