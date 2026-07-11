import 'dart:async';

import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/settings/application/wake_plan_defaults_controller.dart';
import 'package:calarm/features/week_calendar/presentation/week_calendar_placeholder.dart';
import 'package:calarm/features/week_calendar/week_calendar.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WakePlanDatabase database;
  late WakePlanRepository repository;
  late ProviderContainer container;

  setUp(() {
    database = WakePlanDatabase(NativeDatabase.memory());
    repository = WakePlanRepository(database);
    container = ProviderContainer(
      overrides: [
        weekCalendarRepositoryProvider.overrideWith((ref) async => repository),
        weekCalendarClockProvider.overrideWith(
          (ref) =>
              () => DateTime(2026, 7, 8, 5, 30),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test(
    'loads future plans outside the current visible week for paging',
    () async {
      final plan = _plan(
        id: 'next-week',
        targetDay: CalendarDay(year: 2026, month: 7, day: 15),
      );
      await repository.saveWakePlan(plan);

      final plans = await container.read(weekCalendarWakePlansProvider.future);

      expect(plans.map((plan) => plan.id), contains('next-week'));
    },
  );

  testWidgets('surfaces provider load errors instead of silent fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith((ref) async {
            throw StateError('database unavailable');
          }),
          wakePlanDefaultsRepositoryProvider.overrideWith((ref) async {
            throw StateError('defaults unavailable');
          }),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 0, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load wake plans or defaults.'), findsOneWidget);

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not open wake plan editor.'), findsOneWidget);
  });

  testWidgets('expands calendar to fill the available primary surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 720, child: WeekCalendarPlaceholder()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );

    expect(calendar.height, greaterThanOrEqualTo(560));
    expect(calendar.hourHeight, 52);
  });

  test(
    'feature repository providers share the app repository instance',
    () async {
      final container = ProviderContainer(
        overrides: [
          appWakePlanRepositoryProvider.overrideWith((ref) async => repository),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(weekCalendarRepositoryProvider.future),
        same(repository),
      );
      expect(
        await container.read(wakePlanDefaultsRepositoryProvider.future),
        same(repository),
      );
    },
  );

  testWidgets('guards against stacked create sheets while service loads', (
    tester,
  ) async {
    final service = Completer<WakePlanService>();
    await repository.saveWakePlan(
      _plan(id: 'seed', targetDay: CalendarDay(year: 2026, month: 7, day: 10)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarWakePlanServiceProvider.overrideWith((ref) {
            return service.future;
          }),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    final target = WeekCalendarTapTarget(
      day: CalendarDay(year: 2026, month: 7, day: 9),
      time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
    );

    calendar.onTargetTap!(target);
    await tester.pump();
    calendar.onTargetTap!(target);
    await tester.pump();

    service.complete(
      WakePlanService(
        repository: repository,
        nativeAlarmGateway: FakeNativeAlarmGateway(),
        clock: () => DateTime(2026, 7, 8, 0, 30),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create wake plan'), findsOneWidget);
  });

  testWidgets('refreshes persisted plans after schedule failure', (
    tester,
  ) async {
    final gateway = FakeNativeAlarmGateway()
      ..scheduleFailureReason = ScheduleFailureReason.permissionMissing;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Alarm permission is required before alarms can be scheduled.'),
      findsOneWidget,
    );
    expect(find.text('Create wake plan'), findsOneWidget);
    final refreshedCalendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    expect(refreshedCalendar.wakePlans, hasLength(1));

    gateway.scheduleFailureReason = null;
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(gateway.scheduledRequests, hasLength(26));
    final retriedCalendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    expect(retriedCalendar.wakePlans, hasLength(1));
  });

  testWidgets('create validation follows the live injected clock', (
    tester,
  ) async {
    final initialNow = DateTime(2026, 7, 8, 5, 30);
    var currentNow = initialNow;
    var clockCalls = 0;
    DateTime clock() {
      clockCalls += 1;
      return currentNow;
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith(
            (ref) => FakeNativeAlarmGateway(),
          ),
          weekCalendarClockProvider.overrideWith((ref) => clock),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create wake plan'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );

    currentNow = DateTime(2026, 7, 10, 5, 30);
    await tester.tap(find.text('No repeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No repeat').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Choose a future wake target before saving.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(clockCalls, greaterThan(1));
  });

  testWidgets('opens wake plan detail and edit reschedules future alarms', (
    tester,
  ) async {
    final gateway = FakeNativeAlarmGateway();
    final now = DateTime(2026, 7, 8, 5, 30);
    final plan = _plan(
      id: 'editable',
      targetDay: CalendarDay(year: 2026, month: 7, day: 9),
    );
    final service = WakePlanService(
      repository: repository,
      nativeAlarmGateway: gateway,
      clock: () => now,
    );
    await service.createPlan(plan);
    gateway.scheduledRequests.clear();
    gateway.cancelledOccurrences.clear();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => now,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onWakePlanTap!(
      WeekCalendarWakePlanTapTarget(
        wakePlan: plan,
        targetDay: CalendarDay(year: 2026, month: 7, day: 9),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wake plan detail'), findsOneWidget);
    expect(find.text('Next fire'), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Skip state'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit wake plan'), findsOneWidget);

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(gateway.cancelledOccurrences, isNotEmpty);
    expect(gateway.scheduledRequests, isNotEmpty);
    expect(
      find.textContaining('Wake plan updated. Next alarm:'),
      findsOneWidget,
    );
  });

  testWidgets('editing weekly plan from past block preserves repeat weekdays', (
    tester,
  ) async {
    final gateway = FakeNativeAlarmGateway();
    final now = DateTime(2026, 7, 8, 5, 30);
    final plan = _plan(
      id: 'weekly-edit',
      targetDay: CalendarDay(year: 2026, month: 7, day: 6),
      repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.wednesday}),
    );
    final service = WakePlanService(
      repository: repository,
      nativeAlarmGateway: gateway,
      clock: () => now,
    );
    await service.createPlan(plan);
    gateway.scheduledRequests.clear();
    gateway.cancelledOccurrences.clear();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => now,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onWakePlanTap!(
      WeekCalendarWakePlanTapTarget(
        wakePlan: plan,
        targetDay: CalendarDay(year: 2026, month: 7, day: 6),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit wake plan'), findsOneWidget);
    expect(
      find.text('Choose a future wake target before saving.'),
      findsNothing,
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(gateway.cancelledOccurrences, isNotEmpty);
    expect(gateway.scheduledRequests, isNotEmpty);
    final saved = await repository.fetchWakePlan('weekly-edit');
    expect(
      saved?.repeatRule,
      RepeatRule.weekly({Weekday.monday, Weekday.wednesday}),
    );
    expect(
      find.textContaining('Wake plan updated. Next alarm:'),
      findsOneWidget,
    );
  });

  testWidgets(
    'confirms repeating wake plan delete and removes calendar block',
    (tester) async {
      final gateway = FakeNativeAlarmGateway();
      final now = DateTime(2026, 7, 8, 5, 30);
      final plan = _plan(
        id: 'weekly-delete',
        targetDay: CalendarDay(year: 2026, month: 7, day: 10),
        repeatRule: RepeatRule.weekly({Weekday.friday}),
      );
      final service = WakePlanService(
        repository: repository,
        nativeAlarmGateway: gateway,
        clock: () => now,
      );
      await service.createPlan(plan);
      gateway.cancelledPlans.clear();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekCalendarRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            wakePlanDefaultsRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            weekCalendarNativeAlarmGatewayProvider.overrideWith(
              (ref) => gateway,
            ),
            weekCalendarClockProvider.overrideWith(
              (ref) =>
                  () => now,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: WeekCalendarPlaceholder()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var calendar = tester.widget<WeekCalendarView>(
        find.byType(WeekCalendarView),
      );
      expect(
        calendar.wakePlans.map((plan) => plan.id),
        contains('weekly-delete'),
      );

      calendar.onWakePlanTap!(
        WeekCalendarWakePlanTapTarget(
          wakePlan: plan,
          targetDay: CalendarDay(year: 2026, month: 7, day: 10),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete repeating wake plan?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
      await tester.pumpAndSettle();

      expect(gateway.cancelledPlans, isNotEmpty);
      expect(await repository.fetchWakePlan('weekly-delete'), isNull);
      expect(find.text('Wake plan deleted.'), findsOneWidget);

      calendar = tester.widget<WeekCalendarView>(find.byType(WeekCalendarView));
      expect(
        calendar.wakePlans.map((plan) => plan.id),
        isNot(contains('weekly-delete')),
      );
    },
  );

  testWidgets('skips next target from detail and keeps following repeats', (
    tester,
  ) async {
    final gateway = FakeNativeAlarmGateway();
    final now = DateTime(2026, 7, 8, 5, 30);
    final skippedDay = CalendarDay(year: 2026, month: 7, day: 8);
    final followingDay = CalendarDay(year: 2026, month: 7, day: 9);
    final plan = _plan(
      id: 'weekly-skip',
      targetDay: skippedDay,
      repeatRule: RepeatRule.weekly({Weekday.wednesday, Weekday.thursday}),
    );
    final service = WakePlanService(
      repository: repository,
      nativeAlarmGateway: gateway,
      clock: () => now,
    );
    await service.createPlan(plan);
    gateway.cancelledOccurrences.clear();
    gateway.scheduledRequests.clear();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => now,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onWakePlanTap!(
      WeekCalendarWakePlanTapTarget(wakePlan: plan, targetDay: skippedDay),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip next target'));
    await tester.pumpAndSettle();

    final saved = await repository.fetchWakePlan('weekly-skip');
    expect(saved?.skipNextDate, skippedDay);
    expect(gateway.cancelledOccurrences, isNotEmpty);
    expect(gateway.scheduledRequests, isNotEmpty);
    expect(find.text('Next wake target skipped.'), findsOneWidget);
    expect(saved!.occursOn(skippedDay), isFalse);
    expect(saved.occursOn(followingDay), isTrue);
  });
}

WakePlan _plan({
  required String id,
  required CalendarDay targetDay,
  RepeatRule? repeatRule,
}) {
  final now = DateTime(2026, 7, 8, 5, 30);
  return WakePlan(
    id: id,
    title: id,
    targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
    startOffset: const Duration(minutes: 60),
    interval: const Duration(minutes: 5),
    repeatRule: repeatRule ?? RepeatRule.oneTime(targetDay),
    isEnabled: true,
    status: WakePlanStatus.scheduled,
    soundId: defaultWakePlanSoundId,
    vibrationEnabled: true,
    createdAt: now,
    updatedAt: now,
  );
}
