import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../model/week_calendar_interaction.dart';
import 'week_calendar_draft.dart';
import 'week_calendar_format.dart';
import 'week_calendar_gestures.dart';
import 'week_calendar_grid_widgets.dart';
import 'week_calendar_view.dart';

/// The 1-day view: instead of paging horizontally between individual days
/// with each one's vertical scroll capped at 24:00, this scrolls a single
/// continuous vertical axis of stacked day grids, so scrolling past 24:00
/// flows straight into 0:00 of the next day (and, scrolling up, into 24:00
/// of the previous day) with no page boundary.
class WeekCalendarInfiniteDayScroller extends StatefulWidget {
  const WeekCalendarInfiniteDayScroller({
    required this.anchorDay,
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
  });

  final CalendarDay anchorDay;
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

  @override
  State<WeekCalendarInfiniteDayScroller> createState() => _InfiniteDayScrollerState();
}

class _InfiniteDayScrollerState extends State<WeekCalendarInfiniteDayScroller> {
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
  void didUpdateWidget(covariant WeekCalendarInfiniteDayScroller oldWidget) {
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
                      ? 'Today, ${weekCalendarWeekdayLabel(day.weekday)} ${day.day}'
                      : '${weekCalendarWeekdayLabel(day.weekday)} ${day.day}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: weekCalendarDateHeaderDayKindColor(
                      weekCalendarDateHeaderDayKind(day, widget.holidays),
                    ),
                  ),
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
                            child: WeekCalendarTimeAxis(hourHeight: _displayHourHeight),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: _dayHeight - withinDay,
                            height: _dayHeight,
                            child: WeekCalendarTimeAxis(hourHeight: _displayHourHeight),
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
          child: WeekCalendarTimeGrid(
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
                  holidays: widget.holidays,
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
                        WeekCalendarWakePlanBlockView(
                          block: block,
                          pixelsPerMinute: _pixelsPerMinute,
                          dayWidth: constraints.maxWidth,
                          onTap: widget.onWakePlanTap,
                        ),
                      if (previewSegment != null)
                        WeekCalendarTapPreviewCell(
                          key: const ValueKey('week-calendar-tap-preview-cell'),
                          segment: previewSegment,
                          pixelsPerMinute: _pixelsPerMinute,
                          dayWidth: constraints.maxWidth,
                        ),
                      if (draft != null && draftSegment != null)
                        WeekCalendarDraftBlock(
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
                          interactionEnabled:
                              !_pinching && widget.draftInteractionEnabled,
                          hideForActiveMove:
                              _manipulatingDraftMode == WeekCalendarDraftDragMode.move,
                          gridHeightOverrideMinutes:
                              windowDays * TimeOfDayMinutes.minutesPerDay,
                          disableHorizontalDayChange: true,
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

  WeekCalendarDraftSegment? _overlaySegmentForTapPreview(
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

  WeekCalendarDraftSegment _overlaySegmentForDraft(
    WeekCalendarDraft draft,
    WeekRange window,
  ) {
    return _overlaySegmentFor(
      startAt: draft.startAt,
      durationMinutes: draft.duration.inMinutes,
      window: window,
    );
  }

  WeekCalendarDraftSegment _overlaySegmentFor({
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
    return WeekCalendarDraftSegment(
      dayIndex: 0,
      topMinute: topMinute,
      durationMinutes: durationMinutes,
      containsStart: true,
      containsEnd: true,
    );
  }
}
