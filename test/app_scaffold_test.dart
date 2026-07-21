import 'dart:async';
import 'dart:ui' show Rect, Size;

import 'package:calarm/app.dart';
import 'package:calarm/core/bootstrap/app_bootstrap.dart';
import 'package:calarm/core/identity/app_identity.dart';
import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/settings/application/alarm_health_controller.dart';
import 'package:calarm/features/settings/presentation/alarm_permission_gate.dart';
import 'package:calarm/features/week_calendar/presentation/week_calendar_placeholder.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter/material.dart' show FilledButton, Scaffold;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, SizedBox;
import 'package:drift/native.dart';

void main() {
  testWidgets('renders loaded scaffold feature boundaries', (tester) async {
    final gateway = FakeNativeAlarmGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
        ],
        child: const CalarmApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppIdentity.defaultDisplayName), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Wake plan'), findsNothing);
    expect(find.text('Alarm ringing'), findsNothing);
    expect(find.text('Settings'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('home-tools-button')));
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.drawer, isNotNull);
    expect(scaffold.endDrawer, isNull);

    expect(find.text('Wake plan'), findsOneWidget);
    expect(find.text('Alarm ringing'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'blocks home and reconciliation until alarm readiness is freshly granted',
    (tester) async {
      final database = WakePlanDatabase(NativeDatabase.memory());
      final repository = WakePlanRepository(database);
      final gateway = _GrantingPermissionGateway();
      final now = DateTime(2026, 7, 6, 5, 55);
      await repository.saveWakePlan(_testPlan(now));
      addTearDown(database.close);
      final service = WakePlanService(
        repository: repository,
        nativeAlarmGateway: gateway,
        coordinator: WakePlanMutationCoordinator(),
        clock: () => now,
        rollingScheduleDays: 2,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appWakePlanRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            appNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
            appWakePlanServiceProvider.overrideWith((ref) async => service),
          ],
          child: const CalarmApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(alarmPermissionGateKey), findsOneWidget);
      expect(find.text('Allow exact alarms'), findsOneWidget);
      expect(find.text('Calendar'), findsNothing);
      expect(gateway.scheduledRequests, isEmpty);

      await tester.tap(find.byKey(alarmPermissionActionKey));
      await tester.pumpAndSettle();

      expect(find.byKey(alarmPermissionGateKey), findsOneWidget);
      expect(gateway.scheduledRequests, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Calendar'), findsOneWidget);
      expect(gateway.scheduledRequests, isNotEmpty);
      expect(gateway.capabilityChecks, 2);
    },
  );

  testWidgets('capability failure is retryable and never exposes home', (
    tester,
  ) async {
    final gateway = _RetryCapabilityGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
        ],
        child: const CalarmApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alarm access could not be checked'), findsOneWidget);
    expect(find.text('Calendar'), findsNothing);

    await tester.tap(find.byKey(alarmPermissionRetryKey));
    await tester.pumpAndSettle();

    expect(find.text('Calendar'), findsOneWidget);
    expect(gateway.capabilityChecks, 2);
  });

  testWidgets('revocation on resume returns to gate before reconciliation', (
    tester,
  ) async {
    final gateway = _CountingCapabilityGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
        ],
        child: const CalarmApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Calendar'), findsOneWidget);

    gateway.capability = _missingExactAlarmCapability;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Allow exact alarms'), findsOneWidget);
    expect(find.text('Calendar'), findsNothing);
    expect(gateway.capabilityChecks, 2);
  });

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('permission gate fits compact ${size.width}x${size.height}', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final gateway = FakeNativeAlarmGateway(
        capability: _missingExactAlarmCapability,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          ],
          child: const CalarmApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(alarmPermissionGateKey), findsOneWidget);
      expect(find.byKey(alarmPermissionActionKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scenario in <({NativeAlarmCapability capability, String title})>[
    (capability: _missingExactAlarmCapability, title: 'Allow exact alarms'),
    (
      capability: const NativeAlarmCapability(
        permissionStatus: NativeAlarmPermissionStatus.denied,
        canScheduleAlarms: false,
        canRequestPermission: true,
        requiresNotificationPermission: true,
      ),
      title: 'Allow alarm notifications',
    ),
    (
      capability: const NativeAlarmCapability(
        permissionStatus: NativeAlarmPermissionStatus.denied,
        canScheduleAlarms: false,
        canRequestPermission: true,
        requiresFullScreenIntentPermission: true,
      ),
      title: 'Allow full-screen alarms',
    ),
    (
      capability: const NativeAlarmCapability(
        permissionStatus: NativeAlarmPermissionStatus.denied,
        canScheduleAlarms: false,
        canRequestPermission: true,
        requiresNotificationChannelSetup: true,
      ),
      title: 'Enable the wake alarm channel',
    ),
  ]) {
    testWidgets('gate presents one actionable ${scenario.title} step', (
      tester,
    ) async {
      final gateway = FakeNativeAlarmGateway(capability: scenario.capability);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          ],
          child: const CalarmApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(scenario.title), findsOneWidget);
      expect(find.byKey(alarmPermissionActionKey), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  }

  testWidgets(
    'reconciles wake plans on startup and resume without duplicates',
    (tester) async {
      final database = WakePlanDatabase(NativeDatabase.memory());
      final repository = WakePlanRepository(database);
      final gateway = FakeNativeAlarmGateway();
      final now = DateTime(2026, 7, 6, 5, 55);
      final plan = WakePlan(
        id: 'startup-plan',
        title: 'Morning',
        targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
        startOffset: const Duration(minutes: 15),
        interval: const Duration(minutes: 5),
        repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        isEnabled: true,
        status: WakePlanStatus.scheduled,
        soundId: 'default',
        vibrationEnabled: true,
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveWakePlan(plan);
      addTearDown(database.close);

      final service = WakePlanService(
        repository: repository,
        nativeAlarmGateway: gateway,
        coordinator: WakePlanMutationCoordinator(),
        clock: () => now,
        rollingScheduleDays: 2,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appWakePlanRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            appNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
            appWakePlanServiceProvider.overrideWith((ref) async => service),
            settingsNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          ],
          child: const CalarmApp(),
        ),
      );
      await tester.pumpAndSettle();

      final scheduledCount = gateway.scheduledRequests.length;
      expect(scheduledCount, greaterThan(0));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(gateway.scheduledRequests, hasLength(scheduledCount));
      final occurrences = await repository.fetchOccurrencesForPlan(plan.id);
      expect(
        occurrences.map((occurrence) => occurrence.platformAlarmId),
        everyElement(isNotNull),
      );
    },
  );

  testWidgets(
    'admits resume during startup reconciliation and runs a fresh pass safely',
    (tester) async {
      final database = WakePlanDatabase(NativeDatabase.memory());
      final repository = WakePlanRepository(database);
      final gateway = _BlockingScheduleGateway();
      var now = DateTime(2026, 7, 6, 5, 55);
      final plan = WakePlan(
        id: 'lifecycle-plan',
        title: 'Morning',
        targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
        startOffset: const Duration(minutes: 15),
        interval: const Duration(minutes: 5),
        repeatRule: RepeatRule.weekly({
          Weekday.monday,
          Weekday.tuesday,
          Weekday.wednesday,
        }),
        isEnabled: true,
        status: WakePlanStatus.scheduled,
        soundId: 'default',
        vibrationEnabled: true,
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveWakePlan(plan);
      addTearDown(database.close);

      final service = WakePlanService(
        repository: repository,
        nativeAlarmGateway: gateway,
        coordinator: WakePlanMutationCoordinator(),
        clock: () => now,
        rollingScheduleDays: 2,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appWakePlanRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            appNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
            appWakePlanServiceProvider.overrideWith((ref) async => service),
            settingsNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          ],
          child: const CalarmApp(),
        ),
      );
      await tester.pump();
      await tester.pump();
      await gateway.firstScheduleStarted.future;

      now = DateTime(2026, 7, 7, 5, 55);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      gateway.releaseFirstSchedule.complete();
      await tester.pumpAndSettle();

      expect(gateway.scheduleCallCount, 2);
      expect(gateway.maxConcurrentScheduleCalls, 1);
      expect(gateway.scheduledBatches, hasLength(2));
      expect(gateway.scheduledBatches.first, hasLength(8));
      expect(gateway.scheduledBatches.last, hasLength(4));
      expect(
        gateway.scheduledBatches.last.every(
          (request) => request.scheduledAt.weekday == DateTime.wednesday,
        ),
        isTrue,
      );
      expect(
        gateway.scheduledRequests.map((request) => request.occurrenceId),
        hasLength(
          gateway.scheduledRequests
              .map((request) => request.occurrenceId)
              .toSet()
              .length,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('loaded home stays reachable in compact portrait', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _pumpLoadedHome(tester, const Size(320, 568));

    await _expectHomeSurfacesReachable(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('loaded home stays reachable in compact landscape', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _pumpLoadedHome(tester, const Size(568, 320));

    await _expectHomeSurfacesReachable(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('compact landscape keeps provider errors exception-free', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appWakePlanRepositoryProvider.overrideWith((ref) async {
            throw StateError('database unavailable');
          }),
          settingsNativeAlarmGatewayProvider.overrideWith(
            (ref) => FakeNativeAlarmGateway(),
          ),
        ],
        child: const CalarmApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load wake plans or defaults.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('home-tools-button')));
    await tester.pumpAndSettle();
    expect(find.text('Defaults could not be loaded.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('bootstrap exposes app identity and persistence config', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(appIdentityProvider).displayName,
      AppIdentity.defaultDisplayName,
    );
    expect(
      container.read(appIdentityProvider).applicationId,
      AppIdentity.defaultApplicationId,
    );
    expect(container.read(appDatabaseConfigProvider).name, 'calarm.sqlite');
  });
}

Future<void> _pumpLoadedHome(WidgetTester tester, Size size) async {
  final database = WakePlanDatabase(NativeDatabase.memory());
  final repository = WakePlanRepository(database);
  final gateway = FakeNativeAlarmGateway();
  addTearDown(database.close);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appWakePlanRepositoryProvider.overrideWith((ref) async => repository),
        appNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
        settingsNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
      ],
      child: const CalarmApp(),
    ),
  );
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull);
}

