import 'dart:ui' show SemanticsAction;

import 'package:calarm/features/wake_plan/ui/inline_wake_plan_editor.dart';
import 'package:calarm/features/week_calendar/model/week_calendar_interaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('direct time input emits a snapped same-day range', (
    tester,
  ) async {
    final draft = _draft(
      startAt: DateTime(2026, 7, 8, 9),
      endAt: DateTime(2026, 7, 8, 10),
    );
    final emitted = <WeekCalendarDraft>[];

    await _pumpEditor(
      tester,
      draft: draft,
      onRangeChanged: _rangeCallback(draft, emitted),
    );
    await _selectTime(
      tester,
      const ValueKey('inline-wake-plan-end-time'),
      hour: 10,
      minute: 12,
    );

    expect(emitted, hasLength(1));
    expect(emitted.single.startAt, DateTime(2026, 7, 8, 9));
    expect(emitted.single.endAt, DateTime(2026, 7, 8, 10, 10));
  });

  testWidgets('accepted snapping immediately governs future Save validity', (
    tester,
  ) async {
    final draft = _draft(
      startAt: DateTime(2026, 7, 8, 9),
      endAt: DateTime(2026, 7, 8, 10, 30),
    );
    final emitted = <WeekCalendarDraft>[];

    await _pumpEditor(
      tester,
      draft: draft,
      now: DateTime(2026, 7, 8, 10, 1),
      onRangeChanged: _rangeCallback(draft, emitted),
    );
    await _selectTime(
      tester,
      const ValueKey('inline-wake-plan-end-time'),
      hour: 10,
      minute: 2,
    );

    expect(emitted.single.endAt, DateTime(2026, 7, 8, 10));
    expect(find.text('Move the wake target to a future time.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('inline-wake-plan-save')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('direct input supports a 23:55 to 00:10 range', (tester) async {
    final draft = _draft(
      startAt: DateTime(2026, 7, 8, 23),
      endAt: DateTime(2026, 7, 9, 0, 30),
    );
    final emitted = <WeekCalendarDraft>[];

    await _pumpEditor(
      tester,
      draft: draft,
      onRangeChanged: _rangeCallback(draft, emitted),
    );
    await _selectTime(
      tester,
      const ValueKey('inline-wake-plan-start-time'),
      hour: 23,
      minute: 54,
    );
    await _selectTime(
      tester,
      const ValueKey('inline-wake-plan-end-time'),
      hour: 0,
      minute: 12,
    );

    expect(emitted.last.startAt, DateTime(2026, 7, 8, 23, 55));
    expect(emitted.last.endAt, DateTime(2026, 7, 9, 0, 10));
    expect(emitted.last.duration, const Duration(minutes: 15));
  });

  testWidgets('date input keeps an invalid intermediate pair repairable', (
    tester,
  ) async {
    final draft = _draft(
      startAt: DateTime(2026, 7, 8, 9),
      endAt: DateTime(2026, 7, 8, 10),
    );
    final emitted = <WeekCalendarDraft>[];

    await _pumpEditor(
      tester,
      draft: draft,
      onRangeChanged: _rangeCallback(draft, emitted),
    );
    await _selectDate(
      tester,
      const ValueKey('inline-wake-plan-end-date'),
      day: 9,
    );

    expect(emitted, isEmpty);
    expect(find.text('Choose a range no longer than 3 hours.'), findsOneWidget);

    await _selectDate(
      tester,
      const ValueKey('inline-wake-plan-start-date'),
      day: 9,
    );

    expect(emitted, hasLength(1));
    expect(emitted.single.startAt, DateTime(2026, 7, 9, 9));
    expect(emitted.single.endAt, DateTime(2026, 7, 9, 10));
    expect(find.text('Choose a range no longer than 3 hours.'), findsNothing);
  });

  testWidgets('invalid transient input shows guidance and can be repaired', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final draft = _draft(
      startAt: DateTime(2026, 7, 8, 9),
      endAt: DateTime(2026, 7, 8, 10),
    );
    final emitted = <WeekCalendarDraft>[];

    await _pumpEditor(
      tester,
      draft: draft,
      onRangeChanged: _rangeCallback(draft, emitted),
    );
    await _selectTime(
      tester,
      const ValueKey('inline-wake-plan-start-time'),
      hour: 11,
      minute: 0,
    );

    expect(emitted, isEmpty);
    expect(find.text('Start must be before end.'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('inline-wake-plan-guidance')))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('inline-wake-plan-save')),
          )
          .onPressed,
      isNull,
    );

    await _selectTime(
      tester,
      const ValueKey('inline-wake-plan-end-time'),
      hour: 12,
      minute: 0,
    );

    expect(emitted, hasLength(1));
    expect(emitted.single.startAt, DateTime(2026, 7, 8, 11));
    expect(emitted.single.endAt, DateTime(2026, 7, 8, 12));
    expect(find.text('Start must be before end.'), findsNothing);
    semantics.dispose();
  });

  testWidgets('past end disables Save without a timezone ambiguity claim', (
    tester,
  ) async {
    final draft = _draft(
      startAt: DateTime(2026, 7, 8, 9),
      endAt: DateTime(2026, 7, 8, 10),
    );

    await _pumpEditor(
      tester,
      draft: draft,
      now: DateTime(2026, 7, 8, 10),
      onRangeChanged: _acceptRange,
    );

    expect(find.text('Move the wake target to a future time.'), findsOneWidget);
    expect(find.textContaining('DST'), findsNothing);
    expect(find.textContaining('daylight'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('inline-wake-plan-save')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('date-time controls lock after submission', (tester) async {
    final draft = _draft(
      startAt: DateTime(2026, 7, 8, 9),
      endAt: DateTime(2026, 7, 8, 10),
    );

    await _pumpEditor(
      tester,
      draft: draft,
      submissionAttempted: true,
      onRangeChanged: _acceptRange,
    );

    for (final key in [
      const ValueKey('inline-wake-plan-start-date'),
      const ValueKey('inline-wake-plan-start-time'),
      const ValueKey('inline-wake-plan-end-date'),
      const ValueKey('inline-wake-plan-end-time'),
    ]) {
      final button = find.descendant(
        of: find.byKey(key),
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(button).onPressed, isNull);
    }
  });

  testWidgets('enabled picker semantics preserve their tap actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final draft = _draft(
      startAt: DateTime(2026, 7, 8, 9),
      endAt: DateTime(2026, 7, 8, 10),
    );

    await _pumpEditor(tester, draft: draft, onRangeChanged: _acceptRange);

    final node = tester.getSemantics(
      find.byKey(const ValueKey('inline-wake-plan-start-date')),
    );
    final data = node.getSemanticsData();
    expect(data.label, 'Start date 2026/7/8');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required WeekCalendarDraft draft,
  required InlineWakePlanRangeChange Function(DateTime, DateTime)
  onRangeChanged,
  DateTime? now,
  bool submissionAttempted = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InlineWakePlanEditor(
          startAt: draft.startAt,
          endAt: draft.endAt,
          now: now ?? DateTime(2026, 7, 8, 8),
          saving: false,
          submissionAttempted: submissionAttempted,
          onRangeChanged: onRangeChanged,
          onSave: () {},
          onCancel: () {},
        ),
      ),
    ),
  );
}

