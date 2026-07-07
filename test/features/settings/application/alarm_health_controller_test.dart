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
  });

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

  test('requests permission and refreshes capability', () async {
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

    final state = container.read(alarmHealthProvider).value!;
    expect(state.lastPermissionResult!.isGranted, isTrue);
    expect(state.warnings, isEmpty);
  });
}
