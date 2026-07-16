import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:calarm/features/wake_plan/ui/wake_plan_detail_sheet.dart';
import 'package:calarm/features/week_calendar/week_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('asks confirmation before deleting a one-time wake plan', (
    tester,
  ) async {
    var deleted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WakePlanDetailSheet(
            target: WeekCalendarWakePlanTapTarget(
              wakePlan: _plan(repeatRule: RepeatRule.oneTime(_targetDay)),
              targetDay: _targetDay,
            ),
            now: DateTime(2026, 7, 8, 5, 30),
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async {
              deleted = true;
              return _successResult();
            },
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (_) async => _successResult(),
            loadOccurrences: _emptyOccurrences,
            onSetOccurrenceEnabled: _unexpectedOccurrenceToggle,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete wake plan?'), findsOneWidget);
    expect(find.text('This removes the selected wake plan.'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(deleted, isFalse);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });

  testWidgets('preserves repeating wake plan delete confirmation copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WakePlanDetailSheet(
            target: WeekCalendarWakePlanTapTarget(
              wakePlan: _plan(),
              targetDay: _targetDay,
            ),
            now: DateTime(2026, 7, 8, 5, 30),
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (_) async => _successResult(),
            loadOccurrences: _emptyOccurrences,
            onSetOccurrenceEnabled: _unexpectedOccurrenceToggle,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete repeating wake plan?'), findsOneWidget);
    expect(
      find.text(
        'This removes future alarms for every repeat of this wake plan.',
      ),
      findsOneWidget,
    );
  });

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
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (_) async => _successResult(),
            loadOccurrences: _emptyOccurrences,
            onSetOccurrenceEnabled: _unexpectedOccurrenceToggle,
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
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (plan) async {
              restored = plan;
              return _successResult();
            },
            loadOccurrences: _emptyOccurrences,
            onSetOccurrenceEnabled: _unexpectedOccurrenceToggle,
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
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async => _successResult(),
            onSkipNext: (plan) async {
              skipped = plan;
              return _successResult();
            },
            onUndoSkipNext: (_) async => _successResult(),
            loadOccurrences: _emptyOccurrences,
            onSetOccurrenceEnabled: _unexpectedOccurrenceToggle,
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
            clock: () => DateTime(2026, 7, 8, 5, 30),
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (plan) async {
              restored = plan;
              return _successResult();
            },
            loadOccurrences: _emptyOccurrences,
            onSetOccurrenceEnabled: _unexpectedOccurrenceToggle,
          ),
        ),
      ),
    );

    expect(find.text('Skipping next target on 2026-07-08'), findsOneWidget);

    await tester.tap(find.text('Undo skip'));
    await tester.pumpAndSettle();

    expect(restored?.id, 'plan-1');
  });

  testWidgets('uses the injected clock for one-time edit eligibility', (
    tester,
  ) async {
    var edited = false;
    final now = DateTime(2026, 7, 8, 5, 30);
    final targetDay = CalendarDay(year: 2026, month: 7, day: 9);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WakePlanDetailSheet(
            target: WeekCalendarWakePlanTapTarget(
              wakePlan: _plan(repeatRule: RepeatRule.oneTime(targetDay)),
              targetDay: targetDay,
            ),
            now: now,
            clock: () => now,
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async {
              edited = true;
              return _successResult();
            },
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (_) async => _successResult(),
            loadOccurrences: _emptyOccurrences,
            onSetOccurrenceEnabled: _unexpectedOccurrenceToggle,
          ),
        ),
      ),
    );

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

    expect(edited, isTrue);
  });

  testWidgets('detail edit validation follows the live injected clock', (
    tester,
  ) async {
    final initialNow = DateTime(2026, 7, 8, 5, 30);
    var currentNow = initialNow;
    var clockCalls = 0;
    var edited = false;
    DateTime clock() {
      clockCalls += 1;
      return currentNow;
    }

    final targetDay = CalendarDay(year: 2026, month: 7, day: 9);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WakePlanDetailSheet(
            target: WeekCalendarWakePlanTapTarget(
              wakePlan: _plan(repeatRule: RepeatRule.oneTime(targetDay)),
              targetDay: targetDay,
            ),
            now: initialNow,
            clock: clock,
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async {
              edited = true;
              return _successResult();
            },
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (_) async => _successResult(),
            loadOccurrences: _emptyOccurrences,
            onSetOccurrenceEnabled: _unexpectedOccurrenceToggle,
          ),
        ),
      ),
    );

    currentNow = DateTime(2026, 7, 10, 5, 30);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit wake plan'), findsOneWidget);
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
    expect(edited, isFalse);
    expect(clockCalls, greaterThan(0));
  });

  testWidgets('blocks one-time edit when the injected clock is past target', (
    tester,
  ) async {
    var edited = false;
    final now = DateTime(2026, 7, 10, 5, 30);
    final targetDay = CalendarDay(year: 2026, month: 7, day: 9);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WakePlanDetailSheet(
            target: WeekCalendarWakePlanTapTarget(
              wakePlan: _plan(repeatRule: RepeatRule.oneTime(targetDay)),
              targetDay: targetDay,
            ),
            now: now,
            clock: () => now,
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async {
              edited = true;
              return _successResult();
            },
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (_) async => _successResult(),
            loadOccurrences: _emptyOccurrences,
            onSetOccurrenceEnabled: _unexpectedOccurrenceToggle,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit wake plan'), findsOneWidget);
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
    expect(edited, isFalse);
  });

  testWidgets(
    'lists future eligible occurrences including the final alarm and toggles it',
    (tester) async {
      final now = DateTime(2026, 7, 8, 5, 30);
      final plan = _plan();
      final finalOccurrence = _occurrence(
        id: 'final',
        scheduledAt: DateTime(2026, 7, 8, 7),
      );
      AlarmOccurrence? toggled;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WakePlanDetailSheet(
              target: WeekCalendarWakePlanTapTarget(
                wakePlan: plan,
                targetDay: _targetDay,
              ),
              now: now,
              clock: () => now,
              defaults: AppSettings.initial(),
              existingWakePlans: const [],
              onEdit: (_) async => _successResult(),
              onDelete: (_) async => _successResult(),
              onSkipNext: (_) async => _successResult(),
              onUndoSkipNext: (_) async => _successResult(),
              loadOccurrences: (_) async => [
                _occurrence(id: 'past', scheduledAt: DateTime(2026, 7, 8, 5)),
                _occurrence(id: 'future', scheduledAt: DateTime(2026, 7, 8, 6)),
                finalOccurrence,
                _occurrence(
                  id: 'ringing',
                  scheduledAt: DateTime(2026, 7, 8, 6, 30),
                  status: AlarmOccurrenceStatus.ringing,
                  firedAt: now,
                ),
                _occurrence(
                  id: 'dismissed',
                  scheduledAt: DateTime(2026, 7, 8, 6, 45),
                  status: AlarmOccurrenceStatus.dismissed,
                  firedAt: now,
                  dismissedAt: now,
                ),
              ],
              onSetOccurrenceEnabled:
                  ({
                    required wakePlanId,
                    required occurrenceId,
                    required enabled,
                  }) async {
                    expect(wakePlanId, plan.id);
                    expect(occurrenceId, finalOccurrence.id);
                    expect(enabled, isFalse);
                    toggled = finalOccurrence.copyWith(
                      status: AlarmOccurrenceStatus.userDisabled,
                      platformAlarmId: null,
                      updatedAt: now,
                    );
                    return AlarmOccurrenceToggleResult.success(
                      status: AlarmOccurrenceToggleStatus.disabled,
                      occurrence: toggled!,
                    );
                  },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('occurrence-toggle-future')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('occurrence-toggle-final')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('occurrence-toggle-past')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('occurrence-toggle-ringing')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('occurrence-toggle-dismissed')),
        findsNothing,
      );

      final finalToggle = find.byKey(const ValueKey('occurrence-toggle-final'));
      await tester.ensureVisible(finalToggle);
      await tester.tap(finalToggle);
      await tester.pumpAndSettle();

      expect(toggled?.status, AlarmOccurrenceStatus.userDisabled);
      expect(tester.widget<SwitchListTile>(finalToggle).value, isFalse);
      expect(find.text('Off'), findsOneWidget);
    },
  );

  testWidgets('keeps occurrence state and shows a useful toggle error', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 8, 5, 30);
    final occurrence = _occurrence(
      id: 'future',
      scheduledAt: DateTime(2026, 7, 8, 6),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WakePlanDetailSheet(
            target: WeekCalendarWakePlanTapTarget(
              wakePlan: _plan(),
              targetDay: _targetDay,
            ),
            now: now,
            clock: () => now,
            defaults: AppSettings.initial(),
            existingWakePlans: const [],
            onEdit: (_) async => _successResult(),
            onDelete: (_) async => _successResult(),
            onSkipNext: (_) async => _successResult(),
            onUndoSkipNext: (_) async => _successResult(),
            loadOccurrences: (_) async => [occurrence],
            onSetOccurrenceEnabled:
                ({
                  required wakePlanId,
                  required occurrenceId,
                  required enabled,
                }) async {
                  return AlarmOccurrenceToggleResult.failure(
                    status: AlarmOccurrenceToggleStatus.cancelFailed,
                    occurrence: occurrence,
                    warning: 'The native alarm could not be turned off.',
                  );
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('occurrence-toggle-future'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(
      find.text('The native alarm could not be turned off.'),
      findsOneWidget,
    );
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

AlarmOccurrence _occurrence({
  required String id,
  required DateTime scheduledAt,
  AlarmOccurrenceStatus status = AlarmOccurrenceStatus.scheduled,
  DateTime? firedAt,
  DateTime? dismissedAt,
}) {
  return AlarmOccurrence(
    id: id,
    wakePlanId: 'plan-1',
    scheduledAt: DateMinute.fromDateTime(scheduledAt),
    status: status,
    platformAlarmId: status == AlarmOccurrenceStatus.scheduled
        ? 'native-$id'
        : null,
    firedAt: firedAt,
    dismissedAt: dismissedAt,
    createdAt: scheduledAt.subtract(const Duration(days: 1)),
    updatedAt: scheduledAt.subtract(const Duration(days: 1)),
  );
}

Future<List<AlarmOccurrence>> _emptyOccurrences(String wakePlanId) async {
  return const [];
}

Future<AlarmOccurrenceToggleResult> _unexpectedOccurrenceToggle({
  required String wakePlanId,
  required String occurrenceId,
  required bool enabled,
}) {
  throw StateError('No occurrence toggle was expected in this test.');
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
