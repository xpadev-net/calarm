import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../model/week_calendar_interaction.dart';
import 'week_calendar_continuous_day_pager.dart';
import 'week_calendar_grid_widgets.dart';
import 'week_calendar_infinite_day_scroller.dart';
import 'week_calendar_week_page.dart';

typedef WeekCalendarTapCallback =
    void Function(WeekCalendarTapTarget target, WeekRange week);
typedef WeekCalendarWakePlanTapCallback =
    void Function(WeekCalendarWakePlanTapTarget target);
typedef WeekCalendarHourHeightChanged = void Function(double hourHeight);
typedef WeekCalendarDraftChanged = void Function(WeekCalendarDraft draft);

class WeekCalendarView extends StatefulWidget {
  const WeekCalendarView({
    super.key,
    required this.now,
    this.initialWeek,
    this.wakePlans = const [],
    this.holidays = const {},
    this.exceptionsByWakePlanId = const {},
    this.onTargetTap,
    this.onWakePlanTap,
    this.height = 420,
    this.hourHeight = 56,
    this.visibleDays = DateTime.daysPerWeek,
    this.onHourHeightChanged,
    this.draft,
    this.onDraftChanged,
    this.draftInteractionEnabled = true,
    this.recenterRequest = 0,
    this.draftDuration = defaultWakePlanStartOffset,
    this.bottomPadding = 0,
  });

  final DateTime now;
  final WeekRange? initialWeek;
  final List<WakePlan> wakePlans;

  /// Public holiday dates for the region(s) configured in Settings. A wake
  /// plan with `skipHolidays` enabled excludes these from both its rendered
  /// blocks and its actual scheduling — see [WakePlan.occursOnConsideringHolidays].
  final Set<CalendarDay> holidays;

  /// Per-occurrence skip/move exceptions, keyed by wake plan id — see
  /// [WakePlanOccurrenceException]. Suppresses the natural block for an
  /// excepted day and, for a moved occurrence, renders its block at the new
  /// day/time instead.
  final Map<String, List<WakePlanOccurrenceException>> exceptionsByWakePlanId;
  final WeekCalendarTapCallback? onTargetTap;
  final WeekCalendarWakePlanTapCallback? onWakePlanTap;
  final double height;
  final double hourHeight;
  final int visibleDays;

  /// Extra scrollable space reserved at the bottom of the day grid, so the
  /// last hour row can still be scrolled clear of a system bar the calendar
  /// is otherwise drawn behind.
  final double bottomPadding;
  final WeekCalendarHourHeightChanged? onHourHeightChanged;
  final WeekCalendarDraft? draft;
  final WeekCalendarDraftChanged? onDraftChanged;
  final bool draftInteractionEnabled;
  final int recenterRequest;

  /// The duration a tap-to-create draft will actually get (before snapping
  /// to [weekCalendarDraftSnapInterval] and clamping to the allowed range).
  /// Used only to size the tap-down preview cell so it matches the draft
  /// that tapping up will create.
  final Duration draftDuration;

  @override
  State<WeekCalendarView> createState() => _WeekCalendarViewState();
}

class _WeekCalendarViewState extends State<WeekCalendarView> {
  static const int _initialPage = 10000;
  static const double _timeAxisWidth = 52;

  late final WeekCalendarPage _initialCalendarPage;
  late final PageController _pageController;
  late final ValueNotifier<double> _axisOffset;
  late int _appliedRecenterRequest;
  late int _recenterPageIndex;
  late int _currentPageIndex;
  // The exact vertical offset a recenter jump targets, computed once here
  // and handed down to the target page instead of letting it recompute its
  // own — otherwise the fixed axis (updated from this value immediately)
  // and the page's own scroll jump (applied a frame later, independently
  // derived) could land on very slightly different offsets and visibly
  // desync for a frame.
  double? _recenterTargetOffset;
  final Map<int, ScrollController> _pageScrollControllers = {};
  VoidCallback? _removeActiveScrollListener;
  bool _pinching = false;

