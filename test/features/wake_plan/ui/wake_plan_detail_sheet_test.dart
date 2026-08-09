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
      _harness(
        target: _target(
          wakePlan: _plan(repeatRule: RepeatRule.oneTime(_targetDay)),
        ),
        onDelete: (_) async {
          deleted = true;
          return _successResult();
        },
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
    await tester.pumpWidget(_harness(target: _target(wakePlan: _plan())));

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

  testWidgets('does not offer occurrence actions for a one-time plan', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        target: _target(
          wakePlan: _plan(repeatRule: RepeatRule.oneTime(_targetDay)),
        ),
      ),
    );

    expect(find.text('Delete this occurrence…'), findsNothing);
    expect(find.text('Move this occurrence…'), findsNothing);
  });

  testWidgets('skips this occurrence only when choosing "This event only"', (
    tester,
  ) async {
    WakePlan? skippedPlan;
    CalendarDay? skippedDay;

    await tester.pumpWidget(
      _harness(
        target: _target(
          wakePlan: _plan(),
          targetDay: CalendarDay(year: 2026, month: 7, day: 8),
        ),
        onSkipOccurrence: (plan, day) async {
          skippedPlan = plan;
          skippedDay = day;
          return _successResult();
        },
      ),
    );

    await tester.tap(find.text('Delete this occurrence…'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this occurrence?'), findsOneWidget);
    await tester.tap(find.text('This event only'));
    await tester.pumpAndSettle();

    expect(skippedPlan?.id, 'plan-1');
    expect(skippedDay, CalendarDay(year: 2026, month: 7, day: 8));
  });

  testWidgets(
    'deletes this and following occurrences when choosing that scope',
    (tester) async {
      WakePlan? truncatedPlan;
      CalendarDay? fromDay;

      await tester.pumpWidget(
        _harness(
          target: _target(
            wakePlan: _plan(),
            targetDay: CalendarDay(year: 2026, month: 7, day: 8),
          ),
          onDeleteThisAndFollowing: (plan, day) async {
            truncatedPlan = plan;
            fromDay = day;
            return _successResult();
          },
        ),
      );

      await tester.tap(find.text('Delete this occurrence…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This and following events'));
      await tester.pumpAndSettle();

      expect(truncatedPlan?.id, 'plan-1');
      expect(fromDay, CalendarDay(year: 2026, month: 7, day: 8));
    },
  );

  testWidgets('lists existing exceptions and undoes them', (tester) async {
    WakePlan? undonePlan;
    CalendarDay? undoneDay;
    final skippedDay = CalendarDay(year: 2026, month: 7, day: 8);
    final exception = WakePlanOccurrenceException(
      wakePlanId: 'plan-1',
      originalDay: skippedDay,
      type: WakePlanOccurrenceExceptionType.skipped,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

    await tester.pumpWidget(
      _harness(
        target: _target(wakePlan: _plan()),
        existingExceptions: [exception],
        onUndoSkipOccurrence: (plan, day) async {
          undonePlan = plan;
          undoneDay = day;
          return _successResult();
        },
      ),
    );

    expect(find.text('Exceptions'), findsOneWidget);
    expect(find.text('Skipped on 2026-07-08'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(undonePlan?.id, 'plan-1');
    expect(undoneDay, skippedDay);
  });

  testWidgets('uses the injected clock for one-time edit eligibility', (
    tester,
  ) async {
    var edited = false;
    final now = DateTime(2026, 7, 8, 5, 30);
    final targetDay = CalendarDay(year: 2026, month: 7, day: 9);

    await tester.pumpWidget(
      _harness(
        target: _target(
          wakePlan: _plan(repeatRule: RepeatRule.oneTime(targetDay)),
          targetDay: targetDay,
        ),
        now: now,
        clock: () => now,
        onEdit: (_) async {
          edited = true;
          return _successResult();
        },
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
      _harness(
        target: _target(
          wakePlan: _plan(repeatRule: RepeatRule.oneTime(targetDay)),
          targetDay: targetDay,
        ),
        now: initialNow,
        clock: clock,
        onEdit: (_) async {
          edited = true;
          return _successResult();
        },
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

  testWidgets('next-fire label follows the live injected clock', (
    tester,
  ) async {
    final initialNow = DateTime(2026, 7, 8, 5, 30);
    final liveNow = DateTime(2026, 7, 8, 8);

    await tester.pumpWidget(
      _harness(
        target: _target(
          wakePlan: _plan(repeatRule: RepeatRule.oneTime(_targetDay)),
        ),
        now: initialNow,
        clock: () => liveNow,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No future alarm'), findsOneWidget);
  });

  testWidgets('blocks one-time edit when the injected clock is past target', (
    tester,
  ) async {
    var edited = false;
    final now = DateTime(2026, 7, 10, 5, 30);
    final targetDay = CalendarDay(year: 2026, month: 7, day: 9);

    await tester.pumpWidget(
      _harness(
        target: _target(
          wakePlan: _plan(repeatRule: RepeatRule.oneTime(targetDay)),
          targetDay: targetDay,
        ),
        now: now,
        clock: () => now,
        onEdit: (_) async {
          edited = true;
          return _successResult();
        },
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
        _harness(
          target: _target(wakePlan: plan),
          now: now,
          clock: () => now,
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

  testWidgets('removes a toggle when an open sheet crosses its alarm time', (
    tester,
  ) async {
    var liveNow = DateTime(2026, 7, 8, 5, 30);
    final occurrence = _occurrence(
      id: 'boundary',
      scheduledAt: DateTime(2026, 7, 8, 5, 31),
    );

    await tester.pumpWidget(
      _harness(
        target: _target(wakePlan: _plan()),
        now: liveNow,
        clock: () => liveNow,
        loadOccurrences: (_) async => [occurrence],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('occurrence-toggle-boundary')),
      findsOneWidget,
    );

    liveNow = DateTime(2026, 7, 8, 5, 31);
    await tester.pump(const Duration(minutes: 1));

    expect(
      find.byKey(const ValueKey('occurrence-toggle-boundary')),
      findsNothing,
    );
    expect(find.text('No future alarms are available.'), findsOneWidget);
  });

  testWidgets('re-arms eligibility refresh when the clock moves backward', (
    tester,
  ) async {
    var liveNow = DateTime(2026, 7, 8, 5, 30);
    final first = _occurrence(
      id: 'first-boundary',
      scheduledAt: DateTime(2026, 7, 8, 5, 31),
    );
    final second = _occurrence(
      id: 'second-boundary',
      scheduledAt: DateTime(2026, 7, 8, 5, 32),
    );

    await tester.pumpWidget(
      _harness(
        target: _target(wakePlan: _plan()),
        now: liveNow,
        clock: () => liveNow,
        loadOccurrences: (_) async => [first, second],
      ),
    );
    await tester.pump();
    await tester.pump();

    liveNow = DateTime(2026, 7, 8, 5, 29);
    await tester.pump(const Duration(minutes: 1));
    expect(
      find.byKey(const ValueKey('occurrence-toggle-first-boundary')),
      findsOneWidget,
    );

    liveNow = DateTime(2026, 7, 8, 5, 31);
    await tester.pump(const Duration(minutes: 2));
    expect(
      find.byKey(const ValueKey('occurrence-toggle-first-boundary')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('occurrence-toggle-second-boundary')),
      findsOneWidget,
    );
  });

  testWidgets('keeps occurrence state and shows a useful toggle error', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 8, 5, 30);
    final occurrence = _occurrence(
      id: 'future',
      scheduledAt: DateTime(2026, 7, 8, 6),
    );

    await tester.pumpWidget(
      _harness(
        target: _target(wakePlan: _plan()),
        now: now,
        clock: () => now,
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

  testWidgets(
    'definite enable rejection stays visible off and can be retried',
    (tester) async {
      final now = DateTime(2026, 7, 8, 5, 30);
      final disabled = _occurrence(
        id: 'retryable',
        scheduledAt: DateTime(2026, 7, 8, 6),
        status: AlarmOccurrenceStatus.userDisabled,
      );
      var attempts = 0;

      await tester.pumpWidget(
        _harness(
          target: _target(wakePlan: _plan()),
          now: now,
          clock: () => now,
          loadOccurrences: (_) async => [disabled],
          onSetOccurrenceEnabled:
              ({
                required wakePlanId,
                required occurrenceId,
                required enabled,
              }) async {
                attempts += 1;
                expect(occurrenceId, disabled.id);
                expect(enabled, isTrue);
                if (attempts == 1) {
                  return AlarmOccurrenceToggleResult.failure(
                    status: AlarmOccurrenceToggleStatus.scheduleFailed,
                    occurrence: disabled,
                    warning: 'The native alarm could not be turned on.',
                  );
                }
                return AlarmOccurrenceToggleResult.success(
                  status: AlarmOccurrenceToggleStatus.enabled,
                  occurrence: disabled.copyWith(
                    status: AlarmOccurrenceStatus.scheduled,
                    platformAlarmId: 'native-retryable',
                    updatedAt: now,
                  ),
                );
              },
        ),
      );
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('occurrence-toggle-retryable'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(toggle, findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(find.text('Off'), findsOneWidget);
      expect(
        find.text('The native alarm could not be turned on.'),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(find.text('On'), findsOneWidget);
    },
  );
}

final _targetDay = CalendarDay(year: 2026, month: 7, day: 8);

WeekCalendarWakePlanTapTarget _target({
  required WakePlan wakePlan,
  CalendarDay? targetDay,
}) {
  return WeekCalendarWakePlanTapTarget(
    wakePlan: wakePlan,
    targetDay: targetDay ?? _targetDay,
  );
}

Widget _harness({
  required WeekCalendarWakePlanTapTarget target,
  DateTime? now,
  DateTime Function()? clock,
  List<WakePlanOccurrenceException> existingExceptions = const [],
  WakePlanEditSave? onEdit,
  WakePlanDelete? onDelete,
  WakePlanOccurrenceSkip? onSkipOccurrence,
  WakePlanOccurrenceSkip? onUndoSkipOccurrence,
  WakePlanOccurrenceMove? onMoveOccurrence,
  WakePlanDeleteThisAndFollowing? onDeleteThisAndFollowing,
  WakePlanOccurrenceLoader? loadOccurrences,
  WakePlanOccurrenceToggle? onSetOccurrenceEnabled,
}) {
  final resolvedNow = now ?? DateTime(2026, 7, 8, 5, 30);
  return MaterialApp(
    home: Scaffold(
      body: WakePlanDetailSheet(
        target: target,
        now: resolvedNow,
        clock: clock ?? (() => resolvedNow),
        defaults: AppSettings.initial(),
        existingWakePlans: const [],
        existingExceptions: existingExceptions,
        onEdit: onEdit ?? (_) async => _successResult(),
        onDelete: onDelete ?? (_) async => _successResult(),
        onSkipOccurrence: onSkipOccurrence ?? (_, _) async => _successResult(),
        onUndoSkipOccurrence:
            onUndoSkipOccurrence ?? (_, _) async => _successResult(),
        onMoveOccurrence:
            onMoveOccurrence ??
            ({
              required wakePlan,
              required fromDay,
              required toDay,
              toTime,
            }) async => _successResult(),
        onDeleteThisAndFollowing:
            onDeleteThisAndFollowing ?? (_, _) async => _successResult(),
        loadOccurrences: loadOccurrences ?? _emptyOccurrences,
        onSetOccurrenceEnabled:
            onSetOccurrenceEnabled ?? _unexpectedOccurrenceToggle,
      ),
    ),
  );
}

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
