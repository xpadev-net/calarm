import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../core/time/time.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../model/week_calendar_interaction.dart';

typedef WeekCalendarTapCallback = void Function(WeekCalendarTapTarget target);
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
  });

  final DateTime now;
  final WeekRange? initialWeek;
  final List<WakePlan> wakePlans;
  final WeekCalendarTapCallback? onTargetTap;
  final WeekCalendarWakePlanTapCallback? onWakePlanTap;
  final double height;
  final double hourHeight;
  final int visibleDays;
  final WeekCalendarHourHeightChanged? onHourHeightChanged;
  final WeekCalendarDraft? draft;
  final WeekCalendarDraftChanged? onDraftChanged;
  final bool draftInteractionEnabled;

  @override
  State<WeekCalendarView> createState() => _WeekCalendarViewState();
}

class _WeekCalendarViewState extends State<WeekCalendarView> {
  static const int _initialPage = 10000;
  static const double _timeAxisWidth = 52;

  late final WeekCalendarPage _initialCalendarPage;
  late final PageController _pageController;
  bool _pinching = false;

  @override
  void initState() {
    super.initState();
    _initialCalendarPage = WeekCalendarPage(
      week:
          widget.initialWeek ??
          currentCalendarRange(widget.now, visibleDays: widget.visibleDays),
    );
    _pageController = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _pageController,
        physics: _pinching || widget.draft != null
            ? const NeverScrollableScrollPhysics()
            : null,
        itemBuilder: (context, index) {
          final week = _initialCalendarPage.addPages(index - _initialPage).week;
          return _WeekCalendarWeekPage(
            week: week,
            now: widget.now,
            wakePlans: widget.wakePlans,
            onTargetTap: widget.onTargetTap,
            onWakePlanTap: widget.onWakePlanTap,
            hourHeight: widget.hourHeight,
            timeAxisWidth: _timeAxisWidth,
            onHourHeightChanged: widget.onHourHeightChanged,
            onPinchStateChanged: _setPinching,
            draft: widget.draft,
            onDraftChanged: widget.onDraftChanged,
            draftInteractionEnabled: widget.draftInteractionEnabled,
          );
        },
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
}

class _WeekCalendarWeekPage extends StatefulWidget {
  const _WeekCalendarWeekPage({
    required this.week,
    required this.now,
    required this.wakePlans,
    required this.onTargetTap,
    required this.onWakePlanTap,
    required this.hourHeight,
    required this.timeAxisWidth,
    required this.onHourHeightChanged,
    required this.onPinchStateChanged,
    required this.draft,
    required this.onDraftChanged,
    required this.draftInteractionEnabled,
  });

  final WeekRange week;
  final DateTime now;
  final List<WakePlan> wakePlans;
  final WeekCalendarTapCallback? onTargetTap;
  final WeekCalendarWakePlanTapCallback? onWakePlanTap;
  final double hourHeight;
  final double timeAxisWidth;
  final WeekCalendarHourHeightChanged? onHourHeightChanged;
  final ValueChanged<bool> onPinchStateChanged;
  final WeekCalendarDraft? draft;
  final WeekCalendarDraftChanged? onDraftChanged;
  final bool draftInteractionEnabled;

  @override
  State<_WeekCalendarWeekPage> createState() => _WeekCalendarWeekPageState();
}

class _WeekCalendarWeekPageState extends State<_WeekCalendarWeekPage> {
  static const double _minHourHeight = 36;
  static const double _maxHourHeight = 92;

