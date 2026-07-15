import 'dart:async';

import 'package:flutter/material.dart';

class InlineWakePlanEditor extends StatefulWidget {
  const InlineWakePlanEditor({
    super.key,
    required this.startAt,
    required this.endAt,
    required this.now,
    required this.saving,
    required this.submissionAttempted,
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

  bool get _isFuture => widget.endAt.isAfter(_now);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = widget.now;
    _scheduleTargetRefresh();
  }

  @override
  void didUpdateWidget(covariant InlineWakePlanEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.now != widget.now || oldWidget.endAt != widget.endAt) {
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
    final delay = widget.endAt.difference(_now);
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

  @override
  void dispose() {
    _targetTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guidance = !_isFuture
        ? 'Move the wake target to a future time.'
        : widget.error;
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
                    _rangeLabel(widget.startAt, widget.endAt),
                    key: const ValueKey('inline-wake-plan-time-range'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (guidance != null)
                    Text(
                      guidance,
                      key: const ValueKey('inline-wake-plan-guidance'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
                    ),
                ],
              );
              final save = FilledButton(
                key: const ValueKey('inline-wake-plan-save'),
                onPressed: widget.saving || !_isFuture ? null : widget.onSave,
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

String _rangeLabel(DateTime startAt, DateTime endAt) {
  final startDate = '${startAt.month}/${startAt.day}';
  final endDate = '${endAt.month}/${endAt.day}';
  final endPrefix = startDate == endDate ? '' : '$endDate ';
  return '$startDate ${_timeLabel(startAt)} – $endPrefix${_timeLabel(endAt)}';
}

String _timeLabel(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
