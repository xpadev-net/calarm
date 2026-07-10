import 'dart:async';
import 'dart:ui' show Rect, Size;

import 'package:calarm/app.dart';
import 'package:calarm/core/bootstrap/app_bootstrap.dart';
import 'package:calarm/core/identity/app_identity.dart';
import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/settings/application/alarm_health_controller.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, SizedBox;
import 'package:drift/native.dart';

void main() {
  testWidgets('renders loaded scaffold feature boundaries', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CalarmApp()));
    await tester.pumpAndSettle();

    expect(find.text(AppIdentity.defaultDisplayName), findsOneWidget);
    expect(find.text('Wake plan'), findsOneWidget);
    expect(find.text('Week calendar'), findsOneWidget);
    expect(find.text('Alarm ringing'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
      await gateway.firstScheduleStarted.future;

      now = DateTime(2026, 7, 7, 5, 55);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
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
  final calendar = find.text('Week calendar');
  expect(calendar, findsOneWidget);
  final calendarRect = tester.getRect(calendar);
  expect(calendarRect.top, greaterThanOrEqualTo(0));
  expect(
    calendarRect.bottom,
    lessThanOrEqualTo(tester.view.physicalSize.height),
  );

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