  @override
  void initState() {
    super.initState();
    _initialCalendarPage = WeekCalendarPage(
      week:
          widget.initialWeek ??
          currentCalendarRange(widget.now, visibleDays: widget.visibleDays),
    );
    _currentPageIndex = _initialPage;
    _pageController = PageController(initialPage: _initialPage)
      ..addListener(_handlePageControllerChanged);
    final axisTarget = initialWeekCalendarScrollTarget(
      week: _initialCalendarPage.week,
      now: widget.now,
      pixelsPerMinute: widget.hourHeight / TimeOfDayMinutes.minutesPerHour,
    );
    _axisOffset = ValueNotifier<double>(axisTarget.offset);
    _appliedRecenterRequest = widget.recenterRequest;
    _recenterPageIndex = _pageIndexForDay(CalendarDay.fromDateTime(widget.now));
  }

  @override
  void didUpdateWidget(covariant WeekCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recenterRequest != widget.recenterRequest) {
      _recenterPageIndex = _pageIndexForDay(
        CalendarDay.fromDateTime(widget.now),
      );
      // Computed synchronously, before this build, so the target page
      // (rebuilt with the new recenterRequest this same frame) and the
      // fixed axis both see the fresh target instead of the previous
      // recenter's — the actual scroll jump still has to wait a frame (the
      // target page's ScrollController may not exist yet), but the value
      // it jumps to must not.
      final target = initialWeekCalendarScrollTarget(
        week: currentCalendarRange(widget.now, visibleDays: widget.visibleDays),
        now: widget.now,
        pixelsPerMinute: widget.hourHeight / TimeOfDayMinutes.minutesPerHour,
      );
      _recenterTargetOffset = target.offset;
      _axisOffset.value = target.offset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyRecenterRequest();
      });
    }
  }

  @override
  void dispose() {
    _removeActiveScrollListener?.call();
    _pageController.removeListener(_handlePageControllerChanged);
    _pageController.dispose();
    _axisOffset.dispose();
    super.dispose();
  }

  void _handlePageControllerChanged() {
    final page = _pageController.page;
    if (page == null) {
      return;
    }
    final rounded = page.round();
    if (rounded != _currentPageIndex) {
      _currentPageIndex = rounded;
      _updateActiveScrollSync();
    }
  }

  // Only the page the PageController currently reports as active drives the
  // fixed axis: PageView.builder constructs the neighboring page as soon as
  // a swipe starts, and that neighbor's own scroll position (e.g. "today" vs
  // a default 05:00 target) would otherwise fight with the visible page's.
  void _registerPageScrollController(
    int pageIndex,
    ScrollController? controller,
  ) {
    if (controller == null) {
      _pageScrollControllers.remove(pageIndex);
    } else {
      _pageScrollControllers[pageIndex] = controller;
    }
    if (pageIndex == _currentPageIndex) {
      _updateActiveScrollSync();
    }
  }

  void _updateActiveScrollSync() {
    _removeActiveScrollListener?.call();
    _removeActiveScrollListener = null;
    final controller = _pageScrollControllers[_currentPageIndex];
    if (controller == null) {
      return;
    }
    void listener() {
      if (!mounted || !controller.hasClients) {
        return;
      }
      _axisOffset.value = controller.offset;
    }

    controller.addListener(listener);
    _removeActiveScrollListener = () => controller.removeListener(listener);
    // Registration/page-index changes can happen while a descendant is
    // still being built or laid out, so defer the initial read a frame
    // rather than mutating the notifier synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) => listener());
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: widget.visibleDays == 1
            ? WeekCalendarInfiniteDayScroller(
                anchorDay: _initialCalendarPage.week.start,
                now: widget.now,
                wakePlans: widget.wakePlans,
                holidays: widget.holidays,
                exceptionsByWakePlanId: widget.exceptionsByWakePlanId,
                onTargetTap: widget.onTargetTap,
                onWakePlanTap: widget.onWakePlanTap,
                hourHeight: widget.hourHeight,
                onHourHeightChanged: widget.onHourHeightChanged,
                draftDuration: widget.draftDuration,
                draft: widget.draft,
                onDraftChanged: widget.onDraftChanged,
                draftInteractionEnabled: widget.draftInteractionEnabled,
                recenterRequest: widget.recenterRequest,
              )
            : widget.visibleDays != DateTime.daysPerWeek
            ? WeekCalendarContinuousDayPager(
                anchorDay: _initialCalendarPage.week.start,
                visibleDays: widget.visibleDays,
                now: widget.now,
                wakePlans: widget.wakePlans,
                holidays: widget.holidays,
                exceptionsByWakePlanId: widget.exceptionsByWakePlanId,
                onTargetTap: widget.onTargetTap,
                onWakePlanTap: widget.onWakePlanTap,
                hourHeight: widget.hourHeight,
                onHourHeightChanged: widget.onHourHeightChanged,
                draftDuration: widget.draftDuration,
                draft: widget.draft,
                onDraftChanged: widget.onDraftChanged,
                draftInteractionEnabled: widget.draftInteractionEnabled,
                recenterRequest: widget.recenterRequest,
                bottomPadding: widget.bottomPadding,
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The time axis lives outside the horizontally paging
                  // content so it stays put while the user swipes between
                  // days/weeks; only its vertical position tracks the active
                  // page's scroll.
                  SizedBox(
                    key: const ValueKey('week-calendar-fixed-time-axis'),
                    width: _timeAxisWidth,
                    child: Column(
                      children: [
                        // An invisible header cell reserves exactly the
                        // space the real (visible, paging) header takes,
                        // including under text scaling, without hardcoding a
                        // pixel height that could overflow or leave a gap.
                        const Opacity(
                          opacity: 0,
                          child: IgnorePointer(
                            child: WeekCalendarDateHeaderSizingProbe(),
                          ),
                        ),
                        Expanded(
                          child: ClipRect(
                            child: ValueListenableBuilder<double>(
                              valueListenable: _axisOffset,
                              builder: (context, offset, _) {
                                return Stack(
                                  children: [
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      top: -offset,
                                      height:
                                          widget.hourHeight *
                                          TimeOfDayMinutes.hoursPerDay,
                                      child: WeekCalendarTimeAxis(
                                        hourHeight: widget.hourHeight,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      physics: _pinching || widget.draft != null
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      itemBuilder: (context, index) {
                        final week = _initialCalendarPage
                            .addPages(index - _initialPage)
                            .week;
                        return WeekCalendarWeekPage(
                          key: ValueKey<CalendarDay>(week.start),
                          week: week,
                          now: widget.now,
                          wakePlans: widget.wakePlans,
                          holidays: widget.holidays,
                          exceptionsByWakePlanId: widget.exceptionsByWakePlanId,
                          onTargetTap: widget.onTargetTap,
                          onWakePlanTap: widget.onWakePlanTap,
                          hourHeight: widget.hourHeight,
                          draftDuration: widget.draftDuration,
                          onHourHeightChanged: widget.onHourHeightChanged,
                          onPinchStateChanged: _setPinching,
                          draft: widget.draft,
                          onDraftChanged: widget.onDraftChanged,
                          draftInteractionEnabled:
                              widget.draftInteractionEnabled,
                          recenterRequest: index == _recenterPageIndex
                              ? widget.recenterRequest
                              : null,
                          recenterTargetOffset: index == _recenterPageIndex
                              ? _recenterTargetOffset
                              : null,
                          pageIndex: index,
                          onScrollControllerReady:
                              _registerPageScrollController,
                          bottomPadding: widget.bottomPadding,
                          // A page being (re)built to satisfy a recenter
                          // request must compute its own "now"-accurate
                          // target; every other newly built page just
                          // inherits wherever the calendar is currently
                          // scrolled to, so paging never jerks the
                          // vertical position around.
                          initialScrollOffset:
                              index == _initialPage ||
                                  index == _recenterPageIndex
                              ? null
                              : _axisOffset.value,
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _setPinching(bool pinching) {
    if (_pinching == pinching) {
      return;
    }
    setState(() {
      _pinching = pinching;
    });
  }

  void _applyRecenterRequest() {
    if (!mounted ||
        _appliedRecenterRequest == widget.recenterRequest ||
        !_pageController.hasClients) {
      return;
    }
    _pageController.jumpToPage(_recenterPageIndex);
    _appliedRecenterRequest = widget.recenterRequest;
  }

  int _pageIndexForDay(CalendarDay day) {
    final daysFromInitial = DateTime.utc(day.year, day.month, day.day)
        .difference(
          DateTime.utc(
            _initialCalendarPage.week.start.year,
            _initialCalendarPage.week.start.month,
            _initialCalendarPage.week.start.day,
          ),
        )
        .inDays;
    final step = weekCalendarPagingStepDays(
      _initialCalendarPage.week.visibleDays,
    );
    final pageDelta = (daysFromInitial / step).floor();
    return _initialPage + pageDelta;
  }
}
