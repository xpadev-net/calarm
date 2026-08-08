import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../model/week_calendar_interaction.dart';
import 'week_calendar_draft.dart';
import 'week_calendar_gestures.dart';
import 'week_calendar_grid_widgets.dart';
import 'week_calendar_view.dart';

class WeekCalendarWeekPage extends StatefulWidget {
  const WeekCalendarWeekPage({
    super.key,
    required this.week,
    required this.now,
    required this.wakePlans,
    this.holidays = const {},
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
    this.initialScrollOffset,
    this.recenterTargetOffset,
  });

  final WeekRange week;
  final DateTime now;
  final List<WakePlan> wakePlans;
  final Set<CalendarDay> holidays;
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

  /// The vertical scroll offset every other page is currently sitting at.
  /// Newly built pages start here instead of each computing its own
  /// "now" vs. default-hour target, so paging horizontally never jerks
  /// the vertical position around.
  final double? initialScrollOffset;

  /// The exact vertical offset a matching [recenterRequest] should jump to,
  /// precomputed once by the parent (see `_axisOffset` there) so the fixed
  /// time axis and this page's own scroll jump always land on the identical
  /// value instead of each independently recomputing "now"'s offset.
  final double? recenterTargetOffset;

  @override
  State<WeekCalendarWeekPage> createState() => _WeekCalendarWeekPageState();
}

class _WeekCalendarWeekPageState extends State<WeekCalendarWeekPage> {
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
  WeekCalendarDraftDragMode? _manipulatingDraftMode;
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
    final initialOffset =
        widget.initialScrollOffset ??
        initialWeekCalendarScrollTarget(
          week: widget.week,
          now: widget.now,
          pixelsPerMinute: _pixelsPerMinute,
        ).offset;
    _scrollController = ScrollController(initialScrollOffset: initialOffset);
    _appliedRecenterRequest = widget.recenterRequest;
    widget.onScrollControllerReady(widget.pageIndex, _scrollController);
  }

  @override
  void didUpdateWidget(covariant WeekCalendarWeekPage oldWidget) {
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
    _pinchStartScrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0;
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
    if (mounted && _pinching) {
      setState(() {
        _pinching = false;
      });
      widget.onPinchStateChanged(false);
    }
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
    final targetOffset =
        widget.recenterTargetOffset ??
        initialWeekCalendarScrollTarget(
          week: widget.week,
          now: widget.now,
          pixelsPerMinute: _pixelsPerMinute,
        ).offset;
    final boundedOffset = targetOffset.clamp(
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
      holidays: widget.holidays,
    );
    final snapIntervalMinutes = weekCalendarTapSnapIntervalMinutes(
      _displayHourHeight,
    );
    final previewDuration = weekCalendarBoundedDraftDuration(
      widget.draftDuration,
    );

    return Column(
      children: [
        WeekCalendarDateHeader(
          week: widget.week,
          now: widget.now,
          holidays: widget.holidays,
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
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: _pinching || _manipulatingDraft
                    ? const NeverScrollableScrollPhysics()
                    : const WeekCalendarPreserveVisibleTimeScrollPhysics(),
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
                              WeekCalendarTimeGrid(
                                week: widget.week,
                                now: widget.now,
                                hourHeight: _displayHourHeight,
                                snapIntervalMinutes: snapIntervalMinutes,
                              ),
                              if (_tapPreviewTarget case final preview?)
                                for (final segment
                                    in weekCalendarTapPreviewSegments(
                                      target: preview,
                                      duration: previewDuration,
                                      week: widget.week,
                                    ))
                                  WeekCalendarTapPreviewCell(
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
                                WeekCalendarWakePlanBlockView(
                                  block: block,
                                  pixelsPerMinute: _pixelsPerMinute,
                                  dayWidth:
                                      constraints.maxWidth /
                                      widget.week.visibleDays,
                                  onTap: widget.onWakePlanTap,
                                ),
                              if (widget.draft case final draft?)
                                for (final segment in weekCalendarDraftSegments(
                                  draft,
                                  widget.week,
                                ))
                                  WeekCalendarDraftBlock(
                                    key: ValueKey(
                                      'week-calendar-draft-block-'
                                      '${draft.id}-'
                                      '${weekCalendarDraftSegmentRole(segment)}',
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
