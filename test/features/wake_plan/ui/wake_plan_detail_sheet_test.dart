import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:calarm/features/wake_plan/ui/wake_plan_detail_sheet.dart';
import 'package:calarm/features/week_calendar/week_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('does not offer skip next for an unskipped one-time plan', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WakePlanDetailSheet(
            target: WeekCalendarWakePlanTapTarget(
              wakePlan: _plan(repeatRule: RepeatRule.oneTime(_targetDay)),
              targetDay: _targetDay,
            ),
            now: DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (_) async => _successResult(),
          ),
        ),
      ),
    );

    expect(find.text('Skip next target'), findsNothing);
    expect(find.text('Undo skip'), findsNothing);
  });

  testWidgets('offers undo for already skipped one-time plans', (tester) async {
    WakePlan? restored;
    final plan = _plan(
      repeatRule: RepeatRule.oneTime(_targetDay),
    ).copyWith(skipNextDate: _targetDay);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WakePlanDetailSheet(
            target: WeekCalendarWakePlanTapTarget(
              wakePlan: plan,
              targetDay: _targetDay,
            ),
            now: DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (plan) async {
              restored = plan;
              return _successResult();
            },
          ),
        ),
      ),
    );

    expect(find.text('Undo skip'), findsOneWidget);

    await tester.tap(find.text('Undo skip'));
    await tester.pumpAndSettle();

    expect(restored?.id, 'plan-1');
  });

  testWidgets('shows skip state and triggers skip next', (tester) async {
    WakePlan? skipped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WakePlanDetailSheet(
            target: WeekCalendarWakePlanTapTarget(
              wakePlan: _plan(),
              targetDay: CalendarDay(year: 2026, month: 7, day: 8),
            ),
            now: DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async => _successResult(),
            onSkipNext: (plan) async {
              skipped = plan;
              return _successResult();
            },
            onUndoSkipNext: (_) async => _successResult(),
          ),
        ),
      ),
    );

    expect(find.text('Skip state'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);

    await tester.tap(find.text('Skip next target'));
    await tester.pumpAndSettle();

    expect(skipped?.id, 'plan-1');
  });

  testWidgets('shows skipped target date and triggers undo skip', (
    tester,
  ) async {
    WakePlan? restored;
    final plan = _plan().copyWith(
      skipNextDate: CalendarDay(year: 2026, month: 7, day: 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WakePlanDetailSheet(
            target: WeekCalendarWakePlanTapTarget(
              wakePlan: plan,
              targetDay: CalendarDay(year: 2026, month: 7, day: 9),
            ),
            now: DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (plan) async {
              restored = plan;
              return _successResult();
            },
          ),
        ),
      ),
    );

    expect(find.text('Skipping next target on 2026-07-08'), findsOneWidget);

    await tester.tap(find.text('Undo skip'));
    await tester.pumpAndSettle();

    expect(restored?.id, 'plan-1');
  });
}

final _targetDay = CalendarDay(year: 2026, month: 7, day: 8);

WakePlan _plan({RepeatRule? repeatRule}) {
  final now = DateTime(2026, 7, 8, 5, 30);
  return WakePlan(
    id: 'plan-1',
    title: 'Morning',
    targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
    startOffset: const Duration(minutes: 60),
    interval: const Duration(minutes: 5),
    repeatRule:
        repeatRule ?? RepeatRule.weekly({Weekday.wednesday, Weekday.thursday}),
    isEnabled: true,
    status: WakePlanStatus.scheduled,
    soundId: defaultWakePlanSoundId,
    vibrationEnabled: true,
    createdAt: now,
    updatedAt: now,
  );
}

WakePlanSchedulingResult _successResult() {
  return WakePlanSchedulingResult(
    wakePlanId: 'plan-1',
    status: WakePlanSchedulingStatus.scheduled,
    changeState: WakePlanChangeState.committed,
    scheduleResult: ScheduleResult(
      status: ScheduleResultStatus.success,
      occurrences: const [],
    ),
    occurrences: const [],
  );
}
