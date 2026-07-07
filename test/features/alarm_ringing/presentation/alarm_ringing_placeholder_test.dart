import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/alarm_ringing/application/alarm_ringing_controller.dart';
import 'package:calarm/features/alarm_ringing/presentation/alarm_ringing_placeholder.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders ringing metadata and only the current stop action', (
    tester,
  ) async {
    var stopped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlarmRingingScreen(
            snapshot: _snapshot(),
            now: DateTime(2026, 7, 6, 6, 50),
            onStop: () async {
              stopped = true;
              return AlarmDismissResult.dismissed;
            },
          ),
        ),
      ),
    );

    expect(find.text('Alarm ringing'), findsOneWidget);
    expect(find.text('Current time'), findsOneWidget);
    expect(find.text('07/06 06:50'), findsOneWidget);
    expect(find.text('Wake target'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('Alarm'), findsOneWidget);
    expect(find.text('2 of 4'), findsOneWidget);
    expect(find.text('Next scheduled'), findsOneWidget);
    expect(find.text('07/06 06:55'), findsOneWidget);
    expect(find.text('Stop current alarm'), findsOneWidget);
    expect(find.textContaining('Snooze'), findsNothing);
    expect(find.textContaining('Skip'), findsNothing);
    expect(find.textContaining('Stop all'), findsNothing);
    expect(find.textContaining('Wake up'), findsNothing);

    await tester.tap(find.text('Stop current alarm'));
    await tester.pumpAndSettle();

    expect(stopped, isTrue);
    expect(find.text('Current alarm stopped.'), findsOneWidget);
  });

  testWidgets('keeps stop action retryable when stop throws', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlarmRingingScreen(
            snapshot: _snapshot(),
            now: DateTime(2026, 7, 6, 6, 50),
            onStop: () async {
              attempts += 1;
              throw StateError('native bridge unavailable');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Stop current alarm'));
    await tester.pump();
    await tester.pump();

    expect(attempts, 1);
    expect(
      find.text('Could not stop the current alarm. Try again.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });
}

AlarmRingingSnapshot _snapshot() {
  final createdAt = DateTime(2026, 7, 6, 5);
  final day = CalendarDay(year: 2026, month: 7, day: 6);
  final plan = WakePlan(
    id: 'plan-1',
    title: 'Morning',
    targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
    startOffset: const Duration(minutes: 15),
    interval: const Duration(minutes: 5),
    repeatRule: RepeatRule.oneTime(day),
    isEnabled: true,
    status: WakePlanStatus.scheduled,
    soundId: defaultWakePlanSoundId,
    vibrationEnabled: true,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
  return AlarmRingingSnapshot(
    wakePlan: plan,
    currentOccurrence: AlarmOccurrence(
      id: 'plan-1:20640:410',
      wakePlanId: plan.id,
      scheduledAt: DateMinute(
        day: day,
        time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
      ),
      status: AlarmOccurrenceStatus.ringing,
      platformAlarmId: 'native-current',
      firedAt: DateTime(2026, 7, 6, 6, 50),
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
    occurrenceIndex: 2,
    occurrenceCount: 4,
    nextScheduledAt: DateMinute(
      day: day,
      time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
    ),
  );
}
