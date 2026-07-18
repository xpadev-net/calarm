import 'dart:async';

import 'package:flutter/material.dart';

class InlineWakePlanRangeChange {
  const InlineWakePlanRangeChange.accepted({
    required DateTime startAt,
    required DateTime endAt,
  }) : canonicalStartAt = startAt,
       canonicalEndAt = endAt,
       guidance = null;

  const InlineWakePlanRangeChange.rejected(this.guidance)
    : canonicalStartAt = null,
      canonicalEndAt = null;

  final DateTime? canonicalStartAt;
  final DateTime? canonicalEndAt;
  final String? guidance;

  bool get isAccepted => canonicalStartAt != null && canonicalEndAt != null;
}

class InlineWakePlanEditor extends StatefulWidget {
  const InlineWakePlanEditor({
    super.key,
    required this.startAt,
    required this.endAt,
    required this.now,
    required this.saving,
    required this.submissionAttempted,
    required this.onRangeChanged,
    required this.onSave,
    required this.onCancel,
    this.error,
    this.clock,
  });

  final DateTime startAt;
  final DateTime endAt;
  final DateTime now;
  final bool saving;
  final bool submissionAttempted;
  final InlineWakePlanRangeChange Function(DateTime startAt, DateTime endAt)
  onRangeChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String? error;
  final DateTime Function()? clock;

  @override
  State<InlineWakePlanEditor> createState() => _InlineWakePlanEditorState();
}

