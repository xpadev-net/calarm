import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/week_calendar/week_calendar.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders date header, time axis, grid, current week, and empty state',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeekCalendarView(now: DateTime(2026, 7, 8, 7, 30)),
          ),
        ),
      );

      expect(find.text('Sun'), findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Wed'), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);
      expect(find.text('24:00'), findsOneWidget);
      expect(
        find.text('No wake plans scheduled for this week'),
        findsOneWidget,
      );
      expect(find.byType(CustomPaint), findsWidgets);
    },
  );

  testWidgets('scrolls the current week near the current time after layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekCalendarView(now: DateTime(2026, 7, 8, 7, 30)),
        ),
      ),
    );
    await tester.pump();

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );

    expect(scrollView.controller, isNotNull);
    expect(scrollView.controller!.offset, 324);
  });

  testWidgets('converts a grid tap into a calendar day and five-minute time', (
    tester,
  ) async {
    WeekCalendarTapTarget? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekCalendarView(
            now: DateTime(2026, 7, 8, 7, 30),
            initialWeek: WeekRange(
              start: CalendarDay(year: 2026, month: 7, day: 6),
            ),
            onTargetTap: (target) => selected = target,
          ),
        ),
      ),
    );

    final gridFinder = find.byType(CustomPaint).last;
    final gridTopLeft = tester.getTopLeft(gridFinder);
    final gridSize = tester.getSize(gridFinder);
    await tester.tapAt(
      Offset(
        gridTopLeft.dx + (gridSize.width / DateTime.daysPerWeek * 2.5),
        gridTopLeft.dy + (gridSize.height / 24 * 7) + 3,
      ),
    );
    await tester.pump();

    expect(selected, isNotNull);
    expect(selected!.day, CalendarDay(year: 2026, month: 7, day: 8));
    expect(selected!.time, TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 5));
  });

  testWidgets('renders a wake plan block label and hides the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekCalendarView(
            now: DateTime(2026, 7, 8, 7, 30),
            initialWeek: WeekRange(
              start: CalendarDay(year: 2026, month: 7, day: 6),
            ),
            wakePlans: [
              buildPlan(
                id: 'plan-1',
                targetDay: CalendarDay(year: 2026, month: 7, day: 8),
                targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('No wake plans scheduled for this week'), findsNothing);
    expect(
      find.text('07:00\n06:00-07:00\nEvery 5 min\n13 alarms'),
      findsOneWidget,
    );
  });

  testWidgets('routes a block tap to the wake plan detail event', (
    tester,
  ) async {
    WeekCalendarWakePlanTapTarget? selected;
    final plan = buildPlan(
      id: 'plan-1',
      targetDay: CalendarDay(year: 2026, month: 7, day: 8),
      targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekCalendarView(
            now: DateTime(2026, 7, 8, 7, 30),
            initialWeek: WeekRange(
              start: CalendarDay(year: 2026, month: 7, day: 6),
            ),
            wakePlans: [plan],
            onWakePlanTap: (target) => selected = target,
          ),
        ),
      ),
    );

    await tester.tap(find.text('07:00\n06:00-07:00\nEvery 5 min\n13 alarms'));
    await tester.pump();

    expect(selected, isNotNull);
    expect(selected!.wakePlan, plan);
    expect(selected!.targetDay, CalendarDay(year: 2026, month: 7, day: 8));
    expect(selected!.targetAt, DateTime(2026, 7, 8, 7));
  });

  testWidgets('keeps three compact overlapping blocks inside their day lanes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekCalendarView(
            now: DateTime(2026, 7, 8, 7, 30),
            initialWeek: WeekRange(
              start: CalendarDay(year: 2026, month: 7, day: 6),
            ),
            wakePlans: [
              buildPlan(
                id: 'plan-1',
                targetDay: CalendarDay(year: 2026, month: 7, day: 8),
                targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
              ),
              buildPlan(
                id: 'plan-2',
                targetDay: CalendarDay(year: 2026, month: 7, day: 8),
                targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
              ),
              buildPlan(
                id: 'plan-3',
                targetDay: CalendarDay(year: 2026, month: 7, day: 8),
                targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
              ),
            ],
          ),
        ),
      ),
    );

    const timeAxisWidth = 52;
    const dayWidth = (390 - timeAxisWidth) / DateTime.daysPerWeek;
    final blockFinder = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return widget is Material &&
          key is ValueKey<String> &&
          key.value.startsWith('week-calendar-wake-plan-block-');
    });

    expect(blockFinder, findsNWidgets(3));

    final blockRects = [
      for (var index = 0; index < 3; index++)
        tester.getRect(blockFinder.at(index)),
    ]..sort((left, right) => left.left.compareTo(right.left));

    expect(blockRects[0].right, lessThanOrEqualTo(blockRects[1].left));
    expect(blockRects[1].right, lessThanOrEqualTo(blockRects[2].left));
    expect(
      blockRects.last.right - blockRects.first.left,
      lessThanOrEqualTo(dayWidth),
    );
  });
}

WakePlan buildPlan({
  required String id,
  required CalendarDay targetDay,
  required TimeOfDayMinutes targetTime,
  Duration startOffset = const Duration(minutes: 60),
  Duration interval = const Duration(minutes: 5),
}) {
  final now = DateTime(2026, 7, 1, 12);

  return WakePlan(
    id: id,
    title: id,
    targetTime: targetTime,
    startOffset: startOffset,
    interval: interval,
    repeatRule: RepeatRule.oneTime(targetDay),
    isEnabled: true,
    status: WakePlanStatus.scheduled,
    soundId: 'default',
    vibrationEnabled: true,
    createdAt: now,
    updatedAt: now,
  );
}