Future<void> _expectHomeSurfacesReachable(WidgetTester tester) async {
  final calendar = find.text('Calendar');
  expect(calendar, findsOneWidget);
  final calendarRect = tester.getRect(calendar);
  expect(calendarRect.top, greaterThanOrEqualTo(0));
  expect(
    calendarRect.bottom,
    lessThanOrEqualTo(tester.view.physicalSize.height),
  );

  final calendarSurface = tester.getRect(find.byType(WeekCalendarPlaceholder));
  expect(calendarSurface.top, greaterThanOrEqualTo(0));
  expect(
    calendarSurface.bottom,
    lessThanOrEqualTo(tester.view.physicalSize.height),
  );
  expect(calendarSurface.height, greaterThan(150));

  expect(find.text('Alarm ringing'), findsNothing);
  expect(find.text('Settings'), findsNothing);
  expect(find.text('Wake plan'), findsNothing);

  final toolsButton = find.byKey(const ValueKey<String>('home-tools-button'));
  expect(toolsButton, findsOneWidget);
  expect(find.byTooltip('Open alarm and settings'), findsOneWidget);
  await tester.tap(toolsButton);
  await tester.pumpAndSettle();

  final sectionsScroll = find.byKey(
    const ValueKey<String>('home-sections-scroll'),
  );
  expect(sectionsScroll, findsOneWidget);
  final viewport = tester.getRect(sectionsScroll);

  for (final label in [
    'Alarm ringing',
    'Schedule 1-minute test alarm',
    'Wake window',
    'Wake plan',
  ]) {
    final target = find.text(label);
    expect(target, findsOneWidget);
    await _dragUntilVisible(tester, sectionsScroll, target, viewport, label);
  }
}