class _InlineWakePlanEditorState extends State<InlineWakePlanEditor>
    with WidgetsBindingObserver {
  Timer? _targetTimer;
  late DateTime _now;
  late DateTime _pendingStartAt;
  late DateTime _pendingEndAt;
  String? _rangeError;

  bool get _isFuture => _pendingEndAt.isAfter(_now);
  bool get _editingEnabled => !widget.saving && !widget.submissionAttempted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = widget.now;
    _pendingStartAt = widget.startAt;
    _pendingEndAt = widget.endAt;
    _scheduleTargetRefresh();
  }

  @override
  void didUpdateWidget(covariant InlineWakePlanEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startAt != widget.startAt ||
        oldWidget.endAt != widget.endAt) {
      _pendingStartAt = widget.startAt;
      _pendingEndAt = widget.endAt;
      _rangeError = null;
    }
    if (oldWidget.now != widget.now ||
        oldWidget.endAt != widget.endAt ||
        oldWidget.startAt != widget.startAt) {
      _now = widget.now;
      _scheduleTargetRefresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNow();
    } else {
      _targetTimer?.cancel();
    }
  }

  void _scheduleTargetRefresh() {
    _targetTimer?.cancel();
    final delay = _pendingEndAt.difference(_now);
    if (delay <= Duration.zero) {
      return;
    }
    _targetTimer = Timer(delay, _refreshNow);
  }

  void _refreshNow() {
    if (!mounted) {
      return;
    }
    setState(() {
      _now = widget.clock?.call() ?? DateTime.now();
    });
    _scheduleTargetRefresh();
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _pendingStartAt : _pendingEndAt;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 10),
      lastDate: DateTime(current.year + 10, 12, 31),
      helpText: start ? 'Select start date' : 'Select end date',
    );
    if (!mounted || selected == null) {
      return;
    }
    _applyCandidate(
      start: start,
      value: DateTime(
        selected.year,
        selected.month,
        selected.day,
        current.hour,
        current.minute,
      ),
    );
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _pendingStartAt : _pendingEndAt;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: start ? 'Select start time' : 'Select end time',
    );
    if (!mounted || selected == null) {
      return;
    }
    _applyCandidate(
      start: start,
      value: DateTime(
        current.year,
        current.month,
        current.day,
        selected.hour,
        selected.minute,
      ),
    );
  }

  void _applyCandidate({required bool start, required DateTime value}) {
    final nextStart = start ? value : _pendingStartAt;
    final nextEnd = start ? _pendingEndAt : value;
    final change = widget.onRangeChanged(nextStart, nextEnd);
    setState(() {
      _pendingStartAt = change.canonicalStartAt ?? nextStart;
      _pendingEndAt = change.canonicalEndAt ?? nextEnd;
      _rangeError = change.guidance;
    });
    _scheduleTargetRefresh();
  }

  @override
  void dispose() {
    _targetTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guidance =
        _rangeError ??
        (!_isFuture ? 'Move the wake target to a future time.' : widget.error);
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      key: const ValueKey('inline-wake-plan-editor'),
      color: colorScheme.surfaceContainer,
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cancel = IconButton(
                key: const ValueKey('inline-wake-plan-cancel'),
                tooltip: widget.submissionAttempted
                    ? 'Cannot cancel after submission'
                    : 'Cancel',
                onPressed: widget.saving || widget.submissionAttempted
                    ? null
                    : widget.onCancel,
                icon: const Icon(Icons.close),
              );
              final summary = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _rangeLabel(_pendingStartAt, _pendingEndAt),
                    key: const ValueKey('inline-wake-plan-time-range'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Start'),
                        _PickerButton(
                          key: const ValueKey('inline-wake-plan-start-date'),
                          label: _dateLabel(_pendingStartAt),
                          semanticLabel:
                              'Start date ${_dateLabel(_pendingStartAt)}',
                          onPressed: _editingEnabled
                              ? () => _pickDate(start: true)
                              : null,
                        ),
                        _PickerButton(
                          key: const ValueKey('inline-wake-plan-start-time'),
                          label: _timeLabel(_pendingStartAt),
                          semanticLabel:
                              'Start time ${_timeLabel(_pendingStartAt)}',
                          onPressed: _editingEnabled
                              ? () => _pickTime(start: true)
                              : null,
                        ),
                        const Text('End'),
                        _PickerButton(
                          key: const ValueKey('inline-wake-plan-end-date'),
                          label: _dateLabel(_pendingEndAt),
                          semanticLabel:
                              'End date ${_dateLabel(_pendingEndAt)}',
                          onPressed: _editingEnabled
                              ? () => _pickDate(start: false)
                              : null,
                        ),
                        _PickerButton(
                          key: const ValueKey('inline-wake-plan-end-time'),
                          label: _timeLabel(_pendingEndAt),
                          semanticLabel:
                              'End time ${_timeLabel(_pendingEndAt)}',
                          onPressed: _editingEnabled
                              ? () => _pickTime(start: false)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  if (guidance != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        guidance,
                        key: const ValueKey('inline-wake-plan-guidance'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                    ),
                ],
              );
              final save = FilledButton(
                key: const ValueKey('inline-wake-plan-save'),
                onPressed: widget.saving || !_isFuture || _rangeError != null
                    ? null
                    : widget.onSave,
                child: Text(
                  widget.saving
                      ? 'Saving…'
                      : widget.submissionAttempted
                      ? 'Retry'
                      : 'Save',
                ),
              );
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              if (textScale > 1.4 || constraints.maxWidth < 300) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        cancel,
                        const SizedBox(width: 4),
                        Expanded(child: summary),
                      ],
                    ),
                    Align(alignment: Alignment.centerRight, child: save),
                  ],
                );
              }
              return Row(
                children: [
                  cancel,
                  const SizedBox(width: 4),
                  Expanded(child: summary),
                  const SizedBox(width: 8),
                  save,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        visualDensity: VisualDensity.compact,
      ),
      child: Semantics(
        label: semanticLabel,
        excludeSemantics: true,
        child: Text(label),
      ),
    );
  }
}

String _rangeLabel(DateTime startAt, DateTime endAt) {
  final startDate = _dateLabel(startAt);
  final endDate = _dateLabel(endAt);
  final endPrefix = startDate == endDate ? '' : '$endDate ';
  return '$startDate ${_timeLabel(startAt)} – $endPrefix${_timeLabel(endAt)}';
}

String _dateLabel(DateTime value) =>
    '${value.year}/${value.month}/${value.day}';

String _timeLabel(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