Future<void> _selectTime(
  WidgetTester tester,
  ValueKey<String> key, {
  required int hour,
  required int minute,
}) async {
  final picker = find.byKey(key);
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));
  final displayHour = hour == 0 ? 12 : (hour - 1) % 12 + 1;
  await tester.enterText(fields.at(0), displayHour.toString());
  await tester.enterText(fields.at(1), minute.toString().padLeft(2, '0'));
  await tester.tap(find.text(hour < 12 ? 'AM' : 'PM'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _selectDate(
  WidgetTester tester,
  ValueKey<String> key, {
  required int day,
}) async {
  final picker = find.byKey(key);
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(day.toString()).last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

InlineWakePlanRangeChange Function(DateTime, DateTime) _rangeCallback(
  WeekCalendarDraft original,
  List<WeekCalendarDraft> emitted,
) {
  return (startAt, endAt) {
    final edit = editWeekCalendarDraftRange(
      draft: original,
      startAt: startAt,
      endAt: endAt,
    );
    final next = edit.draft;
    if (next != null) {
      emitted.add(next);
      return InlineWakePlanRangeChange.accepted(
        startAt: next.startAt,
        endAt: next.endAt,
      );
    }
    final guidance = switch (edit.error!) {
      WeekCalendarDraftRangeError.notOrdered => 'Start must be before end.',
      WeekCalendarDraftRangeError.tooShort =>
        'Choose a range of at least 5 minutes.',
      WeekCalendarDraftRangeError.tooLong =>
        'Choose a range no longer than 3 hours.',
    };
    return InlineWakePlanRangeChange.rejected(guidance);
  };
}

InlineWakePlanRangeChange _acceptRange(DateTime startAt, DateTime endAt) {
  return InlineWakePlanRangeChange.accepted(startAt: startAt, endAt: endAt);
}

WeekCalendarDraft _draft({required DateTime startAt, required DateTime endAt}) {
  return WeekCalendarDraft(
    id: 'draft',
    startAt: startAt,
    endAt: endAt,
    createdAt: DateTime(2026, 7, 8, 8),
  );
}