  late final ScrollController _scrollController;
  late double _displayHourHeight;
  bool _didApplyInitialScroll = false;
  double? _pendingScrollOffset;
  double? _pinchStartDistance;
  double? _pinchStartHourHeight;
  double? _pinchStartScrollOffset;
  double? _zoomFocalY;
  bool _pinching = false;
  bool _manipulatingDraft = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyInitialScroll();
    });
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
    if (oldWidget.week.start != widget.week.start) {
      _didApplyInitialScroll = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyInitialScroll();
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
      _manipulatingDraft = false;
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
    if (nextHourHeight == _displayHourHeight) {
      return;
    }
    final focalY = _zoomFocalY!;
    final focalMinute =
        (startScrollOffset + focalY) /
        (startHourHeight / TimeOfDayMinutes.minutesPerHour);
    _pendingScrollOffset =
        (focalMinute * (nextHourHeight / TimeOfDayMinutes.minutesPerHour)) -
        focalY;
    setState(() {
      _displayHourHeight = nextHourHeight;
    });
    widget.onHourHeightChanged?.call(nextHourHeight);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyPendingScroll();
    });
  }

  void _handlePinchEnd() {
    // A cross-day move can replace the draft segment that received the pointer
    // down before it sees the matching up/cancel. The page-level recognizer
    // stays mounted for the whole gesture, so it owns the cleanup guarantee.
    _setManipulatingDraft(false);
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

  void _setManipulatingDraft(bool manipulating) {
    if (_manipulatingDraft == manipulating) {
      return;
    }
    setState(() {
      _manipulatingDraft = manipulating;
    });
  }

  @override
  void dispose() {
    _draftBodyFocusNode.dispose();
    _draftStartFocusNode.dispose();
    _draftEndFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applyInitialScroll() {
    if (!mounted || _didApplyInitialScroll || !_scrollController.hasClients) {
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
    _didApplyInitialScroll = true;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final blocks = weekCalendarWakePlanBlocks(
      week: widget.week,
      wakePlans: widget.wakePlans,
    );

    return Column(
      children: [
        _DateHeader(
          week: widget.week,
          now: widget.now,
          timeAxisWidth: widget.timeAxisWidth,
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Scrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: _pinching || _manipulatingDraft
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    child: SizedBox(
                      height: _displayHourHeight * TimeOfDayMinutes.hoursPerDay,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: widget.timeAxisWidth,
                            child: _TimeAxis(hourHeight: _displayHourHeight),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) {
                                    final target =
                                        weekCalendarTapTargetFromPosition(
                                          week: widget.week,
                                          localX: details.localPosition.dx,
                                          localY: details.localPosition.dy,
                                          gridWidth: constraints.maxWidth,
                                          gridHeight:
                                              _displayHourHeight *
                                              TimeOfDayMinutes.hoursPerDay,
                                        );
                                    widget.onTargetTap?.call(target);
                                  },
                                  child: Stack(
                                    children: [
                                      _TimeGrid(
                                        week: widget.week,
                                        now: widget.now,
                                        hourHeight: _displayHourHeight,
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
                                            bodyFocusNode: segment.containsStart
                                                ? _draftBodyFocusNode
                                                : null,
                                            startFocusNode:
                                                segment.containsStart
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
                        ],
                      ),
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
  });

  final WeekCalendarDraft draft;
  final _DraftSegment segment;
  final WeekRange week;
  final double pixelsPerMinute;
  final double dayWidth;
  final WeekCalendarDraftChanged? onChanged;
  final ValueChanged<bool> onManipulationChanged;
  final bool interactionEnabled;
  final FocusNode? bodyFocusNode;
  final FocusNode? startFocusNode;
  final FocusNode? endFocusNode;

  @override
  State<_DraftBlock> createState() => _DraftBlockState();
}

class _DraftBlockState extends State<_DraftBlock> {
  late WeekCalendarDraft _initialDraft;
  late _DraftDragMode _dragMode;
  Offset _dragDelta = Offset.zero;
  int? _activePointer;
  Offset? _lastPointerPosition;
  static final _movePreviousDayAction = CustomSemanticsAction(
    label: 'Move to previous day',
  );
  static final _moveNextDayAction = CustomSemanticsAction(
    label: 'Move to next day',
  );

  void _startManipulation(_DraftDragMode mode) {
    _initialDraft = widget.draft;
    _dragDelta = Offset.zero;
    _dragMode = mode;
    widget.onManipulationChanged(true);
  }

  void _beginPointer(PointerDownEvent event, _DraftDragMode mode) {
    if (_activePointer != null || !widget.interactionEnabled) {
      return;
    }
    _activePointer = event.pointer;
    _lastPointerPosition = event.position;
    _startManipulation(mode);
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
    _endManipulation();
  }

  void _applyDragDelta(Offset delta) {
    if (!widget.interactionEnabled) {
      return;
    }
    _dragDelta += delta;
    final minuteDelta =
        ((_dragDelta.dy / widget.pixelsPerMinute) /
                weekCalendarDraftSnapInterval.inMinutes)
            .round() *
        weekCalendarDraftSnapInterval.inMinutes;
    final next = switch (_dragMode) {
      _DraftDragMode.move => clampWeekCalendarDraftToRange(
        draft: _initialDraft.moveBy(
          days: (_dragDelta.dx / widget.dayWidth).round(),
          minutes: minuteDelta,
        ),
        week: widget.week,
      ),
      _DraftDragMode.resizeStart => _initialDraft.resizeStartBy(
        Duration(minutes: minuteDelta),
      ),
      _DraftDragMode.resizeEnd => _initialDraft.resizeEndBy(
        Duration(minutes: minuteDelta),
      ),
    };
    widget.onChanged?.call(next);
  }

  void _adjustDraft(_DraftDragMode mode, {int minutes = 0, int days = 0}) {
    if (!widget.interactionEnabled) {
      return;
    }
    final delta = Duration(minutes: minutes);
    final next = switch (mode) {
      _DraftDragMode.move => clampWeekCalendarDraftToRange(
        draft: widget.draft.moveBy(days: days, minutes: minutes),
        week: widget.week,
      ),
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
    widget.onManipulationChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final height = (widget.segment.durationMinutes * widget.pixelsPerMinute)
        .clamp(24, double.infinity)
        .toDouble();
    final bodyListener = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        widget.bodyFocusNode?.requestFocus();
        _beginPointer(event, _DraftDragMode.move);
      },
      onPointerMove: _movePointer,
      onPointerUp: _endPointer,
      onPointerCancel: _endPointer,
      child: DecoratedBox(
        key: ValueKey(
          'week-calendar-draft-body-${widget.draft.id}-'
          '${widget.segment.dayIndex}',
        ),
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer.withValues(alpha: 0.28),
          border: Border.all(color: colorScheme.tertiary, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
    final bodyFocusNode = widget.bodyFocusNode;
    final body = bodyFocusNode == null
        ? bodyListener
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
              child: bodyListener,
            ),
          );
    return Positioned(
      key: ValueKey(
        'week-calendar-draft-segment-${widget.draft.id}-'
        '${widget.segment.dayIndex}',
      ),
      left: widget.segment.dayIndex * widget.dayWidth + 2,
      top: widget.segment.topMinute * widget.pixelsPerMinute - 14,
      width: (widget.dayWidth - 4).clamp(0, double.infinity),
      height: height + 28,
      child: IgnorePointer(
        ignoring: !widget.interactionEnabled,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(top: 14, left: 0, right: 0, height: height, child: body),
            if (widget.segment.containsStart)
              _DraftHandleControl(
                key: const ValueKey('week-calendar-draft-start-handle'),
                top: 0,
                color: colorScheme.tertiary,
                alignStart: true,
                mode: _DraftDragMode.resizeStart,
                onPointerDown: _beginPointer,
                onPointerMove: _movePointer,
                onPointerEnd: _endPointer,
                value: _accessibleDateTime(widget.draft.startAt),
                interactionEnabled: widget.interactionEnabled,
                focusNode: widget.startFocusNode!,
                onAdjustMinutes: (minutes) =>
                    _adjustDraft(_DraftDragMode.resizeStart, minutes: minutes),
              ),
            if (widget.segment.containsEnd)
              _DraftHandleControl(
                key: const ValueKey('week-calendar-draft-end-handle'),
                top: height,
                color: colorScheme.tertiary,
                alignStart: false,
                mode: _DraftDragMode.resizeEnd,
                onPointerDown: _beginPointer,
                onPointerMove: _movePointer,
                onPointerEnd: _endPointer,
                value: _accessibleDateTime(widget.draft.endAt),
                interactionEnabled: widget.interactionEnabled,
                focusNode: widget.endFocusNode!,
                onAdjustMinutes: (minutes) =>
                    _adjustDraft(_DraftDragMode.resizeEnd, minutes: minutes),
              ),
          ],
        ),
      ),
    );
  }
}

class _DraftHandleControl extends StatefulWidget {
  const _DraftHandleControl({
    super.key,
    required this.top,
    required this.color,
    required this.alignStart,
    required this.mode,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerEnd,
    required this.value,
    required this.interactionEnabled,
    required this.focusNode,
    required this.onAdjustMinutes,
  });

  final double top;
  final Color color;
  final bool alignStart;
  final _DraftDragMode mode;
  final void Function(PointerDownEvent event, _DraftDragMode mode)
  onPointerDown;
  final void Function(PointerMoveEvent event) onPointerMove;
  final void Function(PointerEvent event) onPointerEnd;
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
      top: widget.top,
      left: widget.alignStart ? 0 : null,
      right: widget.alignStart ? null : 0,
      width: 24,
      height: 28,
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
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              widget.focusNode.requestFocus();
              widget.onPointerDown(event, widget.mode);
            },
            onPointerMove: widget.onPointerMove,
            onPointerUp: widget.onPointerEnd,
            onPointerCancel: widget.onPointerEnd,
            child: Center(
              child: Container(
                width: 12,
                height: 12,
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
  const _DateHeader({
    required this.week,
    required this.now,
    required this.timeAxisWidth,
  });

  final WeekRange week;
  final DateTime now;
  final double timeAxisWidth;

  @override
  Widget build(BuildContext context) {
    final today = CalendarDay.fromDateTime(now);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(width: timeAxisWidth),
        for (final day in week.days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _weekdayLabel(day.weekday),
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
                      color: day == today
                          ? colorScheme.primary
                          : Colors.transparent,
                    ),
                    child: Text(
                      '${day.day}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: day == today
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
  });

  final WeekRange week;
  final DateTime now;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = CalendarDay.fromDateTime(now);
    final currentMinute =
        now.hour * TimeOfDayMinutes.minutesPerHour + now.minute;

    return CustomPaint(
      painter: _TimeGridPainter(
        lineColor: colorScheme.outlineVariant,
        dayLineColor: colorScheme.outline,
        currentTimeColor: colorScheme.error,
        hourHeight: hourHeight,
        visibleDays: week.visibleDays,
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
    required this.dayLineColor,
    required this.currentTimeColor,
    required this.hourHeight,
    required this.visibleDays,
    required this.currentDayIndex,
    required this.currentMinute,
  });

  final Color lineColor;
  final Color dayLineColor;
  final Color currentTimeColor;
  final double hourHeight;
  final int visibleDays;
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
        oldDelegate.dayLineColor != dayLineColor ||
        oldDelegate.currentTimeColor != currentTimeColor ||
        oldDelegate.hourHeight != hourHeight ||
        oldDelegate.visibleDays != visibleDays ||
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
