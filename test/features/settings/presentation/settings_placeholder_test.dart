import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/features/settings/application/alarm_health_controller.dart';
import 'package:calarm/features/settings/application/wake_plan_defaults_controller.dart';
import 'package:calarm/features/settings/presentation/settings_placeholder.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WakePlanDatabase database;
  late WakePlanRepository repository;
  late FakeNativeAlarmGateway gateway;

  setUp(() {
    database = WakePlanDatabase(NativeDatabase.memory());
    repository = WakePlanRepository(database);
    gateway = FakeNativeAlarmGateway();
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('renders and persists settings default controls', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          settingsNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPlaceholder())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wake window'), findsOneWidget);
    expect(find.text('1 h'), findsOneWidget);
    expect(find.text('Interval'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('OS default'), findsOneWidget);
    expect(find.text('No repeat'), findsOneWidget);
    expect(find.text('Alarm readiness'), findsOneWidget);
    expect(find.text('Alarms are ready to schedule.'), findsOneWidget);

    await tester.tap(find.text('Weekday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vibration'));
    await tester.pumpAndSettle();

    final saved = await repository.fetchEffectiveAppSettings();

    expect(saved.defaultRepeatType, RepeatType.weekly);
    expect(saved.defaultVibrationEnabled, isFalse);
  });

  testWidgets('shows a message when saving settings fails', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          settingsNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPlaceholder())),
      ),
    );
    await tester.pumpAndSettle();
    await database.close();

    await tester.tap(find.text('Weekday'));
    await tester.pumpAndSettle();

    expect(find.text('Could not save settings.'), findsOneWidget);

    database = WakePlanDatabase(NativeDatabase.memory());
  });

  testWidgets('shows health warnings and schedules a one minute test alarm', (
    tester,
  ) async {
    gateway.capability = const NativeAlarmCapability(
      permissionStatus: NativeAlarmPermissionStatus.denied,
      canScheduleAlarms: false,
      canRequestPermission: true,
      requiresExactAlarmPermission: true,
      requiresNotificationPermission: true,
      requiresFullScreenIntentPermission: true,
      requiresNotificationChannelSetup: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          settingsNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPlaceholder())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Alarm permission is denied.'), findsOneWidget);
    expect(
      find.textContaining('Android exact alarm permission is required.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Android notification permission is required.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Android full-screen alarm permission is required.'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Android wake alarm notification channel is disabled.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Schedule 1-minute test alarm'));
    await tester.pumpAndSettle();

    expect(gateway.scheduledTestAlarms.single.fireAfter, Duration(minutes: 1));
    expect(
      find.text('Test alarm could not be scheduled: permission is missing.'),
      findsOneWidget,
    );
  });

  testWidgets('preserves inline schedule failure reason', (tester) async {
    gateway.testAlarmFailureReason = ScheduleFailureReason.osConstraint;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          settingsNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPlaceholder())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Schedule 1-minute test alarm'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Test alarm could not be scheduled: the operating system blocked it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('disables test alarm action when unsupported', (tester) async {
    gateway.capability = const NativeAlarmCapability(
      permissionStatus: NativeAlarmPermissionStatus.authorized,
      canScheduleAlarms: true,
      canRequestPermission: false,
      supportsTestAlarm: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          settingsNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPlaceholder())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('This device does not support test alarms.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Schedule 1-minute test alarm'),
    );

    expect(button.onPressed, isNull);
    expect(gateway.scheduledTestAlarms, isEmpty);
  });
}
