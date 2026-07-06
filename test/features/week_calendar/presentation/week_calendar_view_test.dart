import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/week_calendar/week_calendar.dart';
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
}
