import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class WeekCalendarPreserveVisibleTimeScrollPhysics extends ScrollPhysics {
  const WeekCalendarPreserveVisibleTimeScrollPhysics({super.parent});

  @override
  WeekCalendarPreserveVisibleTimeScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return WeekCalendarPreserveVisibleTimeScrollPhysics(parent: buildParent(ancestor));
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
class WeekCalendarTwoPointerScaleGestureRecognizer extends OneSequenceGestureRecognizer {
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