class _BlockingScheduleGateway extends FakeNativeAlarmGateway {
  final firstScheduleStarted = Completer<void>();
  final releaseFirstSchedule = Completer<void>();
  final scheduledBatches = <List<NativeAlarmScheduleRequest>>[];
  var activeScheduleCalls = 0;
  var maxConcurrentScheduleCalls = 0;
  var scheduleCallCount = 0;

  @override
  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  ) async {
    scheduleCallCount += 1;
    activeScheduleCalls += 1;
    maxConcurrentScheduleCalls =
        activeScheduleCalls > maxConcurrentScheduleCalls
        ? activeScheduleCalls
        : maxConcurrentScheduleCalls;
    scheduledBatches.add(List<NativeAlarmScheduleRequest>.of(occurrences));
    try {
      if (scheduleCallCount == 1) {
        firstScheduleStarted.complete();
        await releaseFirstSchedule.future;
      }
      return await super.scheduleOccurrences(occurrences);
    } finally {
      activeScheduleCalls -= 1;
    }
  }
}

const _missingExactAlarmCapability = NativeAlarmCapability(
  permissionStatus: NativeAlarmPermissionStatus.denied,
  canScheduleAlarms: false,
  canRequestPermission: true,
  requiresExactAlarmPermission: true,
  supportsInventory: true,
);

