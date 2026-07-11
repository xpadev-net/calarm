import 'dart:async';

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

    await tester.ensureVisible(find.text('Sound and vibration'));
    await tester.tap(find.text('Sound and vibration'));
    await tester.pumpAndSettle();

    expect(find.text('Default sound'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
  });

  testWidgets('creates an arbitrary weekly repeat from selected weekdays', (
    tester,
  ) async {
    WakePlan? savedPlan;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateWakePlanSheet(
            initialTarget: _target(),
            now: DateTime(2026, 7, 8, 5, 30),
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onSave: (plan) async {
              savedPlan = plan;
              return _failureResult();
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('No repeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose weekdays').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fri'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      savedPlan?.repeatRule,
      RepeatRule.weekly({Weekday.wednesday, Weekday.friday}),
    );
  });

  testWidgets('creates daily, weekday, and weekend repeat presets', (
    tester,
  ) async {
    final savedPlans = <WakePlan>[];

    Future<void> pumpForPreset(String label) async {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Scaffold(
            body: CreateWakePlanSheet(
              initialTarget: _target(),
              now: DateTime(2026, 7, 8, 5, 30),
              clock: () => DateTime(2026, 7, 8, 5, 30),
              defaults: AppSettings.initial(),
              existingWakePlans: const [],
              onSave: (plan) async {
                savedPlans.add(plan);
                return _failureResult();
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('No repeat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    await pumpForPreset('Daily');
    await pumpForPreset('Weekdays');
    await pumpForPreset('Weekends');

    expect(savedPlans[0].repeatRule.weekdays, Set.of(Weekday.values));
    expect(savedPlans[1].repeatRule.weekdays, {
      Weekday.monday,
      Weekday.tuesday,
      Weekday.wednesday,
      Weekday.thursday,
      Weekday.friday,
    });
    expect(savedPlans[2].repeatRule.weekdays, {
      Weekday.saturday,
      Weekday.sunday,
    });
  });

  testWidgets('seeds default weekly repeat from the tapped target day', (
    tester,
  ) async {
    WakePlan? savedPlan;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateWakePlanSheet(
            initialTarget: _target(),
            now: DateTime(2026, 7, 8, 5, 30),
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial().copyWith(
              defaultRepeatType: RepeatType.weekly,
            ),
            existingWakePlans: const [],
            onSave: (plan) async {
              savedPlan = plan;
              return _failureResult();
            },
          ),
        ),
      ),
    );

    expect(find.text('Choose weekdays'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Wed'))
          .selected,
      isTrue,
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedPlan?.repeatRule, RepeatRule.weekly({Weekday.wednesday}));
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

  testWidgets('retries with one session identity and ignores a double tap', (
    tester,
  ) async {
    final firstCompletion = Completer<WakePlanSchedulingResult>();
    final savedPlans = <WakePlan>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateWakePlanSheet(
            initialTarget: _target(),
            now: DateTime(2026, 7, 8, 5, 30),
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onSave: (plan) {
              savedPlans.add(plan);
              if (savedPlans.length == 1) {
                return firstCompletion.future;
              }
              return Future.value(_successResult());
            },
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(savedPlans, hasLength(1));
    firstCompletion.complete(_failureResult());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(savedPlans, hasLength(2));
    expect(savedPlans[1].id, savedPlans[0].id);
  });

  testWidgets('locks create draft metadata after partial failure before retry', (
    tester,
  ) async {
    final savedPlans = <WakePlan>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateWakePlanSheet(
            initialTarget: _target(),
            now: DateTime(2026, 7, 8, 5, 30),
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onSave: (plan) async {
              savedPlans.add(plan);
              return savedPlans.length == 1
                  ? _partialFailureResult()
                  : _successResult();
            },
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Some alarms could not be scheduled.'), findsOneWidget);
    expect(
      find.text(
        'Draft locked after submission. Retry this request or close and reopen to edit it.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Change wake target time',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is IconButton && widget.tooltip == 'Change wake target time',
      ),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(find.text('2026-07-08 07:00'), findsOneWidget);

    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(savedPlans, hasLength(2));
    expect(savedPlans[1].id, savedPlans[0].id);
    expect(savedPlans[1].targetTime, savedPlans[0].targetTime);
    expect(savedPlans[1].startOffset, savedPlans[0].startOffset);
    expect(savedPlans[1].interval, savedPlans[0].interval);
    expect(savedPlans[1].repeatRule, savedPlans[0].repeatRule);
    expect(savedPlans[1].soundId, savedPlans[0].soundId);
    expect(savedPlans[1].vibrationEnabled, savedPlans[0].vibrationEnabled);
  });

  testWidgets(
    'uses collision-safe identities across independent sheet sessions',
    (tester) async {
      final savedPlans = <WakePlan>[];

      Widget buildSheet(List<WakePlan> existingWakePlans) {
        return MaterialApp(
          home: Scaffold(
            body: CreateWakePlanSheet(
              key: UniqueKey(),
              initialTarget: _target(),
              now: DateTime(2026, 7, 8, 5, 30),
              clock: () => DateTime(2026, 7, 8, 5, 30),
              defaults: AppSettings.initial(),
              existingWakePlans: existingWakePlans,
              onSave: (plan) {
                savedPlans.add(plan);
                return Future.value(_failureResult());
              },
            ),
          ),
        );
      }

      await tester.pumpWidget(buildSheet(const []));
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(buildSheet([savedPlans.single]));
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedPlans, hasLength(2));
      expect(savedPlans[0].id, startsWith('wake-session-'));
      expect(savedPlans[1].id, startsWith('wake-session-'));
      expect(savedPlans[1].id, isNot(savedPlans[0].id));
    },
  );

  testWidgets('ignores a delayed save completion after disposal', (
    tester,
  ) async {
    final completion = Completer<WakePlanSchedulingResult>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateWakePlanSheet(
            initialTarget: _target(),
            now: DateTime(2026, 7, 8, 5, 30),
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onSave: (_) => completion.future,
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    completion.complete(_successResult());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
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

  testWidgets('warns when a cross-day draft overlaps before visible week', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateWakePlanSheet(
            initialTarget: WeekCalendarTapTarget(
              day: CalendarDay(year: 2026, month: 7, day: 5),
              time: TimeOfDayMinutes.fromHourMinute(hour: 1, minute: 0),
            ),
            now: DateTime(2026, 7, 4, 21),
            clock: () => DateTime(2026, 7, 4, 21),
            defaults: AppSettings.initial().copyWith(
              defaultStartOffset: const Duration(hours: 3),
            ),
            existingWakePlans: [
              _plan(
                id: 'previous-week',
                targetDay: CalendarDay(year: 2026, month: 7, day: 4),
                targetTime: TimeOfDayMinutes.fromHourMinute(
                  hour: 23,
                  minute: 0,
                ),
              ),
            ],
            onSave: (_) async => _successResult(),
          ),
        ),
      ),
    );

    expect(find.text('Overlaps 22:00-23:00.'), findsOneWidget);
  });

  testWidgets('summarizes multiple overlapping wake windows', (tester) async {
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
                id: 'existing-1',
                targetDay: CalendarDay(year: 2026, month: 7, day: 8),
              ),
              _plan(
                id: 'existing-2',
                targetDay: CalendarDay(year: 2026, month: 7, day: 8),
              ),
            ],
            onSave: (_) async => _successResult(),
          ),
        ),
      ),
    );

    expect(find.text('Overlaps 2 wake plans.'), findsOneWidget);
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

WakePlanSchedulingResult _partialFailureResult() {
  final scheduleResult = ScheduleResult.fromOccurrences([
    ScheduleOccurrenceResult.success(
      occurrenceId: 'occurrence-one',
      wakePlanId: 'created',
      platformAlarmId: 'native-one',
    ),
    ScheduleOccurrenceResult.failure(
      occurrenceId: 'occurrence-two',
      wakePlanId: 'created',
      reason: ScheduleFailureReason.nativeError,
    ),
  ]);
  return WakePlanSchedulingResult(
    wakePlanId: 'created',
    status: WakePlanSchedulingStatus.scheduleFailed,
    changeState: WakePlanChangeState.failed,
    scheduleResult: scheduleResult,
    occurrences: const [],
    warning: WakePlanSchedulingWarning.scheduleFailed(scheduleResult),
  );
}
