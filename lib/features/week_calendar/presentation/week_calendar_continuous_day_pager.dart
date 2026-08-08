import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../model/week_calendar_interaction.dart';
import 'week_calendar_draft.dart';
import 'week_calendar_format.dart';
import 'week_calendar_gestures.dart';
import 'week_calendar_grid_widgets.dart';
import 'week_calendar_view.dart';

/// Multi-day paged view used for widths other than 1 or 7 (currently just
/// the 3-day mode). Unlike [WeekCalendarWeekPage]'s [PageView] (whose pages
/// are each a full [visibleDays]-wide window, so a swipe replaces the whole
/// window at once — e.g. 3/4/5 -> 4/5/6 -> 5/6/7, each requiring a full page
/// swipe even though only one day actually changes), this pages a single
/// day at a time via `PageController.viewportFraction`, so a swipe slides
/// the visible days by exactly one day, continuously, like the header cards
/// in Google Calendar.
class WeekCalendarContinuousDayPager extends StatefulWidget {
  const WeekCalendarContinuousDayPager({
    super.key,
    required this.anchorDay,
    required this.visibleDays,
    required this.now,
    required this.wakePlans,
    this.holidays = const {},
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
  final Set<CalendarDay> holidays;
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
  State<WeekCalendarContinuousDayPager> createState() =>
      _ContinuousDayPagerState();
}

class _ContinuousDayPagerState extends State<WeekCalendarContinuousDayPager> {
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
  WeekCalendarDraftDragMode? _manipulatingDraftMode;
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
  void didUpdateWidget(covariant WeekCalendarContinuousDayPager oldWidget) {
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
    if (mounted && _pinching) {
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

  void _setManipulatingDraft(WeekCalendarDraftDragMode? mode) {
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
              child: IgnorePointer(child: WeekCalendarDateHeaderSizingProbe()),
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
                      holidays: widget.holidays,
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
                            child: WeekCalendarTimeAxis(
                              hourHeight: _displayHourHeight,
                            ),
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
                    WeekCalendarTwoPointerScaleGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          WeekCalendarTwoPointerScaleGestureRecognizer
                        >(WeekCalendarTwoPointerScaleGestureRecognizer.new, (
                          recognizer,
                        ) {
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
                          : const WeekCalendarPreserveVisibleTimeScrollPhysics(),
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
      holidays: widget.holidays,
    );
    final snapIntervalMinutes = weekCalendarTapSnapIntervalMinutes(
      _displayHourHeight,
    );
    final previewDuration = weekCalendarBoundedDraftDuration(
      widget.draftDuration,
    );
    final draft = widget.draft;
    final draftSegments = draft == null
        ? const <WeekCalendarDraftSegment>[]
        : weekCalendarDraftSegments(draft, week);

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
              WeekCalendarTimeGrid(
                week: week,
                now: widget.now,
                hourHeight: _displayHourHeight,
                snapIntervalMinutes: snapIntervalMinutes,
              ),
              if (_tapPreviewDay == day)
                if (_tapPreviewTarget case final preview?)
                  for (final segment in weekCalendarTapPreviewSegments(
                    target: preview,
                    duration: previewDuration,
                    week: week,
                  ))
                    WeekCalendarTapPreviewCell(
                      key: const ValueKey('week-calendar-tap-preview-cell'),
                      segment: segment,
                      pixelsPerMinute: _pixelsPerMinute,
                      dayWidth: constraints.maxWidth,
                    ),
              for (final block in blocks)
                WeekCalendarWakePlanBlockView(
                  block: block,
                  pixelsPerMinute: _pixelsPerMinute,
                  dayWidth: constraints.maxWidth,
                  onTap: widget.onWakePlanTap,
                ),
              if (draft != null)
                for (final segment in draftSegments)
                  WeekCalendarDraftBlock(
                    key: ValueKey(
                      'week-calendar-draft-block-'
                      '${draft.id}-'
                      '${weekCalendarDraftSegmentRole(segment)}',
                    ),
                    draft: draft,
                    segment: segment,
                    week: week,
                    pixelsPerMinute: _pixelsPerMinute,
                    dayWidth: constraints.maxWidth,
                    onChanged: widget.onDraftChanged,
                    onManipulationChanged: _setManipulatingDraft,
                    interactionEnabled:
                        !_pinching && widget.draftInteractionEnabled,
                    hideForActiveMove:
                        _manipulatingDraftMode ==
                        WeekCalendarDraftDragMode.move,
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

/// Renders the sliding row of date headers above [WeekCalendarContinuousDayPager]'s
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
    this.holidays = const {},
  });

  final ValueListenable<double> pageListenable;
  final CalendarDay anchorDay;
  final int visibleDays;
  final DateTime now;
  final Set<CalendarDay> holidays;

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
                          return WeekCalendarDateHeaderCell(
                            weekdayLabel: weekCalendarWeekdayLabel(day.weekday),
                            dayLabel: '${day.day}',
                            highlighted: day == today,
                            dayKind: weekCalendarDateHeaderDayKind(
                              day,
                              holidays,
                            ),
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
