import 'dart:async';

import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/bootstrap/app_bootstrap.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/settings/application/wake_plan_defaults_controller.dart';
import 'package:calarm/features/settings/application/alarm_health_controller.dart';
import 'package:calarm/features/week_calendar/presentation/week_calendar_placeholder.dart';
import 'package:calarm/features/week_calendar/week_calendar.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:calarm/features/wake_plan/ui/inline_wake_plan_editor.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WakePlanDatabase database;
  late WakePlanRepository repository;
  late ProviderContainer container;

  setUp(() {
    database = WakePlanDatabase(NativeDatabase.memory());
    repository = WakePlanRepository(database);
    container = ProviderContainer(
      overrides: [
        weekCalendarRepositoryProvider.overrideWith((ref) async => repository),
        weekCalendarClockProvider.overrideWith(
          (ref) =>
              () => DateTime(2026, 7, 8, 5, 30),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  testWidgets(
    'inline editor disables Save when its idle target timer expires',
    (tester) async {
      var currentNow = DateTime(2026, 7, 8, 10);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineWakePlanEditor(
              startAt: DateTime(2026, 7, 8, 9),
              endAt: DateTime(2026, 7, 8, 10, 1),
              now: currentNow,
              clock: () => currentNow,
              saving: false,
              submissionAttempted: false,
              onRangeChanged: (startAt, endAt) =>
                  InlineWakePlanRangeChange.accepted(
                    startAt: startAt,
                    endAt: endAt,
                  ),
              onSave: () {},
              onCancel: () {},
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('inline-wake-plan-save')),
            )
            .onPressed,
        isNotNull,
      );

      currentNow = DateTime(2026, 7, 8, 10, 1);
      await tester.pump(const Duration(minutes: 1));

      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('inline-wake-plan-save')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Move the wake target to a future time.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('inline editor refreshes target validity when the app resumes', (
    tester,
  ) async {
    var currentNow = DateTime(2026, 7, 8, 10);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineWakePlanEditor(
            startAt: DateTime(2026, 7, 8, 9),
            endAt: DateTime(2026, 7, 8, 11),
            now: currentNow,
            clock: () => currentNow,
            saving: false,
            submissionAttempted: false,
            onRangeChanged: (startAt, endAt) =>
                InlineWakePlanRangeChange.accepted(
                  startAt: startAt,
                  endAt: endAt,
                ),
            onSave: () {},
            onCancel: () {},
          ),
        ),
      ),
    );
    currentNow = DateTime(2026, 7, 8, 12);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('inline-wake-plan-save')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Move the wake target to a future time.'), findsOneWidget);
  });

  testWidgets(
    'refreshes calendar now at minute boundaries and on resume only while active',
    (tester) async {
      var currentNow = DateTime(2026, 7, 8, 5, 30, 45);
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekCalendarRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            wakePlanDefaultsRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            weekCalendarClockProvider.overrideWith(
              (ref) =>
                  () => currentNow,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: WeekCalendarPlaceholder()),
          ),
        ),
      );
      await tester.pump();

      WeekCalendarView calendar() =>
          tester.widget<WeekCalendarView>(find.byType(WeekCalendarView));

      expect(calendar().now, DateTime(2026, 7, 8, 5, 30, 45));
      currentNow = DateTime(2026, 7, 8, 5, 31);
      await tester.pump(const Duration(seconds: 14));
      expect(calendar().now, DateTime(2026, 7, 8, 5, 30, 45));
      await tester.pump(const Duration(seconds: 1));
      expect(calendar().now, DateTime(2026, 7, 8, 5, 31));

      currentNow = DateTime(2026, 7, 8, 5, 32);
      await tester.pump(const Duration(seconds: 60));
      expect(calendar().now, DateTime(2026, 7, 8, 5, 32));

      var displayedNow = DateTime(2026, 7, 8, 5, 32);
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        currentNow = displayedNow.add(const Duration(minutes: 8));
        await tester.pump(const Duration(minutes: 2));
        expect(calendar().now, displayedNow, reason: '$state must stop ticks');

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        displayedNow = currentNow;
        expect(
          calendar().now,
          displayedNow,
          reason: 'resume after $state must catch up immediately',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      currentNow = displayedNow.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeated resume notifications keep one observable minute-boundary tick',
    (tester) async {
      var currentNow = DateTime(2026, 7, 8, 5, 30, 45);
      var clockReads = 0;
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekCalendarRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            wakePlanDefaultsRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            weekCalendarClockProvider.overrideWith(
              (ref) => () {
                clockReads += 1;
                return currentNow;
              },
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: WeekCalendarPlaceholder()),
          ),
        ),
      );
      await tester.pump();

      for (var index = 0; index < 3; index += 1) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pump();
      final readsBeforeBoundary = clockReads;
      currentNow = DateTime(2026, 7, 8, 5, 31);

      await tester.pump(const Duration(seconds: 15));

      final calendar = tester.widget<WeekCalendarView>(
        find.byType(WeekCalendarView),
      );
      expect(calendar.now, DateTime(2026, 7, 8, 5, 31));
      expect(clockReads - readsBeforeBoundary, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<WeekCalendarView>(find.byType(WeekCalendarView)).now,
        DateTime(2026, 7, 8, 5, 31),
      );
    },
  );

  testWidgets(
    'minute refresh preserves draft zoom page and vertical scroll together',
    (tester) async {
      var currentNow = DateTime(2026, 7, 8, 5, 30, 45);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekCalendarRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            wakePlanDefaultsRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            weekCalendarClockProvider.overrideWith(
              (ref) =>
                  () => currentNow,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(height: 720, child: WeekCalendarPlaceholder()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      var calendar = tester.widget<WeekCalendarView>(
        find.byType(WeekCalendarView),
      );
      calendar.onTargetTap!(
        WeekCalendarTapTarget(
          day: CalendarDay(year: 2026, month: 7, day: 15),
          time: TimeOfDayMinutes.fromHourMinute(hour: 10, minute: 0),
        ),
      );
      await tester.pump();
      calendar = tester.widget<WeekCalendarView>(find.byType(WeekCalendarView));
      calendar.onHourHeightChanged!(80);
      await tester.pump();

      calendar = tester.widget<WeekCalendarView>(find.byType(WeekCalendarView));
      final draftBefore = calendar.draft!;
      final pageController = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      final visibleScrollView = find
          .byType(SingleChildScrollView)
          .hitTestable()
          .first;
      final scrollController = tester
          .widget<SingleChildScrollView>(visibleScrollView)
          .controller!;
      scrollController.jumpTo(600);
      await tester.pump();
      final pageBefore = pageController.page;
      final offsetBefore = scrollController.offset;
      expect(calendar.hourHeight, 80);
      expect(
        find.byKey(const ValueKey('week-calendar-draft-start-handle')),
        findsOneWidget,
      );

      currentNow = DateTime(2026, 7, 8, 5, 31);
      await tester.pump(const Duration(seconds: 15));

      calendar = tester.widget<WeekCalendarView>(find.byType(WeekCalendarView));
      expect(calendar.now, DateTime(2026, 7, 8, 5, 31));
      expect(calendar.hourHeight, 80);
      expect(calendar.draft?.id, draftBefore.id);
      expect(calendar.draft?.startAt, draftBefore.startAt);
      expect(calendar.draft?.endAt, draftBefore.endAt);
      expect(pageController.page, pageBefore);
      expect(scrollController.offset, offsetBefore);
      expect(
        find.byKey(const ValueKey('week-calendar-draft-start-handle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('week-calendar-draft-end-handle')),
        findsOneWidget,
      );
    },
  );

  for (final testCase in [
    (
      name: 'same-day',
      time: TimeOfDayMinutes.fromHourMinute(hour: 22, minute: 30),
    ),
    (
      name: 'cross-day',
      time: TimeOfDayMinutes.fromHourMinute(hour: 23, minute: 30),
    ),
  ]) {
    testWidgets(
      '${testCase.name} near-23:00 tap preserves scroll grid and date page',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              weekCalendarRepositoryProvider.overrideWith(
                (ref) async => repository,
              ),
              wakePlanDefaultsRepositoryProvider.overrideWith(
                (ref) async => repository,
              ),
              weekCalendarClockProvider.overrideWith(
                (ref) =>
                    () => DateTime(2026, 7, 8, 18),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SizedBox(height: 720, child: WeekCalendarPlaceholder()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pageController = tester
            .widget<PageView>(find.byType(PageView))
            .controller!;
        final scrollController = tester
            .widget<SingleChildScrollView>(
              find.byType(SingleChildScrollView).hitTestable().first,
            )
            .controller!;
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pump();
        final pageBefore = pageController.page;
        final offsetBefore = scrollController.offset;
        final gridBefore = tester.getTopLeft(
          find.byKey(const ValueKey('week-calendar-time-grid')).first,
        );

        _calendar(tester).onTargetTap!(
          WeekCalendarTapTarget(
            day: CalendarDay(year: 2026, month: 7, day: 8),
            time: testCase.time,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(InlineWakePlanEditor), findsOneWidget);
        expect(pageController.page, pageBefore);
        expect(scrollController.offset, offsetBefore);
        expect(
          tester.getTopLeft(
            find.byKey(const ValueKey('week-calendar-time-grid')).first,
          ),
          gridBefore,
        );
        final draft = _calendar(tester).draft!;
        expect(
          draft.endAt.day != draft.startAt.day,
          testCase.name == 'cross-day',
        );

        _calendar(tester).onDraftChanged!(draft.moveBy(days: 0, minutes: -5));
        await tester.pump();
        expect(pageController.page, pageBefore);
        expect(scrollController.offset, offsetBefore);

        await tester.tap(find.byKey(const ValueKey('inline-wake-plan-cancel')));
        await tester.pumpAndSettle();
        expect(pageController.page, pageBefore);
        expect(scrollController.offset, offsetBefore);
      },
    );
  }

  for (final testCase in [
    (
      name: 'same-day',
      startAt: DateTime(2026, 7, 9, 9, 2),
      endAt: DateTime(2026, 7, 9, 10, 3),
      expectedStartAt: DateTime(2026, 7, 9, 9),
      expectedEndAt: DateTime(2026, 7, 9, 10, 5),
    ),
    (
      name: '23:55 to 00:10',
      startAt: DateTime(2026, 7, 9, 23, 53),
      endAt: DateTime(2026, 7, 10, 0, 12),
      expectedStartAt: DateTime(2026, 7, 9, 23, 55),
      expectedEndAt: DateTime(2026, 7, 10, 0, 10),
    ),
  ]) {
    testWidgets(
      'direct ${testCase.name} edit updates outline without moving scroll',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              weekCalendarRepositoryProvider.overrideWith(
                (ref) async => repository,
              ),
              wakePlanDefaultsRepositoryProvider.overrideWith(
                (ref) async => repository,
              ),
              weekCalendarClockProvider.overrideWith(
                (ref) =>
                    () => DateTime(2026, 7, 8, 18),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SizedBox(height: 720, child: WeekCalendarPlaceholder()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _calendar(tester).onTargetTap!(
          WeekCalendarTapTarget(
            day: CalendarDay(year: 2026, month: 7, day: 9),
            time: TimeOfDayMinutes.fromHourMinute(hour: 9, minute: 0),
          ),
        );
        await tester.pumpAndSettle();

        final pageController = tester
            .widget<PageView>(find.byType(PageView))
            .controller!;
        final scrollController = tester
            .widget<SingleChildScrollView>(
              find.byType(SingleChildScrollView).hitTestable().first,
            )
            .controller!;
        scrollController.jumpTo(420);
        await tester.pump();
        final pageBefore = pageController.page;
        final offsetBefore = scrollController.offset;
        final gridBefore = tester.getTopLeft(
          find.byKey(const ValueKey('week-calendar-time-grid')).first,
        );

        final editor = tester.widget<InlineWakePlanEditor>(
          find.byType(InlineWakePlanEditor),
        );
        final change = editor.onRangeChanged(testCase.startAt, testCase.endAt);
        expect(change.guidance, isNull);
        expect(change.canonicalStartAt, testCase.expectedStartAt);
        expect(change.canonicalEndAt, testCase.expectedEndAt);
        await tester.pump();

        final draft = _calendar(tester).draft!;
        expect(draft.startAt, testCase.expectedStartAt);
        expect(draft.endAt, testCase.expectedEndAt);
        expect(pageController.page, pageBefore);
        expect(scrollController.offset, offsetBefore);
        expect(
          tester.getTopLeft(
            find.byKey(const ValueKey('week-calendar-time-grid')).first,
          ),
          gridBefore,
        );
      },
    );
  }

  testWidgets('invalid direct ranges never replace or save the draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 18),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _calendar(tester).onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 9, minute: 0),
      ),
    );
    await tester.pump();
    final original = _calendar(tester).draft!;
    final editor = tester.widget<InlineWakePlanEditor>(
      find.byType(InlineWakePlanEditor),
    );

    expect(
      editor
          .onRangeChanged(DateTime(2026, 7, 9, 11), DateTime(2026, 7, 9, 10))
          .guidance,
      'Start must be before end.',
    );
    expect(
      editor
          .onRangeChanged(DateTime(2026, 7, 9, 9), DateTime(2026, 7, 9, 12, 5))
          .guidance,
      'Choose a range no longer than 3 hours.',
    );
    await tester.pump();

    expect(_calendar(tester).draft!.startAt, original.startAt);
    expect(_calendar(tester).draft!.endAt, original.endAt);
    expect(
      await repository.fetchWakePlans(now: DateTime(2026, 7, 8, 18)),
      isEmpty,
    );
  });

  testWidgets('past direct end stays unsavable', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 18),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _calendar(tester).onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 9, minute: 0),
      ),
    );
    await tester.pump();
    var editor = tester.widget<InlineWakePlanEditor>(
      find.byType(InlineWakePlanEditor),
    );
    expect(
      editor
          .onRangeChanged(DateTime(2026, 7, 8, 9), DateTime(2026, 7, 8, 10))
          .guidance,
      isNull,
    );
    await tester.pump();

    editor = tester.widget<InlineWakePlanEditor>(
      find.byType(InlineWakePlanEditor),
    );
    editor.onSave();
    await tester.pump();

    expect(find.text('Move the wake target to a future time.'), findsOneWidget);
    expect(
      await repository.fetchWakePlans(now: DateTime(2026, 7, 8, 18)),
      isEmpty,
    );
  });

  testWidgets('cross-year direct edit saves local snapped target', (
    tester,
  ) async {
    final gateway = FakeNativeAlarmGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 12, 30, 18),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _calendar(tester).onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 12, day: 31),
        time: TimeOfDayMinutes.fromHourMinute(hour: 23, minute: 0),
      ),
    );
    await tester.pump();
    final editor = tester.widget<InlineWakePlanEditor>(
      find.byType(InlineWakePlanEditor),
    );
    expect(
      editor
          .onRangeChanged(
            DateTime(2026, 12, 31, 23, 53),
            DateTime(2027, 1, 1, 0, 12),
          )
          .guidance,
      isNull,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('inline-wake-plan-save')));
    await tester.pumpAndSettle();

    final plans = await repository.fetchWakePlans(
      now: DateTime(2026, 12, 30, 18),
    );
    expect(plans, hasLength(1));
    expect(
      plans.single.targetAt(CalendarDay(year: 2027, month: 1, day: 1)),
      DateTime(2027, 1, 1, 0, 10),
    );
    expect(plans.single.startOffset, const Duration(minutes: 15));
  });

  testWidgets('foreground return recenters once while other rebuilds do not', (
    tester,
  ) async {
    var currentNow = DateTime(2026, 7, 8, 5, 30, 45);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => currentNow,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 480, child: WeekCalendarPlaceholder()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    var pageController = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    var scrollController = tester
        .widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView).hitTestable(),
        )
        .controller!;
    scrollController.jumpTo(600);
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    currentNow = DateTime(2026, 7, 8, 18);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(_calendar(tester).recenterRequest, 1);
    pageController = tester.widget<PageView>(find.byType(PageView)).controller!;
    scrollController = tester
        .widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView).hitTestable(),
        )
        .controller!;
    expect(pageController.page, 10000);
    expect(scrollController.offset, 840);

    scrollController.jumpTo(600);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    ProviderScope.containerOf(
      tester.element(find.byType(WeekCalendarPlaceholder)),
    ).invalidate(weekCalendarWakePlansProvider);
    await tester.pumpAndSettle();
    expect(_calendar(tester).recenterRequest, 1);
    expect(pageController.page, 10000);
    expect(scrollController.offset, 600);

    currentNow = DateTime(2026, 7, 8, 18, 1);
    await tester.pump(const Duration(seconds: 15));
    expect(_calendar(tester).recenterRequest, 1);
    expect(pageController.page, 10000);
    expect(scrollController.offset, 600);
  });

  test(
    'loads future plans outside the current visible week for paging',
    () async {
      final plan = _plan(
        id: 'next-week',
        targetDay: CalendarDay(year: 2026, month: 7, day: 15),
      );
      await repository.saveWakePlan(plan);

      final plans = await container.read(weekCalendarWakePlansProvider.future);

      expect(plans.map((plan) => plan.id), contains('next-week'));
    },
  );

  testWidgets('surfaces provider load errors instead of silent fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith((ref) async {
            throw StateError('database unavailable');
          }),
          wakePlanDefaultsRepositoryProvider.overrideWith((ref) async {
            throw StateError('defaults unavailable');
          }),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 0, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load wake plans or defaults.'), findsOneWidget);

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inline-wake-plan-editor')),
      findsOneWidget,
    );
    expect(find.text('Create wake plan'), findsNothing);
  });

  testWidgets('expands calendar to fill the available primary surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 720, child: WeekCalendarPlaceholder()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );

    expect(calendar.height, greaterThanOrEqualTo(550));
    expect(calendar.hourHeight, 52);
  });

  testWidgets('does not cap calendar height on a tall primary surface', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 960, child: WeekCalendarPlaceholder()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );

    expect(calendar.height, greaterThan(720));
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(320, 568), Size(568, 320)]) {
    testWidgets('keeps inline draft controls compact at $size', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekCalendarRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            wakePlanDefaultsRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            weekCalendarClockProvider.overrideWith(
              (ref) =>
                  () => DateTime(2026, 7, 8, 5, 30),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: WeekCalendarPlaceholder()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (size.width > size.height) {
        await tester.tap(
          find.byKey(const ValueKey('week-calendar-three-day-button')),
        );
        await tester.pump();
      }
      _calendar(tester).onTargetTap!(
        WeekCalendarTapTarget(
          day: CalendarDay(year: 2026, month: 7, day: 9),
          time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('inline-wake-plan-editor')),
        findsOneWidget,
      );
      expect(find.text('Save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'uses actual remaining height with wrapped errors, large text, and inset',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekCalendarRepositoryProvider.overrideWith((ref) async {
              throw StateError('database unavailable');
            }),
            wakePlanDefaultsRepositoryProvider.overrideWith((ref) async {
              throw StateError('defaults unavailable');
            }),
            weekCalendarClockProvider.overrideWith(
              (ref) =>
                  () => DateTime(2026, 7, 8, 5, 30),
            ),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 568),
                padding: EdgeInsets.only(bottom: 34),
                textScaler: TextScaler.linear(2),
              ),
              child: const Scaffold(body: WeekCalendarPlaceholder()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      _calendar(tester).onTargetTap!(
        WeekCalendarTapTarget(
          day: CalendarDay(year: 2026, month: 7, day: 9),
          time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
        ),
      );
      await tester.pumpAndSettle();

      final error = find.text('Could not load wake plans or defaults.');
      final calendar = find.byType(WeekCalendarView);
      final editor = find.byKey(const ValueKey('inline-wake-plan-editor'));
      expect(tester.getSize(error).height, greaterThan(40));
      expect(
        tester.getRect(calendar).bottom,
        lessThanOrEqualTo(tester.getRect(editor).top),
      );
      expect(
        tester.getRect(editor).bottom,
        lessThanOrEqualTo(tester.getRect(error).top),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switches 3/7-day modes and pinches between bounded hour heights',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekCalendarRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            wakePlanDefaultsRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            weekCalendarClockProvider.overrideWith(
              (ref) =>
                  () => DateTime(2026, 7, 8, 5, 30),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(height: 720, child: WeekCalendarPlaceholder()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('week-calendar-zoom-in-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('week-calendar-zoom-out-button')),
        findsNothing,
      );
      expect(_calendar(tester).visibleDays, DateTime.daysPerWeek);

      await tester.tap(
        find.byKey(const ValueKey('week-calendar-three-day-button')),
      );
      await tester.pumpAndSettle();
      expect(_calendar(tester).visibleDays, 3);
      expect(find.text('Wed'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
      expect(find.text('Sat'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('week-calendar-seven-day-button')),
      );
      await tester.pumpAndSettle();
      expect(_calendar(tester).visibleDays, DateTime.daysPerWeek);
      expect(find.text('Sun'), findsOneWidget);

      final scrollController = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      final surface = find.byKey(const ValueKey('week-calendar-pinch-surface'));
      final focalY = tester.getSize(surface).height / 2;
      final beforeMinute =
          (scrollController.offset + focalY) /
          (_calendar(tester).hourHeight / 60);

      await _pinch(tester, surface, startDistance: 80, endDistance: 400);
      expect(_calendar(tester).hourHeight, 92);
      final afterMinute =
          (scrollController.offset + focalY) /
          (_calendar(tester).hourHeight / 60);
      expect(afterMinute, closeTo(beforeMinute, 2));

      await _pinch(tester, surface, startDistance: 200, endDistance: 10);
      expect(_calendar(tester).hourHeight, 36);

      final beforeDrag = scrollController.offset;
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(scrollController.offset, greaterThan(beforeDrag));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'feature repository providers share the app repository instance',
    () async {
      final container = ProviderContainer(
        overrides: [
          appWakePlanRepositoryProvider.overrideWith((ref) async => repository),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(weekCalendarRepositoryProvider.future),
        same(repository),
      );
      expect(
        await container.read(wakePlanDefaultsRepositoryProvider.future),
        same(repository),
      );
    },
  );

  testWidgets('creates only one inline draft and disables mode changes', (
    tester,
  ) async {
    final service = Completer<WakePlanService>();
    await repository.saveWakePlan(
      _plan(id: 'seed', targetDay: CalendarDay(year: 2026, month: 7, day: 10)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarWakePlanServiceProvider.overrideWith((ref) {
            return service.future;
          }),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    final target = WeekCalendarTapTarget(
      day: CalendarDay(year: 2026, month: 7, day: 9),
      time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
    );

    calendar.onTargetTap!(target);
    await tester.pump();
    calendar.onTargetTap!(target);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('inline-wake-plan-editor')),
      findsOneWidget,
    );
    expect(find.text('Create wake plan'), findsNothing);
    expect(_calendar(tester).draft?.startAt, DateTime(2026, 7, 9, 7));
    expect(_calendar(tester).draft?.endAt, DateTime(2026, 7, 9, 8));
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('week-calendar-three-day-button')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    service.complete(
      WakePlanService(
        repository: repository,
        nativeAlarmGateway: FakeNativeAlarmGateway(),
        clock: () => DateTime(2026, 7, 8, 0, 30),
      ),
    );
  });

  testWidgets('cancel removes an unsubmitted draft without persistence', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _calendar(tester).onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
      ),
    );
    await tester.pump();
    final draftId = _calendar(tester).draft!.id;

    await tester.tap(find.byKey(const ValueKey('inline-wake-plan-cancel')));
    await tester.pump();

    expect(find.byKey(const ValueKey('inline-wake-plan-editor')), findsNothing);
    expect(await repository.fetchWakePlan(draftId), isNull);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('week-calendar-three-day-button')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('save uses defaults, persists once, and clears the draft', (
    tester,
  ) async {
    final gateway = FakeNativeAlarmGateway();
    final defaults = AppSettings(
      defaultStartOffset: const Duration(minutes: 90),
      defaultInterval: const Duration(minutes: 15),
      defaultSoundId: defaultWakePlanSoundId,
      defaultVibrationEnabled: false,
      defaultRepeatType: RepeatType.weekly,
    );
    await repository.saveAppSettings(defaults);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _calendar(tester).onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 23, minute: 30),
      ),
    );
    await tester.pump();
    final draft = _calendar(tester).draft!;
    expect(draft.endAt, DateTime(2026, 7, 10, 1));

    await tester.tap(find.byKey(const ValueKey('inline-wake-plan-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inline-wake-plan-editor')), findsNothing);
    final saved = await repository.fetchWakePlan(draft.id);
    expect(saved, isNotNull);
    expect(
      saved!.targetTime,
      TimeOfDayMinutes.fromHourMinute(hour: 1, minute: 0),
    );
    expect(saved.startOffset, const Duration(minutes: 90));
    expect(saved.interval, const Duration(minutes: 15));
    expect(saved.repeatRule, RepeatRule.weekly({Weekday.friday}));
    expect(saved.soundId, defaultWakePlanSoundId);
    expect(saved.vibrationEnabled, isFalse);
    expect(saved.createdAt, draft.createdAt);
    expect(gateway.scheduledRequests, isNotEmpty);
  });

  testWidgets('double Save while service is delayed creates only once', (
    tester,
  ) async {
    final service = _DelayedWakePlanService(
      repository: repository,
      nativeAlarmGateway: FakeNativeAlarmGateway(),
      clock: () => DateTime(2026, 7, 8, 5, 30),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarWakePlanServiceProvider.overrideWith(
            (ref) async => service,
          ),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _calendar(tester).onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
      ),
    );
    await tester.pump();

    final save = find.byKey(const ValueKey('inline-wake-plan-save'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(service.createCalls, 1);
    expect(find.text('Saving…'), findsOneWidget);

    service.release.complete();
    await tester.pumpAndSettle();
    expect(service.createCalls, 1);
    expect(find.byKey(const ValueKey('inline-wake-plan-editor')), findsNothing);
  });

  testWidgets('refreshes persisted plans after schedule failure', (
    tester,
  ) async {
    final gateway = FakeNativeAlarmGateway()
      ..scheduleFailureReason = ScheduleFailureReason.permissionMissing;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
      ),
    );
    await tester.pumpAndSettle();
    final draftId = _calendar(tester).draft!.id;

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Alarm permission is required before alarms can be scheduled.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inline-wake-plan-editor')),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    final refreshedCalendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    expect(refreshedCalendar.wakePlans, hasLength(1));
    expect(refreshedCalendar.wakePlans.single.id, draftId);
    expect(refreshedCalendar.draftInteractionEnabled, isFalse);
    final firstPersisted = refreshedCalendar.wakePlans.single;
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('inline-wake-plan-cancel')),
          )
          .onPressed,
      isNull,
    );

    gateway.scheduleFailureReason = null;
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(gateway.scheduledRequests, isNotEmpty);
    final retriedCalendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    expect(retriedCalendar.wakePlans, hasLength(1));
    final retried = retriedCalendar.wakePlans.single;
    expect(retried.id, firstPersisted.id);
    expect(retried.createdAt, firstPersisted.createdAt);
    expect(retried.targetTime, firstPersisted.targetTime);
    expect(retried.startOffset, firstPersisted.startOffset);
    expect(retried.repeatRule, firstPersisted.repeatRule);
    expect(retried.soundId, firstPersisted.soundId);
    expect(retried.vibrationEnabled, firstPersisted.vibrationEnabled);
  });

  testWidgets(
    'permission loss during Save refreshes readiness and keeps inline Retry',
    (tester) async {
      final gateway = _RevokingScheduleGateway();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          appNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 8, 5, 30),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: WeekCalendarPlaceholder()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _calendar(tester).onTargetTap!(
        WeekCalendarTapTarget(
          day: CalendarDay(year: 2026, month: 7, day: 9),
          time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('inline-wake-plan-save')));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      final health = container.read(alarmHealthProvider).value!;
      expect(health.readinessStatus, AlarmReadinessStatus.actionRequired);
      expect(health.capability.requiresExactAlarmPermission, isTrue);
      expect(gateway.capabilityChecks, greaterThanOrEqualTo(1));
    },
  );

  testWidgets('create validation follows the live injected clock', (
    tester,
  ) async {
    final initialNow = DateTime(2026, 7, 8, 5, 30);
    var currentNow = initialNow;
    var clockCalls = 0;
    DateTime clock() {
      clockCalls += 1;
      return currentNow;
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith(
            (ref) => FakeNativeAlarmGateway(),
          ),
          weekCalendarClockProvider.overrideWith((ref) => clock),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onTargetTap!(
      WeekCalendarTapTarget(
        day: CalendarDay(year: 2026, month: 7, day: 9),
        time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inline-wake-plan-editor')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );

    currentNow = DateTime(2026, 7, 10, 5, 30);
    final currentCalendar = _calendar(tester);
    currentCalendar.onDraftChanged!(currentCalendar.draft!.copyWith());
    await tester.pump();

    expect(find.text('Move the wake target to a future time.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(clockCalls, greaterThan(1));
  });

  testWidgets('opens wake plan detail and edit reschedules future alarms', (
    tester,
  ) async {
    final gateway = FakeNativeAlarmGateway();
    final now = DateTime(2026, 7, 8, 5, 30);
    final plan = _plan(
      id: 'editable',
      targetDay: CalendarDay(year: 2026, month: 7, day: 9),
    );
    final service = WakePlanService(
      repository: repository,
      nativeAlarmGateway: gateway,
      clock: () => now,
    );
    await service.createPlan(plan);
    gateway.scheduledRequests.clear();
    gateway.cancelledOccurrences.clear();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => now,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onWakePlanTap!(
      WeekCalendarWakePlanTapTarget(
        wakePlan: plan,
        targetDay: CalendarDay(year: 2026, month: 7, day: 9),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wake plan detail'), findsOneWidget);
    expect(find.text('Next fire'), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Skip state'), findsOneWidget);

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

    expect(gateway.cancelledOccurrences, isNotEmpty);
    expect(gateway.scheduledRequests, isNotEmpty);
    expect(
      find.textContaining('Wake plan updated. Next alarm:'),
      findsOneWidget,
    );
  });

  testWidgets('editing weekly plan from past block preserves repeat weekdays', (
    tester,
  ) async {
    final gateway = FakeNativeAlarmGateway();
    final now = DateTime(2026, 7, 8, 5, 30);
    final plan = _plan(
      id: 'weekly-edit',
      targetDay: CalendarDay(year: 2026, month: 7, day: 6),
      repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.wednesday}),
    );
    final service = WakePlanService(
      repository: repository,
      nativeAlarmGateway: gateway,
      clock: () => now,
    );
    await service.createPlan(plan);
    gateway.scheduledRequests.clear();
    gateway.cancelledOccurrences.clear();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => now,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onWakePlanTap!(
      WeekCalendarWakePlanTapTarget(
        wakePlan: plan,
        targetDay: CalendarDay(year: 2026, month: 7, day: 6),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit wake plan'), findsOneWidget);
    expect(
      find.text('Choose a future wake target before saving.'),
      findsNothing,
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(gateway.cancelledOccurrences, isNotEmpty);
    expect(gateway.scheduledRequests, isNotEmpty);
    final saved = await repository.fetchWakePlan('weekly-edit');
    expect(
      saved?.repeatRule,
      RepeatRule.weekly({Weekday.monday, Weekday.wednesday}),
    );
    expect(
      find.textContaining('Wake plan updated. Next alarm:'),
      findsOneWidget,
    );
  });

  testWidgets(
    'confirms repeating wake plan delete and removes calendar block',
    (tester) async {
      final gateway = FakeNativeAlarmGateway();
      final now = DateTime(2026, 7, 8, 5, 30);
      final plan = _plan(
        id: 'weekly-delete',
        targetDay: CalendarDay(year: 2026, month: 7, day: 10),
        repeatRule: RepeatRule.weekly({Weekday.friday}),
      );
      final service = WakePlanService(
        repository: repository,
        nativeAlarmGateway: gateway,
        clock: () => now,
      );
      await service.createPlan(plan);
      gateway.cancelledPlans.clear();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekCalendarRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            wakePlanDefaultsRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            weekCalendarNativeAlarmGatewayProvider.overrideWith(
              (ref) => gateway,
            ),
            weekCalendarClockProvider.overrideWith(
              (ref) =>
                  () => now,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: WeekCalendarPlaceholder()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var calendar = tester.widget<WeekCalendarView>(
        find.byType(WeekCalendarView),
      );
      expect(
        calendar.wakePlans.map((plan) => plan.id),
        contains('weekly-delete'),
      );

      calendar.onWakePlanTap!(
        WeekCalendarWakePlanTapTarget(
          wakePlan: plan,
          targetDay: CalendarDay(year: 2026, month: 7, day: 10),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete repeating wake plan?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
      await tester.pumpAndSettle();

      expect(gateway.cancelledPlans, isNotEmpty);
      expect(await repository.fetchWakePlan('weekly-delete'), isNull);
      expect(find.text('Wake plan deleted.'), findsOneWidget);

      calendar = tester.widget<WeekCalendarView>(find.byType(WeekCalendarView));
      expect(
        calendar.wakePlans.map((plan) => plan.id),
        isNot(contains('weekly-delete')),
      );
    },
  );

  testWidgets('skips next target from detail and keeps following repeats', (
    tester,
  ) async {
    final gateway = FakeNativeAlarmGateway();
    final now = DateTime(2026, 7, 8, 5, 30);
    final skippedDay = CalendarDay(year: 2026, month: 7, day: 8);
    final followingDay = CalendarDay(year: 2026, month: 7, day: 9);
    final plan = _plan(
      id: 'weekly-skip',
      targetDay: skippedDay,
      repeatRule: RepeatRule.weekly({Weekday.wednesday, Weekday.thursday}),
    );
    final service = WakePlanService(
      repository: repository,
      nativeAlarmGateway: gateway,
      clock: () => now,
    );
    await service.createPlan(plan);
    gateway.cancelledOccurrences.clear();
    gateway.scheduledRequests.clear();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekCalendarRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          weekCalendarNativeAlarmGatewayProvider.overrideWith((ref) => gateway),
          weekCalendarClockProvider.overrideWith(
            (ref) =>
                () => now,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeekCalendarPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = tester.widget<WeekCalendarView>(
      find.byType(WeekCalendarView),
    );
    calendar.onWakePlanTap!(
      WeekCalendarWakePlanTapTarget(wakePlan: plan, targetDay: skippedDay),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip next target'));
    await tester.pumpAndSettle();

    final saved = await repository.fetchWakePlan('weekly-skip');
    expect(saved?.skipNextDate, skippedDay);
    expect(gateway.cancelledOccurrences, isNotEmpty);
    expect(gateway.scheduledRequests, isNotEmpty);
    expect(find.text('Next wake target skipped.'), findsOneWidget);
    expect(saved!.occursOn(skippedDay), isFalse);
    expect(saved.occursOn(followingDay), isTrue);
  });
}

WakePlan _plan({
  required String id,
  required CalendarDay targetDay,
  RepeatRule? repeatRule,
}) {
  final now = DateTime(2026, 7, 8, 5, 30);
  return WakePlan(
    id: id,
    title: id,
    targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
    startOffset: const Duration(minutes: 60),
    interval: const Duration(minutes: 5),
    repeatRule: repeatRule ?? RepeatRule.oneTime(targetDay),
    isEnabled: true,
    status: WakePlanStatus.scheduled,
    soundId: defaultWakePlanSoundId,
    vibrationEnabled: true,
    createdAt: now,
    updatedAt: now,
  );
}

WeekCalendarView _calendar(WidgetTester tester) {
  return tester.widget<WeekCalendarView>(find.byType(WeekCalendarView));
}

Future<void> _pinch(
  WidgetTester tester,
  Finder surface, {
  required double startDistance,
  required double endDistance,
}) async {
  final center = tester.getCenter(surface);
  final first = await tester.createGesture(pointer: 1);
  final second = await tester.createGesture(pointer: 2);
  await first.down(center - Offset(0, startDistance / 2));
  await second.down(center + Offset(0, startDistance / 2));
  await first.moveTo(center - Offset(0, endDistance / 2));
  await second.moveTo(center + Offset(0, endDistance / 2));
  await tester.pumpAndSettle();
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

class _DelayedWakePlanService extends WakePlanService {
  _DelayedWakePlanService({
    required super.repository,
    required super.nativeAlarmGateway,
    required DateTime Function() clock,
  }) : super(clock: clock);

  final Completer<void> release = Completer<void>();
  int createCalls = 0;

  @override
  Future<WakePlanSchedulingResult> createPlan(WakePlan plan) async {
    createCalls += 1;
    await release.future;
    return super.createPlan(plan);
  }
}

class _RevokingScheduleGateway extends FakeNativeAlarmGateway {
  var capabilityChecks = 0;

  @override
  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  ) {
    capability = const NativeAlarmCapability(
      permissionStatus: NativeAlarmPermissionStatus.denied,
      canScheduleAlarms: false,
      canRequestPermission: true,
      requiresExactAlarmPermission: true,
      supportsInventory: true,
    );
    return super.scheduleOccurrences(occurrences);
  }

  @override
  Future<NativeAlarmCapability> getCapability() {
    capabilityChecks += 1;
    return super.getCapability();
  }
}
