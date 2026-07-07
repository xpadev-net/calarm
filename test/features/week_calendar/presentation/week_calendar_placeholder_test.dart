import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/settings/application/wake_plan_defaults_controller.dart';
import 'package:calarm/features/week_calendar/presentation/week_calendar_placeholder.dart';
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
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load wake plans or defaults.'), findsOneWidget);
  });
}

WakePlan _plan({required String id, required CalendarDay targetDay}) {
  final now = DateTime(2026, 7, 8, 5, 30);
  return WakePlan(
    id: id,
    title: id,
    targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
    startOffset: const Duration(minutes: 60),
    interval: const Duration(minutes: 5),
    repeatRule: RepeatRule.oneTime(targetDay),
    isEnabled: true,
    status: WakePlanStatus.scheduled,
    soundId: defaultWakePlanSoundId,
    vibrationEnabled: true,
    createdAt: now,
    updatedAt: now,
  );
}
