import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:calarm/features/wake_plan/ui/create_wake_plan_sheet.dart';
import 'package:calarm/features/week_calendar/week_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows default preview with advanced settings collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateWakePlanSheet(
            initialTarget: _target(),
            now: DateTime(2026, 7, 8, 5, 30),
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onSave: (_) async => _successResult(),
          ),
        ),
      ),
    );

    expect(find.text('2026-07-08 07:00'), findsOneWidget);
    expect(find.text('06:00-07:00'), findsOneWidget);
    expect(find.text('5 min'), findsWidgets);
    expect(find.text('13 alarms'), findsNWidgets(2));
    expect(find.text('Default sound'), findsNothing);

    await tester.tap(find.text('Sound and vibration'));
    await tester.pumpAndSettle();

    expect(find.text('Default sound'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
  });

  testWidgets('does not save a past concrete target', (tester) async {
    var saved = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateWakePlanSheet(
            initialTarget: _target(),
            now: DateTime(2026, 7, 8, 7, 1),
            clock: () => DateTime(2026, 7, 8, 7, 1),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onSave: (_) async {
              saved = true;
              return _successResult();
            },
          ),
        ),
      ),
    );

    expect(
      find.text('Choose a future wake target before saving.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(saved, isFalse);
  });

  testWidgets('keeps schedule failures visible instead of popping success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateWakePlanSheet(
            initialTarget: _target(),
            now: DateTime(2026, 7, 8, 5, 30),
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onSave: (_) async => _failureResult(),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Alarm permission is required before alarms can be scheduled.'),
      findsOneWidget,
    );
    expect(find.text('Create wake plan'), findsOneWidget);
  });

  testWidgets('shows an inline warning for overlapping wake windows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateWakePlanSheet(
            initialTarget: _target(),
            now: DateTime(2026, 7, 8, 5, 30),
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: [
              _plan(
                id: 'existing',
                targetDay: CalendarDay(year: 2026, month: 7, day: 8),
              ),
            ],
            onSave: (_) async => _successResult(),
          ),
        ),
      ),
    );

    expect(find.text('Overlaps 06:00-07:00.'), findsOneWidget);
  });

  testWidgets('calendar tap opens create sheet and save renders a block', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _FlowHarness())),
    );

    final gridFinder = find.byType(CustomPaint).last;
    final gridTopLeft = tester.getTopLeft(gridFinder);
    final gridSize = tester.getSize(gridFinder);
    await tester.tapAt(
      Offset(
        gridTopLeft.dx + (gridSize.width / DateTime.daysPerWeek * 2.5),
        gridTopLeft.dy + (gridSize.height / 24 * 7),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create wake plan'), findsOneWidget);
    expect(find.text('06:00-07:00'), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('07:00\n06:00-07:00\nEvery 5 min\n13 alarms'),
      findsOneWidget,
    );
  });
}

class _FlowHarness extends StatefulWidget {
  const _FlowHarness();

  @override
  State<_FlowHarness> createState() => _FlowHarnessState();
}

class _FlowHarnessState extends State<_FlowHarness> {
  final List<WakePlan> _plans = [];
  final DateTime _now = DateTime(2026, 7, 8, 5, 30);

  @override
  Widget build(BuildContext context) {
    return WeekCalendarView(
      now: _now,
      initialWeek: WeekRange(start: CalendarDay(year: 2026, month: 7, day: 6)),
      wakePlans: _plans,
      onTargetTap: (target) {
        showModalBottomSheet<WakePlanSchedulingResult>(
          context: context,
          builder: (context) {
            return CreateWakePlanSheet(
              initialTarget: target,
              now: _now,
              clock: () => _now,
              defaults: AppSettings.initial(),
              existingWakePlans: _plans,
              onSave: (plan) async {
                setState(() => _plans.add(plan));
                return _successResult();
              },
            );
          },
        );
      },
    );
  }
}

WeekCalendarTapTarget _target() {
  return WeekCalendarTapTarget(
    day: CalendarDay(year: 2026, month: 7, day: 8),
    time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
  );
}

WakePlan _plan({
  required String id,
  required CalendarDay targetDay,
  TimeOfDayMinutes? targetTime,
}) {
  final now = DateTime(2026, 7, 8, 5, 30);
  return WakePlan(
    id: id,
    title: id,
    targetTime:
        targetTime ?? TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
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

WakePlanSchedulingResult _successResult() {
  return WakePlanSchedulingResult(
    wakePlanId: 'created',
    status: WakePlanSchedulingStatus.scheduled,
    changeState: WakePlanChangeState.committed,
    scheduleResult: ScheduleResult(
      status: ScheduleResultStatus.success,
      occurrences: const [],
    ),
    occurrences: const [],
  );
}

WakePlanSchedulingResult _failureResult() {
  final scheduleResult = ScheduleResult(
    status: ScheduleResultStatus.permissionMissing,
    occurrences: const [],
  );
  return WakePlanSchedulingResult(
    wakePlanId: 'created',
    status: WakePlanSchedulingStatus.scheduleFailed,
    changeState: WakePlanChangeState.failed,
    scheduleResult: scheduleResult,
    occurrences: const [],
    warning: WakePlanSchedulingWarning.scheduleFailed(scheduleResult),
  );
}
