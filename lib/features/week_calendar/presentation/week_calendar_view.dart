import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../core/time/time.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../model/week_calendar_interaction.dart';

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
            ? _InfiniteDayScroller(
                anchorDay: _initialCalendarPage.week.start,
                now: widget.now,
                wakePlans: widget.wakePlans,
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
            ? _ContinuousDayPager(
                anchorDay: _initialCalendarPage.week.start,
                visibleDays: widget.visibleDays,
                now: widget.now,
                wakePlans: widget.wakePlans,
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
                          child: IgnorePointer(child: _DateHeaderSizingProbe()),
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
                                      child: _TimeAxis(
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
                        return _WeekCalendarWeekPage(
                          key: ValueKey<CalendarDay>(week.start),
                          week: week,
                          now: widget.now,
                          wakePlans: widget.wakePlans,
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
                          pageIndex: index,
                          onScrollControllerReady:
                              _registerPageScrollController,
                          bottomPadding: widget.bottomPadding,
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

/// The 1-day view: instead of paging horizontally between individual days
/// with each one's vertical scroll capped at 24:00, this scrolls a single
/// continuous vertical axis of stacked day grids, so scrolling past 24:00
/// flows straight into 0:00 of the next day (and, scrolling up, into 24:00
/// of the previous day) with no page boundary.
class _InfiniteDayScroller extends StatefulWidget {
  const _InfiniteDayScroller({
    required this.anchorDay,
    required this.now,
    required this.wakePlans,
    required this.onTargetTap,
    required this.onWakePlanTap,
    required this.hourHeight,
    required this.onHourHeightChanged,
    required this.draftDuration,
    required this.draft,
    required this.onDraftChanged,
    required this.draftInteractionEnabled,
    required this.recenterRequest,
  });

  final CalendarDay anchorDay;
  final DateTime now;
  final List<WakePlan> wakePlans;
  final WeekCalendarTapCallback? onTargetTap;
  final WeekCalendarWakePlanTapCallback? onWakePlanTap;
  final double hourHeight;
  final WeekCalendarHourHeightChanged? onHourHeightChanged;
  final Duration draftDuration;
  final WeekCalendarDraft? draft;
  final WeekCalendarDraftChanged? onDraftChanged;
  final bool draftInteractionEnabled;
  final int recenterRequest;

  @override
  State<_InfiniteDayScroller> createState() => _InfiniteDayScrollerState();
}

class _InfiniteDayScrollerState extends State<_InfiniteDayScroller> {
  static const double _timeAxisWidth = 52;
  static const double _dateBadgeHeight = 32;
  static const double _minHourHeight = weekCalendarMinHourHeight;
  static const double _maxHourHeight = weekCalendarMaxHourHeight;

  late final ScrollController _scrollController;
  late final Key _centerSliverKey;
  late final ValueNotifier<CalendarDay> _visibleDay;
  late double _displayHourHeight;
  int? _appliedRecenterRequest;
  double? _pendingScrollOffset;
  double? _pinchStartDistance;
  double? _pinchStartHourHeight;
  double? _pinchStartScrollOffset;
  double? _zoomFocalY;
  bool _pinching = false;
  _DraftDragMode? _manipulatingDraftMode;
  bool get _manipulatingDraft => _manipulatingDraftMode != null;
  WeekCalendarTapTarget? _tapPreviewTarget;
  CalendarDay? _tapPreviewDay;
  final FocusNode _draftBodyFocusNode = FocusNode(
    debugLabel: 'Wake plan draft',
  );
  final FocusNode _draftStartFocusNode = FocusNode(
    debugLabel: 'Wake plan start',
  );
  final FocusNode _draftEndFocusNode = FocusNode(debugLabel: 'Wake plan end');

  double get _pixelsPerMinute {
    return _displayHourHeight / TimeOfDayMinutes.minutesPerHour;
  }

  double get _dayHeight {
    return _displayHourHeight * TimeOfDayMinutes.hoursPerDay;
  }

  @override
  void initState() {
    super.initState();
    _centerSliverKey = UniqueKey();
    _visibleDay = ValueNotifier<CalendarDay>(widget.anchorDay);
    _displayHourHeight = widget.hourHeight;
    final target = initialWeekCalendarScrollTarget(
      week: WeekRange(start: widget.anchorDay, visibleDays: 1),
      now: widget.now,
      pixelsPerMinute: _pixelsPerMinute,
    );
    _scrollController = ScrollController(initialScrollOffset: target.offset)
      ..addListener(_handleScroll);
    _appliedRecenterRequest = widget.recenterRequest;
  }

  @override
  void didUpdateWidget(covariant _InfiniteDayScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hourHeight != _displayHourHeight &&
        _scrollController.hasClients) {
      final oldPixelsPerMinute =
          _displayHourHeight / TimeOfDayMinutes.minutesPerHour;
      final focalY = _zoomFocalY ?? 0;
      final focalMinute =
          (_scrollController.offset + focalY) / oldPixelsPerMinute;
      _displayHourHeight = widget.hourHeight;
      _pendingScrollOffset = (focalMinute * _pixelsPerMinute) - focalY;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyPendingScroll();
      });
    }
    if (widget.recenterRequest != oldWidget.recenterRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyRecenterRequest();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _visibleDay.dispose();
    _draftBodyFocusNode.dispose();
    _draftStartFocusNode.dispose();
    _draftEndFocusNode.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final dayIndex = (_scrollController.offset / _dayHeight).floor();
    final day = widget.anchorDay.addDays(dayIndex);
    if (_visibleDay.value != day) {
      _visibleDay.value = day;
    }
  }

  void _applyPendingScroll() {
    final offset = _pendingScrollOffset;
    if (!mounted || offset == null || !_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(offset);
    _pendingScrollOffset = null;
    if (!_pinching) {
      _zoomFocalY = null;
    }
  }

  void _handlePinchStart(Offset focalPoint, double distance) {
    _pinchStartDistance = distance;
    _pinchStartHourHeight = _displayHourHeight;
    _pinchStartScrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0;
    _zoomFocalY = focalPoint.dy;
    setState(() {
      _pinching = true;
      _manipulatingDraftMode = null;
    });
  }

  void _handlePinchUpdate(Offset focalPoint, double distance) {
    final startDistance = _pinchStartDistance;
    final startHourHeight = _pinchStartHourHeight;
    final startScrollOffset = _pinchStartScrollOffset;
    if (startDistance == null ||
        startDistance == 0 ||
        startHourHeight == null ||
        startScrollOffset == null) {
      return;
    }

    final nextHourHeight = (startHourHeight * (distance / startDistance)).clamp(
      _minHourHeight,
      _maxHourHeight,
    );
    final hourHeightChanged = nextHourHeight != _displayHourHeight;
    final startFocalY = _zoomFocalY!;
    final focalMinute =
        (startScrollOffset + startFocalY) /
        (startHourHeight / TimeOfDayMinutes.minutesPerHour);
    final nextOffset =
        (focalMinute * (nextHourHeight / TimeOfDayMinutes.minutesPerHour)) -
        focalPoint.dy;
    // Unlike the paged view's bounded SingleChildScrollView, this scroller's
    // extents are unbounded, so the corrected offset needs no post-layout
    // clamping — applying it in the same frame as the hourHeight change
    // (inside setState) keeps the grid glued to the pinch gesture instead of
    // visibly snapping one frame late on every update.
    if (hourHeightChanged) {
      setState(() {
        _displayHourHeight = nextHourHeight;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(nextOffset);
        }
      });
      widget.onHourHeightChanged?.call(nextHourHeight);
    } else if (_scrollController.hasClients) {
      _scrollController.jumpTo(nextOffset);
    }
  }

  void _handlePinchEnd() {
    _setManipulatingDraft(null);
    _pinchStartDistance = null;
    _pinchStartHourHeight = null;
    _pinchStartScrollOffset = null;
    _zoomFocalY = null;
    if (_pinching) {
      setState(() {
        _pinching = false;
      });
    }
  }

  void _applyRecenterRequest() {
    if (!mounted ||
        _appliedRecenterRequest == widget.recenterRequest ||
        !_scrollController.hasClients) {
      return;
    }
    final today = CalendarDay.fromDateTime(widget.now);
    final target = initialWeekCalendarScrollTarget(
      week: WeekRange(start: today, visibleDays: 1),
      now: widget.now,
      pixelsPerMinute: _pixelsPerMinute,
    );
    final dayDelta = today.differenceInDays(widget.anchorDay);
    _scrollController.jumpTo((dayDelta * _dayHeight) + target.offset);
    _appliedRecenterRequest = widget.recenterRequest;
  }

  void _setManipulatingDraft(_DraftDragMode? mode) {
    if (_manipulatingDraftMode == mode) {
      return;
    }
    setState(() {
      _manipulatingDraftMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: _dateBadgeHeight,
          child: ValueListenableBuilder<CalendarDay>(
            valueListenable: _visibleDay,
            builder: (context, day, _) {
              final today = CalendarDay.fromDateTime(widget.now);
              return Align(
                alignment: Alignment.center,
                child: Text(
                  day == today
                      ? 'Today, ${_weekdayLabel(day.weekday)} ${day.day}'
                      : '${_weekdayLabel(day.weekday)} ${day.day}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              );
            },
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _timeAxisWidth,
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, _) {
                      final offset = _scrollController.hasClients
                          ? _scrollController.offset
                          : 0.0;
                      final withinDay = offset % _dayHeight;
                      return Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: -withinDay,
                            height: _dayHeight,
                            child: _TimeAxis(hourHeight: _displayHourHeight),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: _dayHeight - withinDay,
                            height: _dayHeight,
                            child: _TimeAxis(hourHeight: _displayHourHeight),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        RawGestureDetector(
                          behavior: HitTestBehavior.translucent,
                          gestures: {
                            _TwoPointerScaleGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  _TwoPointerScaleGestureRecognizer
                                >(_TwoPointerScaleGestureRecognizer.new, (
                                  recognizer,
                                ) {
                                  recognizer
                                    ..onStart = _handlePinchStart
                                    ..onUpdate = _handlePinchUpdate
                                    ..onEnd = _handlePinchEnd
                                    ..shouldContinueWaitingForSecondPointer =
                                        () => _manipulatingDraft;
                                }),
                          },
                          child: CustomScrollView(
                            controller: _scrollController,
                            center: _centerSliverKey,
                            physics: _pinching || _manipulatingDraft
                                ? const NeverScrollableScrollPhysics()
                                : const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverFixedExtentList(
                                itemExtent: _dayHeight,
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _buildDayItem(
                                    widget.anchorDay.addDays(-(index + 1)),
                                  ),
                                ),
                              ),
                              SliverFixedExtentList(
                                key: _centerSliverKey,
                                itemExtent: _dayHeight,
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _buildDayItem(
                                    widget.anchorDay.addDays(index),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildScrollSyncedOverlay(constraints),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayItem(CalendarDay day) {
    final week = WeekRange(start: day, visibleDays: 1);
    // `week` above is exactly the one on-screen day, so it's the right
    // scope for mapping a tap position to a grid cell — but it's the wrong
    // scope for `onTargetTap`, which callers use to cap how long a new
    // draft can be (see `weekCalendarClampDraftDurationToWeek`): with only
    // this single day, a tap at e.g. 23:45 would cap even a 30-minute draft
    // at 15 minutes, cut off at midnight. `_buildScrollSyncedOverlay` renders
    // a draft's full span regardless of day boundaries, so callers here only
    // need enough width to comfortably fit the longest possible draft
    // (`weekCalendarDraftMaximumDuration`, 3h) — two days is a generous
    // margin for that.
    final capWeek = WeekRange(start: day, visibleDays: 2);
    final snapIntervalMinutes = weekCalendarTapSnapIntervalMinutes(
      _displayHourHeight,
    );

    return LayoutBuilder(
      key: ValueKey<CalendarDay>(day),
      builder: (context, constraints) {
        WeekCalendarTapTarget targetFromPosition(Offset localPosition) {
          final raw = weekCalendarTapTargetFromPosition(
            week: week,
            localX: localPosition.dx,
            localY: localPosition.dy,
            gridWidth: constraints.maxWidth,
            gridHeight: _dayHeight,
            snapIntervalMinutes: snapIntervalMinutes,
          );
          return weekCalendarClampTapTargetToWeek(
            target: raw,
            week: week,
            snapIntervalMinutes: snapIntervalMinutes,
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            setState(() {
              _tapPreviewDay = day;
              _tapPreviewTarget = targetFromPosition(details.localPosition);
            });
          },
          onTapCancel: () {
            setState(() {
              _tapPreviewTarget = null;
              _tapPreviewDay = null;
            });
          },
          onTapUp: (details) {
            final target = targetFromPosition(details.localPosition);
            setState(() {
              _tapPreviewTarget = null;
              _tapPreviewDay = null;
            });
            widget.onTargetTap?.call(target, capWeek);
          },
          child: _TimeGrid(
            week: week,
            now: widget.now,
            hourHeight: _displayHourHeight,
            snapIntervalMinutes: snapIntervalMinutes,
          ),
        );
      },
    );
  }

  // Renders wake-plan blocks, the tap-preview cell, and the in-progress
  // draft as ONE shared layer scroll-synced to `_scrollController`, instead
  // of splitting them per day panel the way `_buildDayItem` used to. Each
  // day here is otherwise an independently mounted list item, so a block
  // crossing midnight previously had to be cut into two separate widgets on
  // two separate panels — unavoidably showing as two disconnected boxes,
  // only one of which was ever on screen at a time. Positioning everything
  // in one continuous coordinate space (minutes counted from `window.start`,
  // matching how the day items themselves stack via `itemExtent: _dayHeight`
  // in the sliver list above) lets a single block span the boundary exactly
  // like it does in the 3/7-day views, where multiple days already share one
  // canvas.
  Widget _buildScrollSyncedOverlay(BoxConstraints constraints) {
    return Positioned.fill(
      child: ClipRect(
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _scrollController,
              builder: (context, _) {
                final offset = _scrollController.hasClients
                    ? _scrollController.offset
                    : 0.0;
                final viewportHeight = constraints.maxHeight > 0
                    ? constraints.maxHeight
                    : 0.0;
                // A 1-day buffer on each side covers a block whose visible
                // portion pokes into the viewport from just outside it.
                final firstDayIndex = (offset / _dayHeight).floor() - 1;
                final lastDayIndex = ((offset + viewportHeight) / _dayHeight)
                    .ceil();
                final windowDays = (lastDayIndex - firstDayIndex + 2).clamp(
                  1,
                  1 << 20,
                );
                final window = WeekRange(
                  start: widget.anchorDay.addDays(firstDayIndex),
                  visibleDays: windowDays,
                );

                final blocks = weekCalendarWakePlanOverlayBlocks(
                  anchorDay: window.start,
                  window: window,
                  wakePlans: widget.wakePlans,
                );
                final previewDuration = weekCalendarBoundedDraftDuration(
                  widget.draftDuration,
                );
                final previewSegment = _overlaySegmentForTapPreview(
                  window,
                  previewDuration,
                );
                final draft = widget.draft;
                final draftSegment = draft == null
                    ? null
                    : _overlaySegmentForDraft(draft, window);

                return Positioned(
                  left: 0,
                  right: 0,
                  top: (firstDayIndex * _dayHeight) - offset,
                  height: windowDays * _dayHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final block in blocks)
                        _WakePlanBlock(
                          block: block,
                          pixelsPerMinute: _pixelsPerMinute,
                          dayWidth: constraints.maxWidth,
                          onTap: widget.onWakePlanTap,
                        ),
                      if (previewSegment != null)
                        _TapPreviewCell(
                          key: const ValueKey('week-calendar-tap-preview-cell'),
                          segment: previewSegment,
                          pixelsPerMinute: _pixelsPerMinute,
                          dayWidth: constraints.maxWidth,
                        ),
                      if (draft != null && draftSegment != null)
                        _DraftBlock(
                          key: ValueKey(
                            'week-calendar-draft-block-${draft.id}-single',
                          ),
                          draft: draft,
                          segment: draftSegment,
                          week: WeekRange(start: window.start, visibleDays: 1),
                          pixelsPerMinute: _pixelsPerMinute,
                          dayWidth: constraints.maxWidth,
                          onChanged: widget.onDraftChanged,
                          onManipulationChanged: _setManipulatingDraft,
                          interactionEnabled: widget.draftInteractionEnabled,
                          hideForActiveMove:
                              _manipulatingDraftMode == _DraftDragMode.move,
                          gridHeightOverrideMinutes:
                              windowDays * TimeOfDayMinutes.minutesPerDay,
                          bodyFocusNode: _draftBodyFocusNode,
                          startFocusNode: _draftStartFocusNode,
                          endFocusNode: _draftEndFocusNode,
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  _DraftSegment? _overlaySegmentForTapPreview(
    WeekRange window,
    Duration duration,
  ) {
    final day = _tapPreviewDay;
    final target = _tapPreviewTarget;
    if (day == null || target == null) {
      return null;
    }
    return _overlaySegmentFor(
      startAt: target.dateTime,
      durationMinutes: duration.inMinutes,
      window: window,
    );
  }

  _DraftSegment _overlaySegmentForDraft(
    WeekCalendarDraft draft,
    WeekRange window,
  ) {
    return _overlaySegmentFor(
      startAt: draft.startAt,
      durationMinutes: draft.duration.inMinutes,
      window: window,
    );
  }

  _DraftSegment _overlaySegmentFor({
    required DateTime startAt,
    required int durationMinutes,
    required WeekRange window,
  }) {
    final dayOffset = CalendarDay.fromDateTime(
      startAt,
    ).differenceInDays(window.start);
    final topMinute =
        (dayOffset * TimeOfDayMinutes.minutesPerDay) +
        (startAt.hour * TimeOfDayMinutes.minutesPerHour) +
        startAt.minute;
    return _DraftSegment(
      dayIndex: 0,
      topMinute: topMinute,
      durationMinutes: durationMinutes,
      containsStart: true,
      containsEnd: true,
    );
  }
}

/// Multi-day paged view used for widths other than 1 or 7 (currently just
/// the 3-day mode). Unlike [_WeekCalendarWeekPage]'s [PageView] (whose pages
/// are each a full [visibleDays]-wide window, so a swipe replaces the whole
/// window at once — e.g. 3/4/5 -> 4/5/6 -> 5/6/7, each requiring a full page
/// swipe even though only one day actually changes), this pages a single
/// day at a time via `PageController.viewportFraction`, so a swipe slides
/// the visible days by exactly one day, continuously, like the header cards
/// in Google Calendar.
class _ContinuousDayPager extends StatefulWidget {
  const _ContinuousDayPager({
    required this.anchorDay,
    required this.visibleDays,
    required this.now,
    required this.wakePlans,
    required this.onTargetTap,
    required this.onWakePlanTap,
    required this.hourHeight,
    required this.onHourHeightChanged,
    required this.draftDuration,
    required this.draft,
    required this.onDraftChanged,
    required this.draftInteractionEnabled,
    required this.recenterRequest,
    this.bottomPadding = 0,
  });

  final CalendarDay anchorDay;
  final int visibleDays;
  final DateTime now;
  final List<WakePlan> wakePlans;
  final WeekCalendarTapCallback? onTargetTap;
  final WeekCalendarWakePlanTapCallback? onWakePlanTap;
  final double hourHeight;
  final WeekCalendarHourHeightChanged? onHourHeightChanged;
  final Duration draftDuration;
  final WeekCalendarDraft? draft;
  final WeekCalendarDraftChanged? onDraftChanged;
  final bool draftInteractionEnabled;
  final int recenterRequest;
  final double bottomPadding;

  @override
  State<_ContinuousDayPager> createState() => _ContinuousDayPagerState();
}

class _ContinuousDayPagerState extends State<_ContinuousDayPager> {
  // A fractional viewportFraction PageView loses floating-point precision in
  // the sliver layer at very large scroll offsets (a page count of 10000, as
  // used by the full-page-width PageView elsewhere in this file, trips a
  // `sliver_fixed_extent_list.dart` assertion here) — this still covers ~11
  // years in either direction, far beyond what a user would ever swipe to.
  static const int _initialPage = 4000;
  static const double _timeAxisWidth = 52;
  static const double _minHourHeight = weekCalendarMinHourHeight;
  static const double _maxHourHeight = weekCalendarMaxHourHeight;

  late final PageController _dayPageController;
  late final ScrollController _verticalScrollController;
  late final ValueNotifier<double> _dayPage;
  late double _displayHourHeight;
  int? _appliedRecenterRequest;
  double? _pendingScrollOffset;
  double? _pinchStartDistance;
  double? _pinchStartHourHeight;
  double? _pinchStartScrollOffset;
  double? _zoomFocalY;
  bool _pinching = false;
  _DraftDragMode? _manipulatingDraftMode;
  bool get _manipulatingDraft => _manipulatingDraftMode != null;
  WeekCalendarTapTarget? _tapPreviewTarget;
  CalendarDay? _tapPreviewDay;
  final FocusNode _draftBodyFocusNode = FocusNode(
    debugLabel: 'Wake plan draft',
  );
  final FocusNode _draftStartFocusNode = FocusNode(
    debugLabel: 'Wake plan start',
  );
  final FocusNode _draftEndFocusNode = FocusNode(debugLabel: 'Wake plan end');

  double get _pixelsPerMinute {
    return _displayHourHeight / TimeOfDayMinutes.minutesPerHour;
  }

  double get _gridHeight {
    return _displayHourHeight * TimeOfDayMinutes.hoursPerDay;
  }

  // A viewportFraction < 1 PageView always centers its settled page (padding
  // both ends so the first/last pages can center too), so the day at the
  // settled page index actually lands in the *middle* column, not the left
  // one. [WeekRange]'s convention is that `anchorDay` is the leftmost day of
  // the visible window, so every page-index target below is offset by this
  // many days to compensate and keep that convention true on screen.
  int get _leftmostOffset => (widget.visibleDays - 1) ~/ 2;

  @override
  void initState() {
    super.initState();
    _dayPageController = PageController(
      viewportFraction: 1 / widget.visibleDays,
      initialPage: _initialPage + _leftmostOffset,
    )..addListener(_handleDayPageChanged);
    // PageController doesn't notify listeners just from setting
    // `initialPage` (only from an actual scroll/jump afterwards), so this
    // has to start out already matching the controller's real initial
    // position or the header renders stale until the first swipe.
    _dayPage = ValueNotifier<double>(_leftmostOffset.toDouble());
    _displayHourHeight = widget.hourHeight;
    final target = initialWeekCalendarScrollTarget(
      week: WeekRange(start: widget.anchorDay, visibleDays: 1),
      now: widget.now,
      pixelsPerMinute: _pixelsPerMinute,
    );
    _verticalScrollController = ScrollController(
      initialScrollOffset: target.offset,
    );
    _appliedRecenterRequest = widget.recenterRequest;
  }

  @override
  void didUpdateWidget(covariant _ContinuousDayPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hourHeight != _displayHourHeight &&
        _verticalScrollController.hasClients) {
      final oldPixelsPerMinute =
          _displayHourHeight / TimeOfDayMinutes.minutesPerHour;
      final focalY = _zoomFocalY ?? 0;
      final focalMinute =
          (_verticalScrollController.offset + focalY) / oldPixelsPerMinute;
      _displayHourHeight = widget.hourHeight;
      _pendingScrollOffset = (focalMinute * _pixelsPerMinute) - focalY;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyPendingScroll();
      });
    }
    if (widget.recenterRequest != oldWidget.recenterRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyRecenterRequest();
      });
    }
  }

  @override
  void dispose() {
    _dayPageController.removeListener(_handleDayPageChanged);
    _dayPageController.dispose();
    _verticalScrollController.dispose();
    _dayPage.dispose();
    _draftBodyFocusNode.dispose();
    _draftStartFocusNode.dispose();
    _draftEndFocusNode.dispose();
    super.dispose();
  }

  void _handleDayPageChanged() {
    final page = _dayPageController.page;
    if (page != null) {
      _dayPage.value = page - _initialPage;
    }
  }

  CalendarDay _dayForPageIndex(int index) {
    return widget.anchorDay.addDays(index - _initialPage);
  }

  void _applyPendingScroll() {
    final offset = _pendingScrollOffset;
    if (!mounted || offset == null || !_verticalScrollController.hasClients) {
      return;
    }
    _verticalScrollController.jumpTo(
      offset.clamp(
        _verticalScrollController.position.minScrollExtent,
        _verticalScrollController.position.maxScrollExtent,
      ),
    );
    _pendingScrollOffset = null;
    if (!_pinching) {
      _zoomFocalY = null;
    }
  }

  double _maxScrollExtentFor(double hourHeight) {
    final childHeight =
        (hourHeight * TimeOfDayMinutes.hoursPerDay) + widget.bottomPadding;
    final viewportDimension =
        _verticalScrollController.position.viewportDimension;
    return (childHeight - viewportDimension).clamp(0, double.infinity);
  }

  void _handlePinchStart(Offset focalPoint, double distance) {
    _pinchStartDistance = distance;
    _pinchStartHourHeight = _displayHourHeight;
    _pinchStartScrollOffset = _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : 0;
    _zoomFocalY = focalPoint.dy;
    setState(() {
      _pinching = true;
      _manipulatingDraftMode = null;
    });
  }

  void _handlePinchUpdate(Offset focalPoint, double distance) {
    final startDistance = _pinchStartDistance;
    final startHourHeight = _pinchStartHourHeight;
    final startScrollOffset = _pinchStartScrollOffset;
    if (startDistance == null ||
        startDistance == 0 ||
        startHourHeight == null ||
        startScrollOffset == null) {
      return;
    }

    final nextHourHeight = (startHourHeight * (distance / startDistance)).clamp(
      _minHourHeight,
      _maxHourHeight,
    );
    final hourHeightChanged = nextHourHeight != _displayHourHeight;
    final startFocalY = _zoomFocalY!;
    final focalMinute =
        (startScrollOffset + startFocalY) /
        (startHourHeight / TimeOfDayMinutes.minutesPerHour);
    final nextOffset =
        (focalMinute * (nextHourHeight / TimeOfDayMinutes.minutesPerHour)) -
        focalPoint.dy;
    if (hourHeightChanged) {
      setState(() {
        _displayHourHeight = nextHourHeight;
        if (_verticalScrollController.hasClients) {
          _verticalScrollController.jumpTo(
            nextOffset.clamp(0, _maxScrollExtentFor(nextHourHeight)),
          );
        }
      });
      widget.onHourHeightChanged?.call(nextHourHeight);
    } else if (_verticalScrollController.hasClients) {
      // See the comment on the analogous branch in
      // `_WeekCalendarWeekPageState._handlePinchUpdate`: a stale
      // `position.maxScrollExtent` from before this frame's relayout would
      // clamp the focal-preserving offset down to the previous hourHeight's
      // bounds when consecutive updates saturate at the same clamped
      // hourHeight.
      _verticalScrollController.jumpTo(
        nextOffset.clamp(0, _maxScrollExtentFor(nextHourHeight)),
      );
    }
  }

  void _handlePinchEnd() {
    _setManipulatingDraft(null);
    _pinchStartDistance = null;
    _pinchStartHourHeight = null;
    _pinchStartScrollOffset = null;
    _zoomFocalY = null;
    if (_pinching) {
      setState(() {
        _pinching = false;
      });
    }
  }

  void _applyRecenterRequest() {
    if (!mounted || _appliedRecenterRequest == widget.recenterRequest) {
      return;
    }
    final today = CalendarDay.fromDateTime(widget.now);
    if (_dayPageController.hasClients) {
      _dayPageController.jumpToPage(
        _initialPage +
            _leftmostOffset +
            today.differenceInDays(widget.anchorDay),
      );
    }
    if (_verticalScrollController.hasClients) {
      final target = initialWeekCalendarScrollTarget(
        week: WeekRange(start: today, visibleDays: 1),
        now: widget.now,
        pixelsPerMinute: _pixelsPerMinute,
      );
      _verticalScrollController.jumpTo(
        target.offset.clamp(
          _verticalScrollController.position.minScrollExtent,
          _verticalScrollController.position.maxScrollExtent,
        ),
      );
    }
    _appliedRecenterRequest = widget.recenterRequest;
  }

  void _setManipulatingDraft(_DraftDragMode? mode) {
    if (_manipulatingDraftMode == mode) {
      return;
    }
    setState(() {
      _manipulatingDraftMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            const Opacity(
              opacity: 0,
              child: IgnorePointer(child: _DateHeaderSizingProbe()),
            ),
            Positioned.fill(
              child: Row(
                children: [
                  const SizedBox(width: _timeAxisWidth),
                  Expanded(
                    child: _ScrollSyncedDateHeader(
                      pageListenable: _dayPage,
                      anchorDay: widget.anchorDay,
                      visibleDays: widget.visibleDays,
                      now: widget.now,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _timeAxisWidth,
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _verticalScrollController,
                    builder: (context, _) {
                      final offset = _verticalScrollController.hasClients
                          ? _verticalScrollController.offset
                          : 0.0;
                      return Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: -offset,
                            height: _gridHeight,
                            child: _TimeAxis(hourHeight: _displayHourHeight),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: RawGestureDetector(
                  key: const ValueKey('week-calendar-pinch-surface'),
                  behavior: HitTestBehavior.translucent,
                  gestures: {
                    _TwoPointerScaleGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          _TwoPointerScaleGestureRecognizer
                        >(_TwoPointerScaleGestureRecognizer.new, (recognizer) {
                          recognizer
                            ..onStart = _handlePinchStart
                            ..onUpdate = _handlePinchUpdate
                            ..onEnd = _handlePinchEnd
                            ..shouldContinueWaitingForSecondPointer = () =>
                                _manipulatingDraft;
                        }),
                  },
                  child: Scrollbar(
                    controller: _verticalScrollController,
                    child: SingleChildScrollView(
                      controller: _verticalScrollController,
                      physics: _pinching || _manipulatingDraft
                          ? const NeverScrollableScrollPhysics()
                          : const _PreserveVisibleTimeScrollPhysics(),
                      child: Padding(
                        padding: EdgeInsets.only(bottom: widget.bottomPadding),
                        child: SizedBox(
                          height: _gridHeight,
                          child: PageView.builder(
                            controller: _dayPageController,
                            physics: _pinching || widget.draft != null
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            itemBuilder: (context, index) =>
                                _buildDayItem(_dayForPageIndex(index)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayItem(CalendarDay day) {
    final week = WeekRange(start: day, visibleDays: 1);
    // `week` is exactly the one on-screen day, right for mapping a tap
    // position to a grid cell but wrong for `onTargetTap`'s duration/movement
    // clamps (see `weekCalendarClampDraftDurationToWeek`): with only this
    // single day, a tap at e.g. 23:45 would cap even a 30-minute draft at 15
    // minutes, cut off at midnight. Give callers a wider scope so a draft
    // started or dragged near midnight isn't truncated or shifted entirely
    // into this one day.
    final capWeek = WeekRange(start: day, visibleDays: 2);
    final blocks = weekCalendarWakePlanBlocks(
      week: week,
      wakePlans: widget.wakePlans,
    );
    final snapIntervalMinutes = weekCalendarTapSnapIntervalMinutes(
      _displayHourHeight,
    );
    final previewDuration = weekCalendarBoundedDraftDuration(
      widget.draftDuration,
    );
    final draft = widget.draft;
    final draftSegments = draft == null
        ? const <_DraftSegment>[]
        : _draftSegments(draft, week);

    return LayoutBuilder(
      key: ValueKey<CalendarDay>(day),
      builder: (context, constraints) {
        WeekCalendarTapTarget targetFromPosition(Offset localPosition) {
          final raw = weekCalendarTapTargetFromPosition(
            week: week,
            localX: localPosition.dx,
            localY: localPosition.dy,
            gridWidth: constraints.maxWidth,
            gridHeight: _gridHeight,
            snapIntervalMinutes: snapIntervalMinutes,
          );
          return weekCalendarClampTapTargetToWeek(
            target: raw,
            week: week,
            snapIntervalMinutes: snapIntervalMinutes,
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            setState(() {
              _tapPreviewDay = day;
              _tapPreviewTarget = targetFromPosition(details.localPosition);
            });
          },
          onTapCancel: () {
            setState(() {
              _tapPreviewTarget = null;
              _tapPreviewDay = null;
            });
          },
          onTapUp: (details) {
            final target = targetFromPosition(details.localPosition);
            setState(() {
              _tapPreviewTarget = null;
              _tapPreviewDay = null;
            });
            widget.onTargetTap?.call(target, capWeek);
          },
          child: Stack(
            children: [
              _TimeGrid(
                week: week,
                now: widget.now,
                hourHeight: _displayHourHeight,
                snapIntervalMinutes: snapIntervalMinutes,
              ),
              if (_tapPreviewDay == day)
                if (_tapPreviewTarget case final preview?)
                  for (final segment in _tapPreviewSegments(
                    target: preview,
                    duration: previewDuration,
                    week: week,
                  ))
                    _TapPreviewCell(
                      key: const ValueKey('week-calendar-tap-preview-cell'),
                      segment: segment,
                      pixelsPerMinute: _pixelsPerMinute,
                      dayWidth: constraints.maxWidth,
                    ),
              for (final block in blocks)
                _WakePlanBlock(
                  block: block,
                  pixelsPerMinute: _pixelsPerMinute,
                  dayWidth: constraints.maxWidth,
                  onTap: widget.onWakePlanTap,
                ),
              if (draft != null)
                for (final segment in draftSegments)
                  _DraftBlock(
                    key: ValueKey(
                      'week-calendar-draft-block-'
                      '${draft.id}-'
                      '${_draftSegmentRole(segment)}',
                    ),
                    draft: draft,
                    segment: segment,
                    week: week,
                    pixelsPerMinute: _pixelsPerMinute,
                    dayWidth: constraints.maxWidth,
                    onChanged: widget.onDraftChanged,
                    onManipulationChanged: _setManipulatingDraft,
                    interactionEnabled: widget.draftInteractionEnabled,
                    hideForActiveMove:
                        _manipulatingDraftMode == _DraftDragMode.move,
                    bodyFocusNode: segment.containsStart
                        ? _draftBodyFocusNode
                        : null,
                    startFocusNode: segment.containsStart
                        ? _draftStartFocusNode
                        : null,
                    endFocusNode: segment.containsEnd
                        ? _draftEndFocusNode
                        : null,
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// Renders the sliding row of date headers above [_ContinuousDayPager]'s
/// grid, mirroring [pageListenable]'s continuous page position exactly so
/// the header stays glued to the day columns beneath it — the same
/// fixed-widget-follows-scroll trick used for the calendar's time axis,
/// applied horizontally instead of vertically.
class _ScrollSyncedDateHeader extends StatelessWidget {
  const _ScrollSyncedDateHeader({
    required this.pageListenable,
    required this.anchorDay,
    required this.visibleDays,
    required this.now,
  });

  final ValueListenable<double> pageListenable;
  final CalendarDay anchorDay;
  final int visibleDays;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = CalendarDay.fromDateTime(now);
    // Mirrors the settled-page centering compensation in
    // _ContinuousDayPagerState._leftmostOffset — the underlying PageView
    // centers its current page, so item positions here need the same
    // leftward shift to keep `anchorDay` visually leftmost.
    final leftmostOffset = (visibleDays - 1) ~/ 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = constraints.maxWidth / visibleDays;
        return ClipRect(
          child: ValueListenableBuilder<double>(
            valueListenable: pageListenable,
            builder: (context, page, _) {
              final baseIndex = page.floor();
              final fraction = page - baseIndex;
              return Stack(
                children: [
                  for (var i = -1; i <= visibleDays; i++)
                    Positioned(
                      left: (leftmostOffset + i - fraction) * dayWidth,
                      width: dayWidth,
                      top: 0,
                      bottom: 0,
                      child: Builder(
                        builder: (context) {
                          final day = anchorDay.addDays(baseIndex + i);
                          return _DateHeaderCell(
                            weekdayLabel: _weekdayLabel(day.weekday),
                            dayLabel: '${day.day}',
                            highlighted: day == today,
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _WeekCalendarWeekPage extends StatefulWidget {
  const _WeekCalendarWeekPage({
    super.key,
    required this.week,
    required this.now,
    required this.wakePlans,
    required this.onTargetTap,
    required this.onWakePlanTap,
    required this.hourHeight,
    required this.draftDuration,
    required this.onHourHeightChanged,
    required this.onPinchStateChanged,
    required this.draft,
    required this.onDraftChanged,
    required this.draftInteractionEnabled,
    required this.recenterRequest,
    required this.pageIndex,
    required this.onScrollControllerReady,
    this.bottomPadding = 0,
  });

  final WeekRange week;
  final DateTime now;
  final List<WakePlan> wakePlans;
  final WeekCalendarTapCallback? onTargetTap;
  final WeekCalendarWakePlanTapCallback? onWakePlanTap;
  final double hourHeight;
  final Duration draftDuration;
  final WeekCalendarHourHeightChanged? onHourHeightChanged;
  final ValueChanged<bool> onPinchStateChanged;
  final WeekCalendarDraft? draft;
  final WeekCalendarDraftChanged? onDraftChanged;
  final bool draftInteractionEnabled;
  final int? recenterRequest;
  final int pageIndex;
  final void Function(int pageIndex, ScrollController? controller)
  onScrollControllerReady;
  final double bottomPadding;

  @override
  State<_WeekCalendarWeekPage> createState() => _WeekCalendarWeekPageState();
}

class _WeekCalendarWeekPageState extends State<_WeekCalendarWeekPage> {
  static const double _minHourHeight = weekCalendarMinHourHeight;
  static const double _maxHourHeight = weekCalendarMaxHourHeight;

  late final ScrollController _scrollController;
  late double _displayHourHeight;
  int? _appliedRecenterRequest;
  double? _pendingScrollOffset;
  double? _pinchStartDistance;
  double? _pinchStartHourHeight;
  double? _pinchStartScrollOffset;
  double? _zoomFocalY;
  bool _pinching = false;
  _DraftDragMode? _manipulatingDraftMode;
  bool get _manipulatingDraft => _manipulatingDraftMode != null;
  WeekCalendarTapTarget? _tapPreviewTarget;
  final FocusNode _draftBodyFocusNode = FocusNode(
    debugLabel: 'Wake plan draft',
  );
  final FocusNode _draftStartFocusNode = FocusNode(
    debugLabel: 'Wake plan start',
  );
  final FocusNode _draftEndFocusNode = FocusNode(debugLabel: 'Wake plan end');

  double get _pixelsPerMinute {
    return _displayHourHeight / TimeOfDayMinutes.minutesPerHour;
  }

  @override
  void initState() {
    super.initState();
    _displayHourHeight = widget.hourHeight;
    final target = initialWeekCalendarScrollTarget(
      week: widget.week,
      now: widget.now,
      pixelsPerMinute: _pixelsPerMinute,
    );
    _scrollController = ScrollController(initialScrollOffset: target.offset);
    _appliedRecenterRequest = widget.recenterRequest;
    widget.onScrollControllerReady(widget.pageIndex, _scrollController);
  }

  @override
  void didUpdateWidget(covariant _WeekCalendarWeekPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hourHeight != _displayHourHeight &&
        _scrollController.hasClients) {
      final oldPixelsPerMinute =
          _displayHourHeight / TimeOfDayMinutes.minutesPerHour;
      final focalY = _zoomFocalY ?? 0;
      final focalMinute =
          (_scrollController.offset + focalY) / oldPixelsPerMinute;
      _displayHourHeight = widget.hourHeight;
      _pendingScrollOffset = (focalMinute * _pixelsPerMinute) - focalY;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyPendingScroll();
      });
    }
    if (widget.recenterRequest != null &&
        oldWidget.recenterRequest != widget.recenterRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyRecenterScroll();
      });
    }
  }

  void _applyPendingScroll() {
    final offset = _pendingScrollOffset;
    if (!mounted || offset == null || !_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(
      offset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
    );
    _pendingScrollOffset = null;
    if (!_pinching) {
      _zoomFocalY = null;
    }
  }

  void _handlePinchStart(Offset focalPoint, double distance) {
    _pinchStartDistance = distance;
    _pinchStartHourHeight = _displayHourHeight;
    _pinchStartScrollOffset = _scrollController.offset;
    _zoomFocalY = focalPoint.dy;
    setState(() {
      _pinching = true;
      _manipulatingDraftMode = null;
    });
    widget.onPinchStateChanged(true);
  }

  void _handlePinchUpdate(Offset focalPoint, double distance) {
    final startDistance = _pinchStartDistance;
    final startHourHeight = _pinchStartHourHeight;
    final startScrollOffset = _pinchStartScrollOffset;
    if (startDistance == null ||
        startDistance == 0 ||
        startHourHeight == null ||
        startScrollOffset == null) {
      return;
    }

    final nextHourHeight = (startHourHeight * (distance / startDistance)).clamp(
      _minHourHeight,
      _maxHourHeight,
    );
    final hourHeightChanged = nextHourHeight != _displayHourHeight;
    final startFocalY = _zoomFocalY!;
    final focalMinute =
        (startScrollOffset + startFocalY) /
        (startHourHeight / TimeOfDayMinutes.minutesPerHour);
    final nextOffset =
        (focalMinute * (nextHourHeight / TimeOfDayMinutes.minutesPerHour)) -
        focalPoint.dy;
    // The child's new height can be computed analytically (hourHeight * 24h
    // + bottom padding) without waiting for a relayout, and the viewport
    // dimension doesn't change from a hourHeight-only resize — so the
    // corrected, clamped offset can be applied in the same frame as the
    // hourHeight change (inside setState) instead of one frame later, which
    // otherwise shows as a visible snap-back on every pinch update.
    if (hourHeightChanged) {
      setState(() {
        _displayHourHeight = nextHourHeight;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            nextOffset.clamp(0, _maxScrollExtentFor(nextHourHeight)),
          );
        }
      });
      widget.onHourHeightChanged?.call(nextHourHeight);
    } else if (_scrollController.hasClients) {
      // Even when this update lands on the same clamped hourHeight as the
      // last one (e.g. two pinch updates in a row both saturating at
      // `_maxHourHeight` before a frame has been pumped in between), the
      // real `position.maxScrollExtent` can still reflect the *previous*
      // hourHeight's layout — Flutter hasn't relaid the child out yet. Use
      // the same analytic estimate as above instead of that stale value, or
      // the focal point drifts on the very next update after saturating.
      _scrollController.jumpTo(
        nextOffset.clamp(0, _maxScrollExtentFor(nextHourHeight)),
      );
    }
  }

  double _maxScrollExtentFor(double hourHeight) {
    final childHeight =
        (hourHeight * TimeOfDayMinutes.hoursPerDay) + widget.bottomPadding;
    final viewportDimension = _scrollController.position.viewportDimension;
    return (childHeight - viewportDimension).clamp(0, double.infinity);
  }

  void _handlePinchEnd() {
    // A cross-day move can replace the draft segment that received the pointer
    // down before it sees the matching up/cancel. The page-level recognizer
    // stays mounted for the whole gesture, so it owns the cleanup guarantee.
    _setManipulatingDraft(null);
    _pinchStartDistance = null;
    _pinchStartHourHeight = null;
    _pinchStartScrollOffset = null;
    _zoomFocalY = null;
    if (_pinching) {
      setState(() {
        _pinching = false;
      });
      widget.onPinchStateChanged(false);
    }
  }

  void _setManipulatingDraft(_DraftDragMode? mode) {
    if (_manipulatingDraftMode == mode) {
      return;
    }
    setState(() {
      _manipulatingDraftMode = mode;
    });
  }

  @override
  void dispose() {
    widget.onScrollControllerReady(widget.pageIndex, null);
    _draftBodyFocusNode.dispose();
    _draftStartFocusNode.dispose();
    _draftEndFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applyRecenterScroll() {
    if (!mounted ||
        _appliedRecenterRequest == widget.recenterRequest ||
        !_scrollController.hasClients) {
      return;
    }
    final target = initialWeekCalendarScrollTarget(
      week: widget.week,
      now: widget.now,
      pixelsPerMinute: _pixelsPerMinute,
    );
    final boundedOffset = target.offset.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(boundedOffset);
    _appliedRecenterRequest = widget.recenterRequest;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = weekCalendarWakePlanBlocks(
      week: widget.week,
      wakePlans: widget.wakePlans,
    );
    final snapIntervalMinutes = weekCalendarTapSnapIntervalMinutes(
      _displayHourHeight,
    );
    final previewDuration = weekCalendarBoundedDraftDuration(
      widget.draftDuration,
    );

    return Column(
      children: [
        _DateHeader(week: widget.week, now: widget.now),
        Expanded(
          child: RawGestureDetector(
            key: const ValueKey('week-calendar-pinch-surface'),
            behavior: HitTestBehavior.translucent,
            gestures: {
              _TwoPointerScaleGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _TwoPointerScaleGestureRecognizer
                  >(_TwoPointerScaleGestureRecognizer.new, (recognizer) {
                    recognizer
                      ..onStart = _handlePinchStart
                      ..onUpdate = _handlePinchUpdate
                      ..onEnd = _handlePinchEnd
                      ..shouldContinueWaitingForSecondPointer = () =>
                          _manipulatingDraft;
                  }),
            },
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: _pinching || _manipulatingDraft
                    ? const NeverScrollableScrollPhysics()
                    : const _PreserveVisibleTimeScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.only(bottom: widget.bottomPadding),
                  child: SizedBox(
                    height: _displayHourHeight * TimeOfDayMinutes.hoursPerDay,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final gridHeight =
                            _displayHourHeight * TimeOfDayMinutes.hoursPerDay;
                        WeekCalendarTapTarget targetFromPosition(
                          Offset localPosition,
                        ) {
                          final raw = weekCalendarTapTargetFromPosition(
                            week: widget.week,
                            localX: localPosition.dx,
                            localY: localPosition.dy,
                            gridWidth: constraints.maxWidth,
                            gridHeight: gridHeight,
                            snapIntervalMinutes: snapIntervalMinutes,
                          );
                          // Used for both the tap-preview cell and the target
                          // actually handed to onTargetTap, so a tap that
                          // rounds past the visible range always creates its
                          // draft where the preview showed it landing.
                          return weekCalendarClampTapTargetToWeek(
                            target: raw,
                            week: widget.week,
                            snapIntervalMinutes: snapIntervalMinutes,
                          );
                        }

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) {
                            setState(() {
                              _tapPreviewTarget = targetFromPosition(
                                details.localPosition,
                              );
                            });
                          },
                          onTapCancel: () {
                            setState(() {
                              _tapPreviewTarget = null;
                            });
                          },
                          onTapUp: (details) {
                            final target = targetFromPosition(
                              details.localPosition,
                            );
                            setState(() {
                              _tapPreviewTarget = null;
                            });
                            widget.onTargetTap?.call(target, widget.week);
                          },
                          child: Stack(
                            children: [
                              _TimeGrid(
                                week: widget.week,
                                now: widget.now,
                                hourHeight: _displayHourHeight,
                                snapIntervalMinutes: snapIntervalMinutes,
                              ),
                              if (_tapPreviewTarget case final preview?)
                                for (final segment in _tapPreviewSegments(
                                  target: preview,
                                  duration: previewDuration,
                                  week: widget.week,
                                ))
                                  _TapPreviewCell(
                                    key: ValueKey(
                                      segment.containsStart
                                          ? 'week-calendar-tap-preview-cell'
                                          : 'week-calendar-tap-preview-cell-'
                                                'continuation-'
                                                '${segment.dayIndex}',
                                    ),
                                    segment: segment,
                                    pixelsPerMinute: _pixelsPerMinute,
                                    dayWidth:
                                        constraints.maxWidth /
                                        widget.week.visibleDays,
                                  ),
                              for (final block in blocks)
                                _WakePlanBlock(
                                  block: block,
                                  pixelsPerMinute: _pixelsPerMinute,
                                  dayWidth:
                                      constraints.maxWidth /
                                      widget.week.visibleDays,
                                  onTap: widget.onWakePlanTap,
                                ),
                              if (widget.draft case final draft?)
                                for (final segment in _draftSegments(
                                  draft,
                                  widget.week,
                                ))
                                  _DraftBlock(
                                    key: ValueKey(
                                      'week-calendar-draft-block-'
                                      '${draft.id}-'
                                      '${_draftSegmentRole(segment)}',
                                    ),
                                    draft: draft,
                                    segment: segment,
                                    week: widget.week,
                                    pixelsPerMinute: _pixelsPerMinute,
                                    dayWidth:
                                        constraints.maxWidth /
                                        widget.week.visibleDays,
                                    onChanged: widget.onDraftChanged,
                                    onManipulationChanged:
                                        _setManipulatingDraft,
                                    interactionEnabled:
                                        !_pinching &&
                                        widget.draftInteractionEnabled,
                                    hideForActiveMove:
                                        _manipulatingDraftMode ==
                                        _DraftDragMode.move,
                                    bodyFocusNode: segment.containsStart
                                        ? _draftBodyFocusNode
                                        : null,
                                    startFocusNode: segment.containsStart
                                        ? _draftStartFocusNode
                                        : null,
                                    endFocusNode: segment.containsEnd
                                        ? _draftEndFocusNode
                                        : null,
                                  ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreserveVisibleTimeScrollPhysics extends ScrollPhysics {
  const _PreserveVisibleTimeScrollPhysics({super.parent});

  @override
  _PreserveVisibleTimeScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _PreserveVisibleTimeScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    return oldPosition.pixels
        .clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent)
        .toDouble();
  }
}

typedef _TwoPointerScaleStart =
    void Function(Offset focalPoint, double distance);
typedef _TwoPointerScaleUpdate =
    void Function(Offset focalPoint, double distance);

/// Gives a second touch a chance to join the first touch before a nested
/// horizontal or vertical drag wins its gesture arena.
///
/// A single touch is released as soon as it moves beyond pan slop, so ordinary
/// scrolling and paging retain their normal drag behavior.
class _TwoPointerScaleGestureRecognizer extends OneSequenceGestureRecognizer {
  _TwoPointerScaleStart? onStart;
  _TwoPointerScaleUpdate? onUpdate;
  VoidCallback? onEnd;
  bool Function()? shouldContinueWaitingForSecondPointer;

  final Map<int, Offset> _positions = {};
  final Map<int, Offset> _initialPositions = {};
  final Set<int> _heldPointers = {};
  bool _accepted = false;
  bool _resetting = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (_positions.length >= 2) {
      resolvePointer(event.pointer, GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
      return;
    }

    _positions[event.pointer] = event.localPosition;
    _initialPositions[event.pointer] = event.localPosition;
    GestureBinding.instance.gestureArena.hold(event.pointer);
    _heldPointers.add(event.pointer);

    if (_positions.length == 2) {
      _accepted = true;
      resolve(GestureDisposition.accepted);
      _releaseHeldPointers();
      onStart?.call(_focalPoint, _distance);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && _positions.containsKey(event.pointer)) {
      _positions[event.pointer] = event.localPosition;
      if (_accepted) {
        onUpdate?.call(_focalPoint, _distance);
      } else {
        final initialPosition = _initialPositions[event.pointer]!;
        if ((event.localPosition - initialPosition).distance >
                computePanSlop(event.kind, gestureSettings) &&
            !(shouldContinueWaitingForSecondPointer?.call() ?? false)) {
          _abandonGesture();
          return;
        }
      }
    }

    if (event is PointerUpEvent || event is PointerCancelEvent) {
      final wasAccepted = _accepted;
      if (!wasAccepted) {
        resolvePointer(event.pointer, GestureDisposition.rejected);
      }
      _positions.remove(event.pointer);
      _initialPositions.remove(event.pointer);
      _releaseHeldPointer(event.pointer);
      stopTrackingPointer(event.pointer);
      if (wasAccepted && _positions.length < 2) {
        _finishGesture();
      } else if (!wasAccepted && _positions.isEmpty) {
        _releaseHeldPointers();
      }
    }
  }

  Offset get _focalPoint {
    final positions = _positions.values.take(2).toList();
    return (positions[0] + positions[1]) / 2;
  }

  double get _distance {
    final positions = _positions.values.take(2).toList();
    return (positions[0] - positions[1]).distance;
  }

  void _finishGesture() {
    if (!_accepted) {
      return;
    }
    _accepted = false;
    _stopTrackingAllPointers();
    onEnd?.call();
  }

  void _abandonGesture() {
    if (_resetting) {
      return;
    }
    _resetting = true;
    resolve(GestureDisposition.rejected);
    _releaseHeldPointers();
    _stopTrackingAllPointers();
    _accepted = false;
    _resetting = false;
  }

  void _stopTrackingAllPointers() {
    for (final pointer in _positions.keys.toList()) {
      stopTrackingPointer(pointer);
    }
    _positions.clear();
    _initialPositions.clear();
  }

  void _releaseHeldPointers() {
    for (final pointer in _heldPointers.toList()) {
      _releaseHeldPointer(pointer);
    }
  }

  void _releaseHeldPointer(int pointer) {
    if (_heldPointers.remove(pointer)) {
      GestureBinding.instance.gestureArena.release(pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (!_accepted) {
      _abandonGesture();
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'two pointer scale';

  @override
  void dispose() {
    final wasAccepted = _accepted;
    _abandonGesture();
    if (wasAccepted) {
      onEnd?.call();
    }
    super.dispose();
  }
}

enum _DraftDragMode { move, resizeStart, resizeEnd }

const _draftHandleHitWidth = 48.0;
const _draftHandleHitHeight = 48.0;
const _draftHandleOverflow = _draftHandleHitHeight / 2;
const _draftHandleVisualDiameter = 12.0;
const _draftHandleVisualRadius = _draftHandleVisualDiameter / 2;
const _draftHandleHorizontalInset = 12.0;

class _DraftSegment {
  const _DraftSegment({
    required this.dayIndex,
    required this.topMinute,
    required this.durationMinutes,
    required this.containsStart,
    required this.containsEnd,
  });

  final int dayIndex;
  final int topMinute;
  final int durationMinutes;
  final bool containsStart;
  final bool containsEnd;
}

String _draftSegmentRole(_DraftSegment segment) {
  if (segment.containsStart) {
    return 'start';
  }
  if (segment.containsEnd) {
    return 'end';
  }
  return 'middle-${segment.dayIndex}';
}

List<_DraftSegment> _draftSegments(WeekCalendarDraft draft, WeekRange week) {
  final segments = <_DraftSegment>[];
  for (var index = 0; index < week.visibleDays; index++) {
    final day = week.start.addDays(index);
    final dayStart = day.startOfDay;
    final dayEnd = day.addDays(1).startOfDay;
    final start = draft.startAt.isAfter(dayStart) ? draft.startAt : dayStart;
    final end = draft.endAt.isBefore(dayEnd) ? draft.endAt : dayEnd;
    if (!start.isBefore(end)) {
      continue;
    }
    segments.add(
      _DraftSegment(
        dayIndex: index,
        topMinute: start.difference(dayStart).inMinutes,
        durationMinutes: end.difference(start).inMinutes,
        containsStart:
            !draft.startAt.isBefore(dayStart) && draft.startAt.isBefore(dayEnd),
        containsEnd:
            draft.endAt.isAfter(dayStart) && !draft.endAt.isAfter(dayEnd),
      ),
    );
  }
  return segments;
}

class _DraftBlock extends StatefulWidget {
  const _DraftBlock({
    super.key,
    required this.draft,
    required this.segment,
    required this.week,
    required this.pixelsPerMinute,
    required this.dayWidth,
    required this.onChanged,
    required this.onManipulationChanged,
    required this.interactionEnabled,
    required this.bodyFocusNode,
    required this.startFocusNode,
    required this.endFocusNode,
    required this.hideForActiveMove,
    this.gridHeightOverrideMinutes,
  });

  final WeekCalendarDraft draft;
  final _DraftSegment segment;
  final WeekRange week;
  final double pixelsPerMinute;
  final double dayWidth;
  final WeekCalendarDraftChanged? onChanged;
  final ValueChanged<_DraftDragMode?> onManipulationChanged;
  final bool interactionEnabled;
  final FocusNode? bodyFocusNode;
  final FocusNode? startFocusNode;
  final FocusNode? endFocusNode;
  // True for every segment of the draft currently being moved (not just the
  // one the pointer is on) — a cross-midnight draft in the 1-day/3-day views
  // renders each day as an independently mounted page, so without this the
  // untouched sibling segment on the other page would sit frozen in its old
  // spot for the whole gesture while the touched one floats away, reading
  // as the drag having split one block into two.
  final bool hideForActiveMove;
  // Overrides the vertical bound handle positions are clamped within
  // (normally one day's worth of minutes — see `_DraftBlockState.build`).
  // The 1-day overlay renders a whole cross-midnight draft as a single
  // unsplit segment whose `topMinute` is counted continuously from the
  // scroller's anchor day rather than reset at each day boundary, so it can
  // run well past one day's minutes — the default bound would otherwise
  // clamp its handles back to a wrong, near-the-top position.
  final int? gridHeightOverrideMinutes;

  @override
  State<_DraftBlock> createState() => _DraftBlockState();
}

class _DraftBlockState extends State<_DraftBlock> {
  late WeekCalendarDraft _initialDraft;
  late _DraftDragMode _dragMode;
  Offset _dragDelta = Offset.zero;
  int? _activePointer;
  Offset? _lastPointerPosition;
  int _previewDayDelta = 0;
  int _previewMinuteDelta = 0;
  OverlayEntry? _dragOverlayEntry;
  Rect? _dragOverlayBaseRect;
  Rect? _dragGridBoundsRect;
  Offset _visualOffsetWithinInteractionRect = Offset.zero;
  Size _visualSize = Size.zero;
  // The interaction box's top-left, in the same local coordinate space as
  // the page's whole day/week grid (whose own origin is (0, 0) there) — see
  // `_showDragOverlay`.
  Offset _interactionOriginWithinGrid = Offset.zero;
  Size _gridSize = Size.zero;
  final ValueNotifier<Offset> _dragOverlayOffset = ValueNotifier<Offset>(
    Offset.zero,
  );
  static final _movePreviousDayAction = CustomSemanticsAction(
    label: 'Move to previous day',
  );
  static final _moveNextDayAction = CustomSemanticsAction(
    label: 'Move to next day',
  );

  @override
  void dispose() {
    _removeDragOverlay();
    _dragOverlayOffset.dispose();
    super.dispose();
  }

  void _startManipulation(_DraftDragMode mode) {
    _initialDraft = widget.draft;
    _dragDelta = Offset.zero;
    _previewDayDelta = 0;
    _previewMinuteDelta = 0;
    _dragMode = mode;
    widget.onManipulationChanged(mode);
  }

  void _beginPointer(PointerDownEvent event, _DraftDragMode mode) {
    if (_activePointer != null || !widget.interactionEnabled) {
      return;
    }
    switch (mode) {
      case _DraftDragMode.move:
        widget.bodyFocusNode?.requestFocus();
      case _DraftDragMode.resizeStart:
        widget.startFocusNode?.requestFocus();
      case _DraftDragMode.resizeEnd:
        widget.endFocusNode?.requestFocus();
    }
    _activePointer = event.pointer;
    _lastPointerPosition = event.position;
    _startManipulation(mode);
    // The block being dragged must stay visible (and keep receiving pointer
    // events) even once it's moved past this page's own day/week bounds —
    // see the note on `_applyDragDelta` for why a live commit can't do that.
    // A ghost rendered in the root `Overlay` paints above every ancestor's
    // `Stack` (which otherwise clips at hard edges — see `_showDragOverlay`),
    // so it never gets cut off crossing into a day this widget can't reach.
    if (mode == _DraftDragMode.move) {
      _showDragOverlay();
    }
  }

  void _showDragOverlay() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return;
    }
    // `renderObject` is the box the outer `Positioned` sizes to fit both the
    // body and (for a start/end segment) the resize handles, which is wider
    // than the visible body itself — floating that whole box would make the
    // ghost visibly larger than, and offset from, the real block. Only the
    // body's own sub-rect is floated here.
    final interactionGlobalOrigin = renderObject.localToGlobal(Offset.zero);
    _dragGridBoundsRect =
        (interactionGlobalOrigin - _interactionOriginWithinGrid) & _gridSize;
    _dragOverlayBaseRect =
        (interactionGlobalOrigin + _visualOffsetWithinInteractionRect) &
        _visualSize;
    _dragOverlayOffset.value = Offset.zero;
    final entry = OverlayEntry(
      builder: (context) {
        return ValueListenableBuilder<Offset>(
          valueListenable: _dragOverlayOffset,
          builder: (context, offset, _) {
            final baseRect = _dragOverlayBaseRect;
            if (baseRect == null) {
              return const SizedBox.shrink();
            }
            final rect = baseRect.shift(offset);
            final previewDraft = _initialDraft.moveBy(
              days: _previewDayDelta,
              minutes: _previewMinuteDelta,
            );
            return Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: IgnorePointer(
                child: _DraftDragGhost(
                  startAt: previewDraft.startAt,
                  endAt: previewDraft.endAt,
                ),
              ),
            );
          },
        );
      },
    );
    _dragOverlayEntry = entry;
    Overlay.of(context).insert(entry);
  }

  // Keeps the floating ghost's raw pixel offset from carrying the block
  // outside this page's own grid — the ghost paints in the app-root
  // `Overlay` precisely so it isn't clipped crossing a day/page boundary,
  // but with nothing else bounding it a large drag would otherwise float
  // over the header, drawer, or other chrome well past the calendar itself.
  Offset _clampOverlayOffset(Offset offset) {
    final base = _dragOverlayBaseRect;
    final bounds = _dragGridBoundsRect;
    if (base == null || bounds == null) {
      return offset;
    }
    final rect = base.shift(offset);
    final clampedLeft = rect.width >= bounds.width
        ? bounds.left
        : rect.left.clamp(bounds.left, bounds.right - rect.width);
    final clampedTop = rect.height >= bounds.height
        ? bounds.top
        : rect.top.clamp(bounds.top, bounds.bottom - rect.height);
    return Offset(clampedLeft - base.left, clampedTop - base.top);
  }

  void _removeDragOverlay() {
    _dragOverlayEntry?.remove();
    _dragOverlayEntry = null;
    _dragOverlayBaseRect = null;
    _dragGridBoundsRect = null;
  }

  _DraftDragMode? _dragModeForPosition(
    Offset position, {
    required Rect bodyRect,
    required Rect startRect,
    required Rect endRect,
    required Offset startCenter,
    required Offset endCenter,
  }) {
    final hitsStart =
        widget.segment.containsStart && startRect.contains(position);
    final hitsEnd = widget.segment.containsEnd && endRect.contains(position);
    final hitsStartVisual =
        (position - startCenter).distanceSquared <=
        _draftHandleVisualRadius * _draftHandleVisualRadius;
    final hitsEndVisual =
        (position - endCenter).distanceSquared <=
        _draftHandleVisualRadius * _draftHandleVisualRadius;
    if (hitsStart && hitsEnd) {
      final startDistance = (position - startCenter).distanceSquared;
      final endDistance = (position - endCenter).distanceSquared;
      if (bodyRect.contains(position) && !hitsStartVisual && !hitsEndVisual) {
        return _DraftDragMode.move;
      }
      if (startDistance == endDistance) {
        return position.dy <= (startCenter.dy + endCenter.dy) / 2
            ? _DraftDragMode.resizeStart
            : _DraftDragMode.resizeEnd;
      }
      return startDistance < endDistance
          ? _DraftDragMode.resizeStart
          : _DraftDragMode.resizeEnd;
    }
    if (hitsStart) {
      if (bodyRect.contains(position) && !hitsStartVisual) {
        return _DraftDragMode.move;
      }
      return _DraftDragMode.resizeStart;
    }
    if (hitsEnd) {
      if (bodyRect.contains(position) && !hitsEndVisual) {
        return _DraftDragMode.move;
      }
      return _DraftDragMode.resizeEnd;
    }
    if (bodyRect.contains(position)) {
      return _DraftDragMode.move;
    }
    return null;
  }

  void _movePointer(PointerMoveEvent event) {
    if (_activePointer != event.pointer || !widget.interactionEnabled) {
      return;
    }
    final previous = _lastPointerPosition;
    if (previous == null) {
      return;
    }
    _lastPointerPosition = event.position;
    _applyDragDelta(event.position - previous);
  }

  void _endPointer(PointerEvent event) {
    if (_activePointer != event.pointer) {
      return;
    }
    _activePointer = null;
    _lastPointerPosition = null;
    if (_dragMode == _DraftDragMode.move) {
      if (_previewDayDelta != 0 || _previewMinuteDelta != 0) {
        widget.onChanged?.call(
          _initialDraft.moveBy(
            days: _previewDayDelta,
            minutes: _previewMinuteDelta,
          ),
        );
      }
      _removeDragOverlay();
      setState(() {
        _dragDelta = Offset.zero;
        _previewDayDelta = 0;
        _previewMinuteDelta = 0;
      });
    }
    _endManipulation();
  }

  void _applyDragDelta(Offset delta) {
    if (!widget.interactionEnabled) {
      return;
    }
    _dragDelta += delta;
    switch (_dragMode) {
      case _DraftDragMode.move:
        // A move is only previewed here — via the overlay ghost started in
        // `_beginPointer` — rather than committed through `widget.onChanged`
        // on every pointer move. Committing immediately would recompute
        // `_draftSegments` against `widget.week` on each frame, and as soon
        // as the dragged block crossed out of that page's day/week window
        // it would stop being one of the segments rendered there —
        // unmounting this exact `_DraftBlock` mid-gesture and silently
        // dropping the pointer capture that drives the drag. The real
        // commit (with no week clamp) happens once, on release, in
        // `_endPointer`.
        //
        // The day/minute delta is snapped here (not left to follow the raw
        // pixel offset) so the ghost always shows one of the discrete grid
        // positions the drag can actually land on — otherwise where it will
        // stop is ambiguous until the finger lifts.
        final dayDelta = (_dragDelta.dx / widget.dayWidth).round();
        final minuteDelta = _snappedMinuteDelta(_dragDelta.dy);
        if (dayDelta != _previewDayDelta ||
            minuteDelta != _previewMinuteDelta) {
          _previewDayDelta = dayDelta;
          _previewMinuteDelta = minuteDelta;
          _dragOverlayOffset.value = _clampOverlayOffset(
            Offset(
              dayDelta * widget.dayWidth,
              minuteDelta * widget.pixelsPerMinute,
            ),
          );
        }
      case _DraftDragMode.resizeStart:
        final minuteDelta = _snappedMinuteDelta(_dragDelta.dy);
        widget.onChanged?.call(
          _initialDraft.resizeStartBy(Duration(minutes: minuteDelta)),
        );
      case _DraftDragMode.resizeEnd:
        final minuteDelta = _snappedMinuteDelta(_dragDelta.dy);
        widget.onChanged?.call(
          _initialDraft.resizeEndBy(Duration(minutes: minuteDelta)),
        );
    }
  }

  int _snappedMinuteDelta(double dyDelta) {
    return ((dyDelta / widget.pixelsPerMinute) /
                weekCalendarDraftSnapInterval.inMinutes)
            .round() *
        weekCalendarDraftSnapInterval.inMinutes;
  }

  void _adjustDraft(_DraftDragMode mode, {int minutes = 0, int days = 0}) {
    if (!widget.interactionEnabled) {
      return;
    }
    final delta = Duration(minutes: minutes);
    final next = switch (mode) {
      _DraftDragMode.move => widget.draft.moveBy(days: days, minutes: minutes),
      _DraftDragMode.resizeStart => widget.draft.resizeStartBy(delta),
      _DraftDragMode.resizeEnd => widget.draft.resizeEndBy(delta),
    };
    widget.onChanged?.call(next);
  }

  KeyEventResult _handleBodyKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !widget.interactionEnabled) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _adjustDraft(_DraftDragMode.move, minutes: -5);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _adjustDraft(_DraftDragMode.move, minutes: 5);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _adjustDraft(_DraftDragMode.move, days: -1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _adjustDraft(_DraftDragMode.move, days: 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _endManipulation() {
    widget.onManipulationChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final height = widget.segment.durationMinutes * widget.pixelsPerMinute;
    final width = (widget.dayWidth - 4).clamp(0, double.infinity).toDouble();
    final gridWidth = widget.dayWidth * widget.week.visibleDays;
    final gridHeight =
        (widget.gridHeightOverrideMinutes ?? Duration.minutesPerDay) *
        widget.pixelsPerMinute;
    final visualLeft = widget.segment.dayIndex * widget.dayWidth + 2;
    final visualTop = widget.segment.topMinute * widget.pixelsPerMinute;
    final visualRect = Rect.fromLTWH(visualLeft, visualTop, width, height);
    final startCenter = Offset(
      visualRect.left + _draftHandleHorizontalInset,
      visualRect.top,
    );
    final endCenter = Offset(
      visualRect.right - _draftHandleHorizontalInset,
      visualRect.bottom,
    );
    Rect handleRect(Offset center) {
      final left = (center.dx - _draftHandleOverflow)
          .clamp(0, gridWidth - _draftHandleHitWidth)
          .toDouble();
      final top = (center.dy - _draftHandleOverflow)
          .clamp(0, gridHeight - _draftHandleHitHeight)
          .toDouble();
      return Rect.fromLTWH(
        left,
        top,
        _draftHandleHitWidth,
        _draftHandleHitHeight,
      );
    }

    final startRect = handleRect(startCenter);
    final endRect = handleRect(endCenter);
    var interactionRect = visualRect;
    if (widget.segment.containsStart) {
      interactionRect = interactionRect.expandToInclude(startRect);
    }
    if (widget.segment.containsEnd) {
      interactionRect = interactionRect.expandToInclude(endRect);
    }
    final interactionOrigin = interactionRect.topLeft;
    // Cached so `_showDragOverlay` (called from a pointer-down handler, well
    // outside `build`) can float exactly the body's own rect rather than the
    // larger box `interactionRect` reserves for the resize handles.
    _visualOffsetWithinInteractionRect = visualRect.topLeft - interactionOrigin;
    _visualSize = visualRect.size;
    _interactionOriginWithinGrid = interactionOrigin;
    _gridSize = Size(gridWidth, gridHeight);
    final localBodyRect = visualRect.shift(-interactionOrigin);
    final localStartRect = startRect.shift(-interactionOrigin);
    final localEndRect = endRect.shift(-interactionOrigin);
    final localStartCenter = startCenter - interactionOrigin;
    final localEndCenter = endCenter - interactionOrigin;
    final bodyDecoration = DecoratedBox(
      key: ValueKey(
        'week-calendar-draft-body-${widget.draft.id}-'
        '${widget.segment.dayIndex}',
      ),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.28),
        border: Border.all(color: colorScheme.tertiary, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
    );
    final bodyFocusNode = widget.bodyFocusNode;
    final body = bodyFocusNode == null
        ? bodyDecoration
        : Focus(
            focusNode: bodyFocusNode,
            canRequestFocus: widget.interactionEnabled,
            onKeyEvent: _handleBodyKey,
            child: Semantics(
              key: ValueKey(
                'week-calendar-draft-body-semantics-${widget.draft.id}',
              ),
              container: true,
              focusable: true,
              enabled: widget.interactionEnabled,
              label: 'Wake plan draft',
              value:
                  'Start ${_accessibleDateTime(widget.draft.startAt)}, '
                  'end ${_accessibleDateTime(widget.draft.endAt)}',
              increasedValue: 'Start and end 5 minutes later',
              decreasedValue: 'Start and end 5 minutes earlier',
              onIncrease: widget.interactionEnabled
                  ? () => _adjustDraft(_DraftDragMode.move, minutes: 5)
                  : null,
              onDecrease: widget.interactionEnabled
                  ? () => _adjustDraft(_DraftDragMode.move, minutes: -5)
                  : null,
              customSemanticsActions: widget.interactionEnabled
                  ? {
                      _movePreviousDayAction: () =>
                          _adjustDraft(_DraftDragMode.move, days: -1),
                      _moveNextDayAction: () =>
                          _adjustDraft(_DraftDragMode.move, days: 1),
                    }
                  : null,
              child: bodyDecoration,
            ),
          );
    // A ghost in the root `Overlay` (see `_showDragOverlay`) tracks the
    // finger during an in-progress move, so this original box is hidden
    // (not repositioned) while that's active — otherwise the two would show
    // side by side. Hit-testing is unaffected: `Opacity` never blocks the
    // pointer route already captured by this `Listener` at drag start.
    // Driven by `widget.hideForActiveMove` rather than this instance's own
    // `_dragOverlayEntry` so every segment of a cross-midnight draft hides
    // together — otherwise a sibling segment on another page (only reachable
    // through the shared `widget.draft`, not this drag's own state) would
    // stay frozen in its old spot while the touched one floats away,
    // reading as one block splitting into two.
    final hideForMoveDrag = widget.hideForActiveMove;
    return Positioned(
      key: ValueKey(
        'week-calendar-draft-segment-${widget.draft.id}-'
        '${widget.segment.dayIndex}',
      ),
      left: interactionRect.left,
      top: interactionRect.top,
      width: interactionRect.width,
      height: interactionRect.height,
      child: IgnorePointer(
        ignoring: !widget.interactionEnabled,
        child: Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (event) {
            final mode = _dragModeForPosition(
              event.localPosition,
              bodyRect: localBodyRect,
              startRect: localStartRect,
              endRect: localEndRect,
              startCenter: localStartCenter,
              endCenter: localEndCenter,
            );
            if (mode != null) {
              _beginPointer(event, mode);
            }
          },
          onPointerMove: _movePointer,
          onPointerUp: _endPointer,
          onPointerCancel: _endPointer,
          child: Opacity(
            opacity: hideForMoveDrag ? 0 : 1,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: localBodyRect.top,
                  left: localBodyRect.left,
                  width: localBodyRect.width,
                  height: localBodyRect.height,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    child: body,
                  ),
                ),
                if (widget.segment.containsStart)
                  _DraftHandleControl(
                    key: const ValueKey('week-calendar-draft-start-handle'),
                    rect: localStartRect,
                    visualCenter: localStartCenter,
                    color: colorScheme.tertiary,
                    mode: _DraftDragMode.resizeStart,
                    value: _accessibleDateTime(widget.draft.startAt),
                    interactionEnabled: widget.interactionEnabled,
                    focusNode: widget.startFocusNode!,
                    onAdjustMinutes: (minutes) => _adjustDraft(
                      _DraftDragMode.resizeStart,
                      minutes: minutes,
                    ),
                  ),
                if (widget.segment.containsEnd)
                  _DraftHandleControl(
                    key: const ValueKey('week-calendar-draft-end-handle'),
                    rect: localEndRect,
                    visualCenter: localEndCenter,
                    color: colorScheme.tertiary,
                    mode: _DraftDragMode.resizeEnd,
                    value: _accessibleDateTime(widget.draft.endAt),
                    interactionEnabled: widget.interactionEnabled,
                    focusNode: widget.endFocusNode!,
                    onAdjustMinutes: (minutes) => _adjustDraft(
                      _DraftDragMode.resizeEnd,
                      minutes: minutes,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftDragGhost extends StatelessWidget {
  const _DraftDragGhost({required this.startAt, required this.endAt});

  final DateTime startAt;
  final DateTime endAt;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.92),
        border: Border.all(color: colorScheme.tertiary, width: 2),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${_dragGhostDateTimeLabel(startAt)} - '
          '${_dragGhostDateTimeLabel(endAt)}',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onTertiaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _dragGhostDateTimeLabel(DateTime dateTime) {
  return '${dateTime.month}/${dateTime.day} ${_timeLabel(dateTime)}';
}

class _DraftHandleControl extends StatefulWidget {
  const _DraftHandleControl({
    super.key,
    required this.rect,
    required this.visualCenter,
    required this.color,
    required this.mode,
    required this.value,
    required this.interactionEnabled,
    required this.focusNode,
    required this.onAdjustMinutes,
  });

  final Rect rect;
  final Offset visualCenter;
  final Color color;
  final _DraftDragMode mode;
  final String value;
  final bool interactionEnabled;
  final FocusNode focusNode;
  final ValueChanged<int> onAdjustMinutes;

  @override
  State<_DraftHandleControl> createState() => _DraftHandleControlState();
}

class _DraftHandleControlState extends State<_DraftHandleControl> {
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !widget.interactionEnabled) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onAdjustMinutes(-5);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.onAdjustMinutes(5);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.rect.top,
      left: widget.rect.left,
      width: widget.rect.width,
      height: widget.rect.height,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: Focus(
          focusNode: widget.focusNode,
          canRequestFocus: widget.interactionEnabled,
          onKeyEvent: _handleKey,
          child: Semantics(
            key: ValueKey(
              widget.mode == _DraftDragMode.resizeStart
                  ? 'week-calendar-draft-start-handle-semantics'
                  : 'week-calendar-draft-end-handle-semantics',
            ),
            container: true,
            focusable: true,
            enabled: widget.interactionEnabled,
            label: widget.mode == _DraftDragMode.resizeStart
                ? 'Wake plan start'
                : 'Wake plan end',
            value: widget.value,
            increasedValue: '5 minutes later',
            decreasedValue: '5 minutes earlier',
            onIncrease: widget.interactionEnabled
                ? () => widget.onAdjustMinutes(5)
                : null,
            onDecrease: widget.interactionEnabled
                ? () => widget.onAdjustMinutes(-5)
                : null,
            child: Center(
              child: Transform.translate(
                offset: widget.visualCenter - widget.rect.center,
                child: Container(
                  width: _draftHandleVisualDiameter,
                  height: _draftHandleVisualDiameter,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds the segments a tap-preview draft of [duration] starting at
/// [target] would occupy, reusing the same day-splitting [_draftSegments]
/// uses for real drafts so a preview that crosses midnight is shown as a
/// continuation in the next visible day instead of one clipped cell — the
/// same shape the draft created on tap-up will actually have.
///
/// [duration] is capped to [week] the same way the real draft created on
/// tap-up is (see weekCalendarClampDraftDurationToWeek), so a tap on the
/// last visible day never previews — or creates — a continuation past the
/// edge of what's currently on screen.
List<_DraftSegment> _tapPreviewSegments({
  required WeekCalendarTapTarget target,
  required Duration duration,
  required WeekRange week,
}) {
  final startAt = target.dateTime;
  final cappedDuration = weekCalendarClampDraftDurationToWeek(
    startAt: startAt,
    duration: duration,
    week: week,
  );
  final draft = WeekCalendarDraft(
    id: 'tap-preview',
    startAt: startAt,
    endAt: startAt.add(cappedDuration),
    createdAt: startAt,
  );
  return _draftSegments(draft, week);
}

/// Shows the grid cell(s) a tap would create a draft in, before the tap is
/// released, so it's obvious ahead of time where the block will land.
class _TapPreviewCell extends StatelessWidget {
  const _TapPreviewCell({
    super.key,
    required this.segment,
    required this.pixelsPerMinute,
    required this.dayWidth,
  });

  final _DraftSegment segment;
  final double pixelsPerMinute;
  final double dayWidth;

  @override
  Widget build(BuildContext context) {
    final top = segment.topMinute * pixelsPerMinute;
    final height = segment.durationMinutes * pixelsPerMinute;
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      left: segment.dayIndex * dayWidth,
      top: top,
      width: dayWidth,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.tertiary.withValues(alpha: 0.18),
            border: Border.all(color: colorScheme.tertiary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _WakePlanBlock extends StatelessWidget {
  const _WakePlanBlock({
    required this.block,
    required this.pixelsPerMinute,
    required this.dayWidth,
    required this.onTap,
  });

  static const double _gap = 2;

  final WeekCalendarWakePlanBlock block;
  final double pixelsPerMinute;
  final double dayWidth;
  final WeekCalendarWakePlanTapCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final laneWidth = dayWidth / block.laneCount;
    final left = (block.dayIndex * dayWidth) + (block.laneIndex * laneWidth);
    final top = block.topMinute * pixelsPerMinute;
    final height = block.durationMinutes * pixelsPerMinute;
    final horizontalGap = laneWidth > (_gap * 2) ? _gap : laneWidth / 8;
    final blockWidth = (laneWidth - (horizontalGap * 2))
        .clamp(0, laneWidth)
        .toDouble();

    return Positioned(
      left: left + horizontalGap,
      top: top + _gap,
      width: blockWidth,
      height: (height - (_gap * 2)).clamp(18, double.infinity),
      child: _WakePlanBlockCard(block: block, onTap: onTap),
    );
  }
}

class _WakePlanBlockCard extends StatelessWidget {
  const _WakePlanBlockCard({required this.block, required this.onTap});

  final WeekCalendarWakePlanBlock block;
  final WeekCalendarWakePlanTapCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final targetColor = block.containsTarget
        ? colorScheme.tertiary
        : colorScheme.primary;
    final labelColor = colorScheme.onPrimaryContainer;
    final label = _wakePlanBlockLabel(block);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        key: ValueKey(
          'week-calendar-wake-plan-block-'
          '${block.wakePlan.id}-${block.day}-${block.laneIndex}',
        ),
        color: colorScheme.primaryContainer.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap?.call(block.tapTarget),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 7),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      label,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: labelColor,
                        height: 1.12,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: block.containsTarget
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                child: Container(height: 5, color: targetColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.week, required this.now});

  final WeekRange week;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = CalendarDay.fromDateTime(now);

    return Row(
      children: [
        for (final day in week.days)
          Expanded(
            child: _DateHeaderCell(
              weekdayLabel: _weekdayLabel(day.weekday),
              dayLabel: '${day.day}',
              highlighted: day == today,
            ),
          ),
      ],
    );
  }
}

/// Reserves exactly the height a real [_DateHeader] cell takes, without
/// rendering any real weekday/day-number text, so it can size the fixed time
/// axis's header spacer without also being matched by `find.text('Mon')`
/// (etc.) finders in tests.
class _DateHeaderSizingProbe extends StatelessWidget {
  const _DateHeaderSizingProbe();

  @override
  Widget build(BuildContext context) {
    return const _DateHeaderCell(
      weekdayLabel: '',
      dayLabel: '',
      highlighted: false,
    );
  }
}

class _DateHeaderCell extends StatelessWidget {
  const _DateHeaderCell({
    required this.weekdayLabel,
    required this.dayLabel,
    required this.highlighted,
  });

  final String weekdayLabel;
  final String dayLabel;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              weekdayLabel,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlighted ? colorScheme.primary : Colors.transparent,
            ),
            child: Text(
              dayLabel,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: highlighted
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeAxis extends StatelessWidget {
  const _TimeAxis({required this.hourHeight});

  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var hour = 0; hour <= TimeOfDayMinutes.hoursPerDay; hour++)
          Positioned(
            top: hour * hourHeight,
            right: 8,
            child: Transform.translate(
              offset: const Offset(0, -8),
              child: Text(
                hour == TimeOfDayMinutes.hoursPerDay
                    ? '24:00'
                    : '${hour.toString().padLeft(2, '0')}:00',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
      ],
    );
  }
}

class _TimeGrid extends StatelessWidget {
  const _TimeGrid({
    required this.week,
    required this.now,
    required this.hourHeight,
    required this.snapIntervalMinutes,
  });

  final WeekRange week;
  final DateTime now;
  final double hourHeight;
  final int snapIntervalMinutes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = CalendarDay.fromDateTime(now);
    final currentMinute =
        now.hour * TimeOfDayMinutes.minutesPerHour + now.minute;

    return CustomPaint(
      key: const ValueKey('week-calendar-time-grid'),
      painter: _TimeGridPainter(
        lineColor: colorScheme.outlineVariant,
        subIntervalLineColor: colorScheme.outlineVariant.withValues(alpha: 0.4),
        dayLineColor: colorScheme.outline,
        currentTimeColor: colorScheme.error,
        hourHeight: hourHeight,
        visibleDays: week.visibleDays,
        snapIntervalMinutes: snapIntervalMinutes,
        currentDayIndex: week.contains(today)
            ? today.differenceInDays(week.start)
            : null,
        currentMinute: currentMinute,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TimeGridPainter extends CustomPainter {
  const _TimeGridPainter({
    required this.lineColor,
    required this.subIntervalLineColor,
    required this.dayLineColor,
    required this.currentTimeColor,
    required this.hourHeight,
    required this.visibleDays,
    required this.snapIntervalMinutes,
    required this.currentDayIndex,
    required this.currentMinute,
  });

  final Color lineColor;
  final Color subIntervalLineColor;
  final Color dayLineColor;
  final Color currentTimeColor;
  final double hourHeight;
  final int visibleDays;
  final int snapIntervalMinutes;
  final int? currentDayIndex;
  final int currentMinute;

  @override
  void paint(Canvas canvas, Size size) {
    final hourPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    final dayPaint = Paint()
      ..color = dayLineColor
      ..strokeWidth = 1;

    if (snapIntervalMinutes < TimeOfDayMinutes.minutesPerHour) {
      final subIntervalPaint = Paint()
        ..color = subIntervalLineColor
        ..strokeWidth = 1;
      final pixelsPerMinute = hourHeight / TimeOfDayMinutes.minutesPerHour;
      for (
        var minute = snapIntervalMinutes;
        minute < TimeOfDayMinutes.minutesPerDay;
        minute += snapIntervalMinutes
      ) {
        if (minute % TimeOfDayMinutes.minutesPerHour == 0) {
          continue;
        }
        final y = minute * pixelsPerMinute;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), subIntervalPaint);
      }
    }

    for (var hour = 0; hour <= TimeOfDayMinutes.hoursPerDay; hour++) {
      final y = hour * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hourPaint);
    }

    final dayWidth = size.width / visibleDays;
    for (var day = 0; day <= visibleDays; day++) {
      final x = day * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dayPaint);
    }

    final currentDayIndex = this.currentDayIndex;
    if (currentDayIndex == null) {
      return;
    }

    final currentY =
        currentMinute * (hourHeight / TimeOfDayMinutes.minutesPerHour);
    final currentStartX = currentDayIndex * dayWidth;
    final currentEndX = currentStartX + dayWidth;
    final currentPaint = Paint()
      ..color = currentTimeColor
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(currentStartX, currentY),
      Offset(currentEndX, currentY),
      currentPaint,
    );
  }

  @override
  bool shouldRepaint(_TimeGridPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.subIntervalLineColor != subIntervalLineColor ||
        oldDelegate.dayLineColor != dayLineColor ||
        oldDelegate.currentTimeColor != currentTimeColor ||
        oldDelegate.hourHeight != hourHeight ||
        oldDelegate.visibleDays != visibleDays ||
        oldDelegate.snapIntervalMinutes != snapIntervalMinutes ||
        oldDelegate.currentDayIndex != currentDayIndex ||
        oldDelegate.currentMinute != currentMinute;
  }
}

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => throw RangeError.range(weekday, DateTime.monday, DateTime.sunday),
  };
}

String _wakePlanBlockLabel(WeekCalendarWakePlanBlock block) {
  return '${block.wakePlan.targetTime}\n'
      '${_timeLabel(block.startAt)}-${_timeLabel(block.targetAt)}\n'
      'Every ${block.wakePlan.interval.inMinutes} min\n'
      '${block.occurrenceCount} alarms';
}

String _timeLabel(DateTime dateTime) {
  return '${dateTime.hour.toString().padLeft(2, '0')}:'
      '${dateTime.minute.toString().padLeft(2, '0')}';
}

String _accessibleDateTime(DateTime dateTime) {
  return '${dateTime.year.toString().padLeft(4, '0')}-'
      '${dateTime.month.toString().padLeft(2, '0')}-'
      '${dateTime.day.toString().padLeft(2, '0')} '
      '${_timeLabel(dateTime)}';
}