WakePlan _testPlan(DateTime now) {
  return WakePlan(
    id: 'permission-plan',
    title: 'Morning',
    targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
    startOffset: const Duration(minutes: 15),
    interval: const Duration(minutes: 5),
    repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
    isEnabled: true,
    status: WakePlanStatus.scheduled,
    soundId: 'default',
    vibrationEnabled: true,
    createdAt: now,
    updatedAt: now,
  );
}

class _CountingCapabilityGateway extends FakeNativeAlarmGateway {
  var capabilityChecks = 0;

  @override
  Future<NativeAlarmCapability> getCapability() async {
    capabilityChecks += 1;
    return super.getCapability();
  }
}

class _GrantingPermissionGateway extends _CountingCapabilityGateway {
  _GrantingPermissionGateway() {
    capability = _missingExactAlarmCapability;
  }

  @override
  Future<NativeAlarmPermissionResult> requestPermission() async {
    capability = const NativeAlarmCapability(
      permissionStatus: NativeAlarmPermissionStatus.authorized,
      canScheduleAlarms: true,
      canRequestPermission: false,
      supportsInventory: true,
    );
    return const NativeAlarmPermissionResult(
      status: NativeAlarmPermissionRequestStatus.granted,
      permissionStatus: NativeAlarmPermissionStatus.authorized,
    );
  }
}

class _RetryCapabilityGateway extends _CountingCapabilityGateway {
  @override
  Future<NativeAlarmCapability> getCapability() {
    capabilityChecks += 1;
    if (capabilityChecks == 1) {
      throw const NativeAlarmCapabilityException(
        reason: NativeAlarmCapabilityFailureReason.transport,
        message: 'temporary transport failure',
      );
    }
    return Future.value(capability);
  }
}

Future<void> _dragUntilVisible(
  WidgetTester tester,
  Finder scrollable,
  Finder target,
  Rect viewport,
  String label,
) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final rect = tester.getRect(target);
    if (rect.top >= viewport.top && rect.bottom <= viewport.bottom) {
      return;
    }

    await tester.drag(scrollable, const Offset(0, -40));
    await tester.pumpAndSettle();
  }

  final rect = tester.getRect(target);
  expect(
    rect.top >= viewport.top && rect.bottom <= viewport.bottom,
    isTrue,
    reason:
        'Expected $label to become visible after drags. '
        'viewport=$viewport rect=$rect.',
  );
}
