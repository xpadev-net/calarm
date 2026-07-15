import 'dart:ui' show PointerDeviceKind;

import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/week_calendar/week_calendar.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders date header, time axis, and empty calendar grid without copy',
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
      expect(find.text('No wake plans scheduled for this week'), findsNothing);
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

  testWidgets('now-only updates preserve the current page and scroll offset', (
    tester,
  ) async {
    var now = DateTime(2026, 7, 8, 7, 30);
    late StateSetter updateHarness;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHarness = setState;
              return WeekCalendarView(now: now);
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    final pageController = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    final visibleScrollView = find.byType(SingleChildScrollView).hitTestable();
    final scrollController = tester
        .widget<SingleChildScrollView>(visibleScrollView)
        .controller!;
    scrollController.jumpTo(700);
    await tester.pump();
    final pageBefore = pageController.page;
    final offsetBefore = scrollController.offset;

    updateHarness(() {
      now = DateTime(2026, 7, 8, 7, 31);
    });
    await tester.pump();

    expect(pageController.page, pageBefore);
    expect(scrollController.offset, offsetBefore);
    expect(
      tester.widget<WeekCalendarView>(find.byType(WeekCalendarView)).now,
      now,
    );
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

  testWidgets('renders an outlined cross-midnight draft with both handles', (
    tester,
  ) async {
    final draft = WeekCalendarDraft(
      id: 'draft-1',
      startAt: DateTime(2026, 7, 8, 23, 30),
      endAt: DateTime(2026, 7, 9, 0, 30),
      createdAt: DateTime(2026, 7, 8, 5, 30),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekCalendarView(
            now: DateTime(2026, 7, 8, 7, 30),
            initialWeek: WeekRange(
              start: CalendarDay(year: 2026, month: 7, day: 6),
            ),
            draft: draft,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('week-calendar-draft-start-handle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('week-calendar-draft-end-handle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('week-calendar-draft-segment-draft-1-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('week-calendar-draft-segment-draft-1-3')),
      findsOneWidget,
    );
  });

  testWidgets('cross-day body drag restores one-finger vertical scrolling', (
    tester,
  ) async {
    var draft = WeekCalendarDraft(
      id: 'cross-day-draft',
      startAt: DateTime(2026, 7, 8, 23, 30),
      endAt: DateTime(2026, 7, 9, 0, 30),
      createdAt: DateTime(2026, 7, 8, 5, 30),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => WeekCalendarView(
              now: DateTime(2026, 7, 8, 23, 30),
              initialWeek: WeekRange(
                start: CalendarDay(year: 2026, month: 7, day: 6),
              ),
              draft: draft,
              onDraftChanged: (value) => setState(() => draft = value),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final body = find.byKey(
      const ValueKey('week-calendar-draft-body-cross-day-draft-2'),
    );
    final dayWidth = tester.getSize(find.byType(CustomPaint).last).width / 7;
    await _rawDragFrom(
      tester,
      tester.getCenter(body),
      Offset(dayWidth, 0),
      pointer: 71,
    );
    expect(draft.startAt, DateTime(2026, 7, 9, 23, 30));
    expect(draft.endAt, DateTime(2026, 7, 10, 0, 30));

    final scrollController = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    scrollController.jumpTo(600);
    await tester.pump();
    final surface = find.byKey(const ValueKey('week-calendar-pinch-surface'));
    await tester.dragFrom(
      tester.getTopLeft(surface) + const Offset(24, 200),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled cross-day body drag restores vertical scrolling', (
    tester,
  ) async {
    var draft = WeekCalendarDraft(
      id: 'cancelled-cross-day-draft',
      startAt: DateTime(2026, 7, 8, 23, 30),
      endAt: DateTime(2026, 7, 9, 0, 30),
      createdAt: DateTime(2026, 7, 8, 5, 30),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => WeekCalendarView(
              now: DateTime(2026, 7, 8, 23, 30),
              initialWeek: WeekRange(
                start: CalendarDay(year: 2026, month: 7, day: 6),
              ),
              draft: draft,
              onDraftChanged: (value) => setState(() => draft = value),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final body = find.byKey(
      const ValueKey('week-calendar-draft-body-cancelled-cross-day-draft-2'),
    );
    final dayWidth = tester.getSize(find.byType(CustomPaint).last).width / 7;
    final gesture = await tester.createGesture(pointer: 72);
    final start = tester.getCenter(body);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(start + Offset(dayWidth, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();

    final scrollController = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    scrollController.jumpTo(600);
    await tester.pump();
    final surface = find.byKey(const ValueKey('week-calendar-pinch-surface'));
    await tester.dragFrom(
      tester.getTopLeft(surface) + const Offset(24, 200),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(600));
    expect(tester.takeException(), isNull);
  });

  for (final hourHeight in const [52.0, 36.0]) {
    testWidgets(
      'raw pointers move body and resize both handles at $hourHeight px/hour',
      (tester) async {
        var draft = WeekCalendarDraft(
          id: 'draft-1',
          startAt: DateTime(2026, 7, 8, 10),
          endAt: DateTime(2026, 7, 8, 11),
          createdAt: DateTime(2026, 7, 8, 5, 30),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => WeekCalendarView(
                  now: DateTime(2026, 7, 8, 7, 30),
                  initialWeek: WeekRange(
                    start: CalendarDay(year: 2026, month: 7, day: 6),
                  ),
                  draft: draft,
                  hourHeight: hourHeight,
                  onDraftChanged: (value) => setState(() => draft = value),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _rawDrag(
          tester,
          find.byKey(const ValueKey('week-calendar-draft-start-handle')),
          const Offset(0, 1000),
          pointer: 51,
        );
        expect(draft.duration, weekCalendarDraftMinimumDuration);

        final body = find.byKey(
          const ValueKey('week-calendar-draft-body-draft-1-2'),
        );
        final bodyRect = tester.getRect(body);
        final dayWidth =
            tester.getSize(find.byType(CustomPaint).last).width / 7;
        await _rawDragFrom(
          tester,
          Offset(bodyRect.right - 4, bodyRect.top + 5),
          Offset(dayWidth, 0),
          pointer: 52,
        );
        expect(draft.startAt, DateTime(2026, 7, 9, 10, 55));
        expect(draft.endAt, DateTime(2026, 7, 9, 11));
        expect(draft.duration, weekCalendarDraftMinimumDuration);

        await _rawDrag(
          tester,
          find.byKey(const ValueKey('week-calendar-draft-start-handle')),
          const Offset(0, -30),
          pointer: 53,
        );
        expect(draft.startAt.isBefore(DateTime(2026, 7, 9, 10, 55)), isTrue);
        expect(draft.duration, greaterThan(weekCalendarDraftMinimumDuration));
        expect(draft.startAt.minute % 5, 0);
        final afterStartResize = draft.duration;

        await _rawDrag(
          tester,
          find.byKey(const ValueKey('week-calendar-draft-end-handle')),
          const Offset(0, 30),
          pointer: 54,
        );
        expect(draft.duration, greaterThan(afterStartResize));
        expect(draft.endAt.minute % 5, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final visibleDays in const [3, DateTime.daysPerWeek]) {
    testWidgets('body drag remains visible at both $visibleDays-day edges', (
      tester,
    ) async {
      final startDay = CalendarDay(year: 2026, month: 7, day: 6);
      late StateSetter update;
      var draft = WeekCalendarDraft(
        id: 'edge-draft',
        startAt: DateTime(2026, 7, 6, 10),
        endAt: DateTime(2026, 7, 6, 11),
        createdAt: DateTime(2026, 7, 6, 5),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return WeekCalendarView(
                  now: DateTime(2026, 7, 6, 7),
                  visibleDays: visibleDays,
                  initialWeek: WeekRange(
                    start: startDay,
                    visibleDays: visibleDays,
                  ),
                  draft: draft,
                  onDraftChanged: (value) => setState(() => draft = value),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var body = find.byKey(
        const ValueKey('week-calendar-draft-body-edge-draft-0'),
      );
      var rect = tester.getRect(body);
      await _rawDragFrom(
        tester,
        Offset(rect.left + 6, rect.center.dy),
        const Offset(-1000, 0),
        pointer: 61,
      );
      expect(draft.startAt, startDay.startOfDay);
      expect(draft.endAt, startDay.startOfDay.add(const Duration(hours: 1)));
      expect(body, findsOneWidget);

      final rangeEnd = startDay.addDays(visibleDays).startOfDay;
      update(() {
        draft = WeekCalendarDraft(
          id: 'edge-draft',
          startAt: rangeEnd.subtract(const Duration(hours: 2)),
          endAt: rangeEnd.subtract(const Duration(hours: 1)),
          createdAt: DateTime(2026, 7, 6, 5),
        );
      });
      await tester.pump();
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!
          .jumpTo(20 * 52);
      await tester.pump();
      body = find.byKey(
        ValueKey('week-calendar-draft-body-edge-draft-${visibleDays - 1}'),
      );
      rect = tester.getRect(body);
      await _rawDragFrom(
        tester,
        Offset(rect.left + 6, rect.center.dy),
        const Offset(1000, 0),
        pointer: 62,
      );
      expect(draft.endAt, rangeEnd);
      expect(draft.startAt, rangeEnd.subtract(const Duration(hours: 1)));
      expect(body, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a draft disables paging while leaving pinch zoom available', (
    tester,
  ) async {
    var hourHeight = 52.0;
    final draft = WeekCalendarDraft(
      id: 'draft-1',
      startAt: DateTime(2026, 7, 8, 10),
      endAt: DateTime(2026, 7, 8, 11),
      createdAt: DateTime(2026, 7, 8, 5, 30),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => WeekCalendarView(
              now: DateTime(2026, 7, 8, 7, 30),
              draft: draft,
              hourHeight: hourHeight,
              onHourHeightChanged: (value) {
                setState(() => hourHeight = value);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    final surface = find.byKey(const ValueKey('week-calendar-pinch-surface'));
    final center = tester.getCenter(surface);
    final first = await tester.createGesture(pointer: 31);
    final second = await tester.createGesture(pointer: 32);
    await first.down(center - const Offset(0, 40));
    await second.down(center + const Offset(0, 40));
    await first.moveTo(center - const Offset(0, 120));
    await second.moveTo(center + const Offset(0, 120));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(hourHeight, greaterThan(52));
    expect(
      find.byKey(const ValueKey('week-calendar-draft-start-handle')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'draft manipulation owns scroll and pinch interrupts it without loss',
    (tester) async {
      var hourHeight = 52.0;
      var draft = WeekCalendarDraft(
        id: 'draft-1',
        startAt: DateTime(2026, 7, 8, 10),
        endAt: DateTime(2026, 7, 8, 12),
        createdAt: DateTime(2026, 7, 8, 5, 30),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => WeekCalendarView(
                now: DateTime(2026, 7, 8, 7, 30),
                initialWeek: WeekRange(
                  start: CalendarDay(year: 2026, month: 7, day: 6),
                ),
                draft: draft,
                hourHeight: hourHeight,
                onDraftChanged: (value) => setState(() => draft = value),
                onHourHeightChanged: (value) {
                  setState(() => hourHeight = value);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollController = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      final initialScroll = scrollController.offset;
      final body = find.byKey(
        const ValueKey('week-calendar-draft-body-draft-1-2'),
      );
      final center = tester.getCenter(body);
      final first = await tester.createGesture(pointer: 41);
      await first.down(center);
      await tester.pump();
      await first.moveTo(center + const Offset(0, -20));
      await tester.pump();
      await first.moveTo(center + const Offset(0, -40));
      await tester.pump();
      expect(scrollController.offset, initialScroll);
      expect(draft.startAt, isNot(DateTime(2026, 7, 8, 10)));
      expect(draft.duration, const Duration(hours: 2));

      final second = await tester.createGesture(pointer: 42);
      await second.down(center + const Offset(0, 80));
      await tester.pump();
      final startAfterTakeover = draft.startAt;
      final endAfterTakeover = draft.endAt;
      await first.moveTo(center + const Offset(0, -120));
      await second.moveTo(center + const Offset(0, 180));
      await tester.pump();
      expect(draft.startAt, startAfterTakeover);
      expect(draft.endAt, endAfterTakeover);
      expect(hourHeight, greaterThan(52));

      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final surface = find.byKey(const ValueKey('week-calendar-pinch-surface'));
      final surfaceTopLeft = tester.getTopLeft(surface);
      await tester.dragFrom(
        surfaceTopLeft + const Offset(24, 120),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(scrollController.offset, greaterThan(initialScroll));
      expect(
        find.byKey(const ValueKey('week-calendar-draft-start-handle')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('three-day mode pages, renders blocks, and maps taps by 3 days', (
    tester,
  ) async {
    WeekCalendarTapTarget? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekCalendarView(
            now: DateTime(2026, 7, 6, 7, 30),
            visibleDays: 3,
            initialWeek: WeekRange(
              start: CalendarDay(year: 2026, month: 7, day: 6),
              visibleDays: 3,
            ),
            wakePlans: [
              buildPlan(
                id: 'three-day-plan',
                targetDay: CalendarDay(year: 2026, month: 7, day: 8),
                targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
              ),
            ],
            onTargetTap: (target) => selected = target,
          ),
        ),
      ),
    );

    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Tue'), findsOneWidget);
    expect(find.text('Wed'), findsOneWidget);
    expect(find.text('Thu'), findsNothing);
    expect(find.textContaining('13 alarms'), findsOneWidget);

    final tapSurface = find
        .byWidgetPredicate(
          (widget) => widget is GestureDetector && widget.onTapUp != null,
        )
        .first;
    final size = tester.getSize(tapSurface);
    tester.widget<GestureDetector>(tapSurface).onTapUp!(
      TapUpDetails(
        localPosition: Offset(size.width * 5 / 6, size.height * 10 / 24),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.pump();
    expect(selected?.day, CalendarDay(year: 2026, month: 7, day: 8));

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Thu'), findsOneWidget);
    expect(find.text('Sat'), findsOneWidget);
    expect(find.text('Sun'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'two-finger diagonal pinch zooms without paging then restores page swipe',
    (tester) async {
      var hourHeight = 52.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return WeekCalendarView(
                  now: DateTime(2026, 7, 6, 7, 30),
                  visibleDays: 3,
                  initialWeek: WeekRange(
                    start: CalendarDay(year: 2026, month: 7, day: 6),
                    visibleDays: 3,
                  ),
                  hourHeight: hourHeight,
                  onHourHeightChanged: (value) {
                    setState(() {
                      hourHeight = value;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surface = find.byKey(const ValueKey('week-calendar-pinch-surface'));
      final center = tester.getCenter(surface);
      final first = await tester.createGesture(pointer: 11);
      final second = await tester.createGesture(pointer: 12);
      await first.down(center + const Offset(-40, -10));
      await second.down(center + const Offset(40, 10));
      await tester.pump();

      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );

      await first.moveTo(center + const Offset(-200, -80));
      await second.moveTo(center + const Offset(200, 80));
      await tester.pumpAndSettle();

      expect(hourHeight, greaterThan(52));
      expect(find.text('6'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('9'), findsNothing);

      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isNot(isA<NeverScrollableScrollPhysics>()),
      );

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('9'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled pinch clears focal state before an external height update',
    (tester) async {
      var hourHeight = 52.0;
      late StateSetter updateHarness;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                updateHarness = setState;
                return WeekCalendarView(
                  now: DateTime(2026, 7, 8, 7, 30),
                  hourHeight: hourHeight,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollController = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      final beforeTopMinute = scrollController.offset / (hourHeight / 60);
      final surface = find.byKey(const ValueKey('week-calendar-pinch-surface'));
      final center = tester.getCenter(surface);
      final first = await tester.createGesture(pointer: 21);
      final second = await tester.createGesture(pointer: 22);
      await first.down(center + const Offset(-40, 0));
      await second.down(center + const Offset(40, 0));
      await tester.pump();
      await first.cancel();
      await second.cancel();
      await tester.pumpAndSettle();

      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isNot(isA<NeverScrollableScrollPhysics>()),
      );
      updateHarness(() {
        hourHeight = 92;
      });
      await tester.pumpAndSettle();

      final afterTopMinute = scrollController.offset / (hourHeight / 60);
      expect(afterTopMinute, closeTo(beforeTopMinute, 0.01));

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('12'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
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

Future<void> _rawDrag(
  WidgetTester tester,
  Finder finder,
  Offset offset, {
  required int pointer,
}) {
  return _rawDragFrom(
    tester,
    tester.getCenter(finder),
    offset,
    pointer: pointer,
  );
}

Future<void> _rawDragFrom(
  WidgetTester tester,
  Offset start,
  Offset offset, {
  required int pointer,
}) async {
  final gesture = await tester.createGesture(pointer: pointer);
  await gesture.down(start);
  await tester.pump();
  await gesture.moveTo(start + (offset / 2));
  await tester.pump();
  await gesture.moveTo(start + offset);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}
