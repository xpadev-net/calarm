import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../core/time/time.dart';
import '../model/week_calendar_interaction.dart';
import 'week_calendar_format.dart';
import 'week_calendar_view.dart';

enum WeekCalendarDraftDragMode { move, resizeStart, resizeEnd }

const _draftHandleHitWidth = 48.0;
const _draftHandleHitHeight = 48.0;
const _draftHandleOverflow = _draftHandleHitHeight / 2;
const _draftHandleVisualDiameter = 12.0;
const _draftHandleVisualRadius = _draftHandleVisualDiameter / 2;
const _draftHandleHorizontalInset = 12.0;

class WeekCalendarDraftSegment {
  const WeekCalendarDraftSegment({
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

String weekCalendarDraftSegmentRole(WeekCalendarDraftSegment segment) {
  if (segment.containsStart) {
    return 'start';
  }
  if (segment.containsEnd) {
    return 'end';
  }
  return 'middle-${segment.dayIndex}';
}

List<WeekCalendarDraftSegment> weekCalendarDraftSegments(WeekCalendarDraft draft, WeekRange week) {
  final segments = <WeekCalendarDraftSegment>[];
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
      WeekCalendarDraftSegment(
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

class WeekCalendarDraftBlock extends StatefulWidget {
  const WeekCalendarDraftBlock({
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
    this.disableHorizontalDayChange = false,
  });

  final WeekCalendarDraft draft;
  final WeekCalendarDraftSegment segment;
  final WeekRange week;
  final double pixelsPerMinute;
  final double dayWidth;
  final WeekCalendarDraftChanged? onChanged;
  final ValueChanged<WeekCalendarDraftDragMode?> onManipulationChanged;
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
  // The 1-day view renders exactly one day wide, so a horizontal drag delta
  // can never land on a different, visible day the way it does in the 3/7-
  // day views — forcing the day delta to zero there keeps a move drag from
  // silently trying to jump the draft to an off-screen day.
  final bool disableHorizontalDayChange;

  @override
  State<WeekCalendarDraftBlock> createState() => _DraftBlockState();
}

class _DraftBlockState extends State<WeekCalendarDraftBlock> {
  late WeekCalendarDraft _initialDraft;
  late WeekCalendarDraftDragMode _dragMode;
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
  void didUpdateWidget(covariant WeekCalendarDraftBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `interactionEnabled` flips off mid-gesture when a second finger turns
    // this into a pinch (see the `!_pinching` wiring at each calendar
    // display mode's call site) — but a plain pointer `Listener` isn't part
    // of the gesture arena, so the pointer that started this drag keeps
    // being routed here regardless of who wins the arena. Without this, the
    // ghost would keep following that finger until it's lifted, and the
    // move would still commit then; cancelling as soon as interaction is
    // disabled matches the immediate visual/interaction cutoff everywhere
    // else pinch takes over.
    if (_activePointer != null &&
        oldWidget.interactionEnabled &&
        !widget.interactionEnabled) {
      _cancelManipulation();
    }
  }

  @override
  void dispose() {
    _removeDragOverlay();
    _dragOverlayOffset.dispose();
    super.dispose();
  }

  void _cancelManipulation() {
    _activePointer = null;
    _lastPointerPosition = null;
    _removeDragOverlay();
    setState(() {
      _dragDelta = Offset.zero;
      _previewDayDelta = 0;
      _previewMinuteDelta = 0;
    });
    _endManipulation();
  }

  void _startManipulation(WeekCalendarDraftDragMode mode) {
    _initialDraft = widget.draft;
    _dragDelta = Offset.zero;
    _previewDayDelta = 0;
    _previewMinuteDelta = 0;
    _dragMode = mode;
    widget.onManipulationChanged(mode);
  }

  void _beginPointer(PointerDownEvent event, WeekCalendarDraftDragMode mode) {
    if (_activePointer != null || !widget.interactionEnabled) {
      return;
    }
    switch (mode) {
      case WeekCalendarDraftDragMode.move:
        widget.bodyFocusNode?.requestFocus();
      case WeekCalendarDraftDragMode.resizeStart:
        widget.startFocusNode?.requestFocus();
      case WeekCalendarDraftDragMode.resizeEnd:
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
    if (mode == WeekCalendarDraftDragMode.move) {
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

  WeekCalendarDraftDragMode? _dragModeForPosition(
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
        return WeekCalendarDraftDragMode.move;
      }
      if (startDistance == endDistance) {
        return position.dy <= (startCenter.dy + endCenter.dy) / 2
            ? WeekCalendarDraftDragMode.resizeStart
            : WeekCalendarDraftDragMode.resizeEnd;
      }
      return startDistance < endDistance
          ? WeekCalendarDraftDragMode.resizeStart
          : WeekCalendarDraftDragMode.resizeEnd;
    }
    if (hitsStart) {
      if (bodyRect.contains(position) && !hitsStartVisual) {
        return WeekCalendarDraftDragMode.move;
      }
      return WeekCalendarDraftDragMode.resizeStart;
    }
    if (hitsEnd) {
      if (bodyRect.contains(position) && !hitsEndVisual) {
        return WeekCalendarDraftDragMode.move;
      }
      return WeekCalendarDraftDragMode.resizeEnd;
    }
    if (bodyRect.contains(position)) {
      return WeekCalendarDraftDragMode.move;
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
    // A `PointerCancelEvent` (or interaction already disabled — e.g. pinch
    // took over before this arrived) means the gesture never reached a
    // normal release, so the previewed move is discarded rather than
    // committed — only a genuine `PointerUpEvent` while still enabled counts
    // as the user actually letting go of the drag.
    if (event is PointerCancelEvent || !widget.interactionEnabled) {
      _cancelManipulation();
      return;
    }
    _activePointer = null;
    _lastPointerPosition = null;
    if (_dragMode == WeekCalendarDraftDragMode.move) {
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
      case WeekCalendarDraftDragMode.move:
        // A move is only previewed here — via the overlay ghost started in
        // `_beginPointer` — rather than committed through `widget.onChanged`
        // on every pointer move. Committing immediately would recompute
        // `weekCalendarDraftSegments` against `widget.week` on each frame, and as soon
        // as the dragged block crossed out of that page's day/week window
        // it would stop being one of the segments rendered there —
        // unmounting this exact `WeekCalendarDraftBlock` mid-gesture and silently
        // dropping the pointer capture that drives the drag. The real
        // commit (with no week clamp) happens once, on release, in
        // `_endPointer`.
        //
        // The day/minute delta is snapped here (not left to follow the raw
        // pixel offset) so the ghost always shows one of the discrete grid
        // positions the drag can actually land on — otherwise where it will
        // stop is ambiguous until the finger lifts.
        final dayDelta = widget.disableHorizontalDayChange
            ? 0
            : (_dragDelta.dx / widget.dayWidth).round();
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
      case WeekCalendarDraftDragMode.resizeStart:
        final minuteDelta = _snappedMinuteDelta(_dragDelta.dy);
        widget.onChanged?.call(
          _initialDraft.resizeStartBy(Duration(minutes: minuteDelta)),
        );
      case WeekCalendarDraftDragMode.resizeEnd:
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

  void _adjustDraft(WeekCalendarDraftDragMode mode, {int minutes = 0, int days = 0}) {
    if (!widget.interactionEnabled) {
      return;
    }
    final delta = Duration(minutes: minutes);
    final next = switch (mode) {
      WeekCalendarDraftDragMode.move => widget.draft.moveBy(days: days, minutes: minutes),
      WeekCalendarDraftDragMode.resizeStart => widget.draft.resizeStartBy(delta),
      WeekCalendarDraftDragMode.resizeEnd => widget.draft.resizeEndBy(delta),
    };
    widget.onChanged?.call(next);
  }

  KeyEventResult _handleBodyKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !widget.interactionEnabled) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _adjustDraft(WeekCalendarDraftDragMode.move, minutes: -5);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _adjustDraft(WeekCalendarDraftDragMode.move, minutes: 5);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _adjustDraft(WeekCalendarDraftDragMode.move, days: -1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _adjustDraft(WeekCalendarDraftDragMode.move, days: 1);
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
                  'Start ${weekCalendarAccessibleDateTime(widget.draft.startAt)}, '
                  'end ${weekCalendarAccessibleDateTime(widget.draft.endAt)}',
              increasedValue: 'Start and end 5 minutes later',
              decreasedValue: 'Start and end 5 minutes earlier',
              onIncrease: widget.interactionEnabled
                  ? () => _adjustDraft(WeekCalendarDraftDragMode.move, minutes: 5)
                  : null,
              onDecrease: widget.interactionEnabled
                  ? () => _adjustDraft(WeekCalendarDraftDragMode.move, minutes: -5)
                  : null,
              customSemanticsActions: widget.interactionEnabled
                  ? {
                      _movePreviousDayAction: () =>
                          _adjustDraft(WeekCalendarDraftDragMode.move, days: -1),
                      _moveNextDayAction: () =>
                          _adjustDraft(WeekCalendarDraftDragMode.move, days: 1),
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
                    mode: WeekCalendarDraftDragMode.resizeStart,
                    value: weekCalendarAccessibleDateTime(widget.draft.startAt),
                    interactionEnabled: widget.interactionEnabled,
                    focusNode: widget.startFocusNode!,
                    onAdjustMinutes: (minutes) => _adjustDraft(
                      WeekCalendarDraftDragMode.resizeStart,
                      minutes: minutes,
                    ),
                  ),
                if (widget.segment.containsEnd)
                  _DraftHandleControl(
                    key: const ValueKey('week-calendar-draft-end-handle'),
                    rect: localEndRect,
                    visualCenter: localEndCenter,
                    color: colorScheme.tertiary,
                    mode: WeekCalendarDraftDragMode.resizeEnd,
                    value: weekCalendarAccessibleDateTime(widget.draft.endAt),
                    interactionEnabled: widget.interactionEnabled,
                    focusNode: widget.endFocusNode!,
                    onAdjustMinutes: (minutes) => _adjustDraft(
                      WeekCalendarDraftDragMode.resizeEnd,
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
  return '${dateTime.month}/${dateTime.day} ${weekCalendarTimeLabel(dateTime)}';
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
  final WeekCalendarDraftDragMode mode;
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
              widget.mode == WeekCalendarDraftDragMode.resizeStart
                  ? 'week-calendar-draft-start-handle-semantics'
                  : 'week-calendar-draft-end-handle-semantics',
            ),
            container: true,
            focusable: true,
            enabled: widget.interactionEnabled,
            label: widget.mode == WeekCalendarDraftDragMode.resizeStart
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
/// [target] would occupy, reusing the same day-splitting [weekCalendarDraftSegments]
/// uses for real drafts so a preview that crosses midnight is shown as a
/// continuation in the next visible day instead of one clipped cell — the
/// same shape the draft created on tap-up will actually have.
///
/// [duration] is capped to [week] the same way the real draft created on
/// tap-up is (see weekCalendarClampDraftDurationToWeek), so a tap on the
/// last visible day never previews — or creates — a continuation past the
/// edge of what's currently on screen.
List<WeekCalendarDraftSegment> weekCalendarTapPreviewSegments({
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
  return weekCalendarDraftSegments(draft, week);
}

/// Shows the grid cell(s) a tap would create a draft in, before the tap is
/// released, so it's obvious ahead of time where the block will land.
class WeekCalendarTapPreviewCell extends StatelessWidget {
  const WeekCalendarTapPreviewCell({
    super.key,
    required this.segment,
    required this.pixelsPerMinute,
    required this.dayWidth,
  });

  final WeekCalendarDraftSegment segment;
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
