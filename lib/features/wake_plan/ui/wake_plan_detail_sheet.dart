import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../../week_calendar/week_calendar.dart';
import '../application/wake_plan_service.dart';
import '../domain/wake_plan_domain.dart';
import 'create_wake_plan_sheet.dart';

typedef WakePlanEditSave =
    Future<WakePlanSchedulingResult> Function(WakePlan plan);
typedef WakePlanDelete = Future<WakePlanSchedulingResult> Function(String id);
typedef WakePlanOccurrenceSkip =
    Future<WakePlanSchedulingResult> Function(WakePlan plan, CalendarDay day);
typedef WakePlanOccurrenceMove =
    Future<WakePlanSchedulingResult> Function({
      required WakePlan wakePlan,
      required CalendarDay fromDay,
      required CalendarDay toDay,
      TimeOfDayMinutes? toTime,
    });
typedef WakePlanDeleteThisAndFollowing =
    Future<WakePlanSchedulingResult> Function(WakePlan plan, CalendarDay day);
typedef WakePlanOccurrenceLoader =
    Future<List<AlarmOccurrence>> Function(String wakePlanId);
typedef WakePlanOccurrenceToggle =
    Future<AlarmOccurrenceToggleResult> Function({
      required String wakePlanId,
      required String occurrenceId,
      required bool enabled,
    });

class WakePlanDetailSheet extends StatefulWidget {
  const WakePlanDetailSheet({
    super.key,
    required this.target,
    required this.now,
    required this.clock,
    required this.defaults,
    required this.existingWakePlans,
    required this.existingExceptions,
    required this.onEdit,
    required this.onDelete,
    required this.onSkipOccurrence,
    required this.onUndoSkipOccurrence,
    required this.onMoveOccurrence,
    required this.onDeleteThisAndFollowing,
    required this.loadOccurrences,
    required this.onSetOccurrenceEnabled,
  });

  final WeekCalendarWakePlanTapTarget target;
  final DateTime now;
  final DateTime Function() clock;
  final AppSettings defaults;
  final List<WakePlan> existingWakePlans;

  /// Per-occurrence skip/move exceptions currently recorded for this plan.
  final List<WakePlanOccurrenceException> existingExceptions;
  final WakePlanEditSave onEdit;
  final WakePlanDelete onDelete;
  final WakePlanOccurrenceSkip onSkipOccurrence;
  final WakePlanOccurrenceSkip onUndoSkipOccurrence;
  final WakePlanOccurrenceMove onMoveOccurrence;
  final WakePlanDeleteThisAndFollowing onDeleteThisAndFollowing;
  final WakePlanOccurrenceLoader loadOccurrences;
  final WakePlanOccurrenceToggle onSetOccurrenceEnabled;

  @override
  State<WakePlanDetailSheet> createState() => _WakePlanDetailSheetState();
}

enum _OccurrenceDeleteScope { thisOccurrence, thisAndFollowing }

class _WakePlanDetailSheetState extends State<WakePlanDetailSheet> {
  bool _deleting = false;
  bool _updatingOccurrenceAction = false;
  bool _loadingOccurrences = true;
  List<AlarmOccurrence> _occurrences = const [];
  final Set<String> _updatingOccurrenceIds = {};
  final Set<String> _updatingExceptionIds = {};
  Timer? _eligibilityTimer;
  String? _occurrenceLoadError;
  String? _warning;

  WakePlan get _wakePlan => widget.target.wakePlan;
  CalendarDay get _originalDay => widget.target.originalDay;

  @override
  void initState() {
    super.initState();
    _loadOccurrences();
  }

  @override
  void dispose() {
    _eligibilityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _wakePlan;
    final liveNow = widget.clock();
    final nextFire = wakePlanNextFireLabel(plan: plan, now: liveNow);
    final isRepeating = plan.repeatRule.type != RepeatType.oneTime;
    final actionsDisabled =
        _deleting ||
        _updatingOccurrenceAction ||
        _updatingOccurrenceIds.isNotEmpty ||
        _updatingExceptionIds.isNotEmpty;
    final toggleableOccurrences =
        _occurrences
            .where((occurrence) => occurrence.isUserToggleEligibleAt(liveNow))
            .toList(growable: false)
          ..sort(
            (left, right) => left.scheduledAt.compareTo(right.scheduledAt),
          );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Wake plan detail',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: actionsDisabled
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Wake target',
                value: _dateTimeLabel(plan.targetAt(widget.target.targetDay)),
              ),
              _InfoRow(
                label: 'Next fire',
                value: nextFire ?? 'No future alarm',
              ),
              _InfoRow(label: 'Repeat', value: _repeatLabel(plan.repeatRule)),
              _InfoRow(
                label: 'Window',
                value:
                    '${_durationLabel(plan.startOffset)} before, every ${_durationLabel(plan.interval)}',
              ),
              if (_warning != null) ...[
                const SizedBox(height: 12),
                _InlineWarning(text: _warning!),
              ],
              const SizedBox(height: 16),
              if (isRepeating) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: actionsDisabled
                            ? null
                            : _deleteThisOccurrence,
                        icon: _updatingOccurrenceAction
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.event_busy),
                        label: const Text('Delete this occurrence…'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: actionsDisabled ? null : _moveThisOccurrence,
                        icon: const Icon(Icons.event_repeat),
                        label: const Text('Move this occurrence…'),
                      ),
                    ),
                  ],
                ),
                if (widget.existingExceptions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Exceptions',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final exception in widget.existingExceptions)
                    _ExceptionRow(
                      exception: exception,
                      updating: _updatingExceptionIds.contains(exception.id),
                      disabled: actionsDisabled,
                      onUndo: () => _undoException(exception),
                    ),
                ],
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: actionsDisabled ? null : _openEditSheet,
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                      onPressed: actionsDisabled ? null : _delete,
                      icon: _deleting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Upcoming alarms',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              if (_loadingOccurrences)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_occurrenceLoadError != null)
                Row(
                  children: [
                    const Expanded(child: Text('Could not load alarms.')),
                    TextButton(
                      onPressed: _loadOccurrences,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              else if (toggleableOccurrences.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No future alarms are available.'),
                )
              else
                for (final occurrence in toggleableOccurrences)
                  SwitchListTile(
                    key: ValueKey('occurrence-toggle-${occurrence.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _dateTimeLabel(occurrence.scheduledAt.toDateTime()),
                    ),
                    subtitle: Text(occurrence.isUserDisabled ? 'Off' : 'On'),
                    value: !occurrence.isUserDisabled,
                    onChanged: actionsDisabled
                        ? null
                        : (enabled) => _setOccurrenceEnabled(
                            occurrence: occurrence,
                            enabled: enabled,
                          ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadOccurrences() async {
    if (mounted) {
      setState(() {
        _loadingOccurrences = true;
        _occurrenceLoadError = null;
      });
    }
    try {
      final occurrences = await widget.loadOccurrences(_wakePlan.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _occurrences = occurrences;
        _loadingOccurrences = false;
      });
      _scheduleEligibilityRefresh();
    } catch (error, stackTrace) {
      debugPrint(
        'WakePlanDetailSheet occurrence load failed: $error\n$stackTrace',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingOccurrences = false;
        _occurrenceLoadError = 'Could not load alarms.';
      });
    }
  }

  Future<void> _setOccurrenceEnabled({
    required AlarmOccurrence occurrence,
    required bool enabled,
  }) async {
    if (_updatingOccurrenceIds.contains(occurrence.id)) {
      return;
    }
    setState(() {
      _updatingOccurrenceIds.add(occurrence.id);
      _warning = null;
    });
    try {
      final result = await widget.onSetOccurrenceEnabled(
        wakePlanId: _wakePlan.id,
        occurrenceId: occurrence.id,
        enabled: enabled,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final updated = result.occurrence;
        if (updated != null) {
          _occurrences = [
            for (final item in _occurrences)
              if (item.id == updated.id) updated else item,
          ];
        }
        _updatingOccurrenceIds.remove(occurrence.id);
        _warning = result.warning;
      });
      _scheduleEligibilityRefresh();
    } catch (error, stackTrace) {
      debugPrint(
        'WakePlanDetailSheet occurrence update failed: $error\n$stackTrace',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _updatingOccurrenceIds.remove(occurrence.id);
        _warning = 'The alarm occurrence could not be updated.';
      });
    }
  }

  void _scheduleEligibilityRefresh() {
    _eligibilityTimer?.cancel();
    final now = widget.clock();
    DateTime? nextBoundary;
    for (final occurrence in _occurrences) {
      if (!occurrence.isUserToggleEligibleAt(now)) {
        continue;
      }
      final boundary = occurrence.scheduledAt.toDateTime();
      if (nextBoundary == null || boundary.isBefore(nextBoundary)) {
        nextBoundary = boundary;
      }
    }
    if (nextBoundary == null) {
      return;
    }
    final scheduledBoundary = nextBoundary;
    _eligibilityTimer = Timer(scheduledBoundary.difference(now), () {
      if (!mounted) {
        return;
      }
      setState(() {});
      _scheduleEligibilityRefresh();
    });
  }

  Future<void> _openEditSheet() async {
    final plan = _wakePlan;
    final result = await showModalBottomSheet<WakePlanSchedulingResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return CreateWakePlanSheet(
          initialTarget: WeekCalendarTapTarget(
            day: widget.target.targetDay,
            time: plan.targetTime,
          ),
          now: widget.now,
          clock: widget.clock,
          defaults: widget.defaults,
          existingWakePlans: widget.existingWakePlans,
          existingWakePlan: plan,
          onSave: widget.onEdit,
        );
      },
    );
    if (!mounted || result == null) {
      return;
    }
    if (result.isSuccess) {
      Navigator.pop(context, result);
      return;
    }
    setState(() {
      _warning = result.warning?.message ?? 'Wake plan could not be updated.';
    });
  }

  Future<void> _delete() async {
    final isRepeating = _wakePlan.repeatRule.type != RepeatType.oneTime;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            isRepeating ? 'Delete repeating wake plan?' : 'Delete wake plan?',
          ),
          content: Text(
            isRepeating
                ? 'This removes future alarms for every repeat of this wake plan.'
                : 'This removes the selected wake plan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _deleting = true;
      _warning = null;
    });
    try {
      final result = await widget.onDelete(_wakePlan.id);
      if (!mounted) {
        return;
      }
      if (result.isSuccess) {
        Navigator.pop(context, result);
        return;
      }
      setState(() {
        _deleting = false;
        _warning = result.warning?.message ?? 'Wake plan could not be deleted.';
      });
    } catch (error, stackTrace) {
      debugPrint('WakePlanDetailSheet delete failed: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _deleting = false;
        _warning = 'Wake plan could not be deleted.';
      });
    }
  }

  Future<void> _deleteThisOccurrence() async {
    final scope = await showDialog<_OccurrenceDeleteScope>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete this occurrence?'),
          content: const Text(
            'Choose whether to delete just this occurrence or this and every '
            'later occurrence of this wake plan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _OccurrenceDeleteScope.thisOccurrence),
              child: const Text('This event only'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _OccurrenceDeleteScope.thisAndFollowing,
              ),
              child: const Text('This and following events'),
            ),
          ],
        );
      },
    );
    if (scope == null || !mounted) {
      return;
    }

    await _updateOccurrenceAction(() {
      return switch (scope) {
        _OccurrenceDeleteScope.thisOccurrence => widget.onSkipOccurrence(
          _wakePlan,
          _originalDay,
        ),
        _OccurrenceDeleteScope.thisAndFollowing =>
          widget.onDeleteThisAndFollowing(_wakePlan, _originalDay),
      };
    });
  }

  Future<void> _moveThisOccurrence() async {
    final plan = _wakePlan;
    final currentTargetDay = widget.target.targetDay;
    final toDay = await showDatePicker(
      context: context,
      initialDate: currentTargetDay.startOfDay,
      firstDate: widget.now.subtract(const Duration(days: 1)),
      lastDate: widget.now.add(const Duration(days: 365)),
    );
    if (toDay == null || !mounted) {
      return;
    }
    final toTimeOfDay = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: plan.targetTime.hour,
        minute: plan.targetTime.minute,
      ),
    );
    if (toTimeOfDay == null || !mounted) {
      return;
    }

    await _updateOccurrenceAction(() {
      return widget.onMoveOccurrence(
        wakePlan: plan,
        fromDay: _originalDay,
        toDay: CalendarDay.fromDateTime(toDay),
        toTime: TimeOfDayMinutes.fromHourMinute(
          hour: toTimeOfDay.hour,
          minute: toTimeOfDay.minute,
        ),
      );
    });
  }

  Future<void> _undoException(WakePlanOccurrenceException exception) async {
    if (_updatingExceptionIds.contains(exception.id) || _deleting) {
      return;
    }
    setState(() {
      _updatingExceptionIds.add(exception.id);
      _warning = null;
    });
    try {
      final result = await widget.onUndoSkipOccurrence(
        _wakePlan,
        exception.originalDay,
      );
      if (!mounted) {
        return;
      }
      if (result.isSuccess) {
        Navigator.pop(context, result);
        return;
      }
      setState(() {
        _updatingExceptionIds.remove(exception.id);
        _warning = result.warning?.message ?? 'Wake plan could not be updated.';
      });
    } catch (error, stackTrace) {
      debugPrint(
        'WakePlanDetailSheet undo exception failed: $error\n$stackTrace',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _updatingExceptionIds.remove(exception.id);
        _warning = 'Wake plan could not be updated.';
      });
    }
  }

  Future<void> _updateOccurrenceAction(
    Future<WakePlanSchedulingResult> Function() action,
  ) async {
    if (_updatingOccurrenceAction || _deleting) {
      return;
    }

    setState(() {
      _updatingOccurrenceAction = true;
      _warning = null;
    });
    try {
      final result = await action();
      if (!mounted) {
        return;
      }
      if (result.isSuccess) {
        Navigator.pop(context, result);
        return;
      }
      setState(() {
        _updatingOccurrenceAction = false;
        _warning = result.warning?.message ?? 'Wake plan could not be updated.';
      });
    } catch (error, stackTrace) {
      debugPrint(
        'WakePlanDetailSheet occurrence action failed: $error\n$stackTrace',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _updatingOccurrenceAction = false;
        _warning = 'Wake plan could not be updated.';
      });
    }
  }
}

String? wakePlanResultNextFireLabel({
  required WakePlanSchedulingResult result,
  required DateTime now,
}) {
  final futureOccurrences =
      result.occurrences
          .where(
            (occurrence) =>
                occurrence.status == AlarmOccurrenceStatus.scheduled &&
                !occurrence.scheduledAt.toDateTime().isBefore(now),
          )
          .toList()
        ..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));
  if (futureOccurrences.isEmpty) {
    return null;
  }
  return _dateTimeLabel(futureOccurrences.first.scheduledAt.toDateTime());
}

String? wakePlanNextFireLabel({required WakePlan plan, required DateTime now}) {
  final today = CalendarDay.fromDateTime(now);
  if (plan.repeatRule.type == RepeatType.oneTime) {
    final oneTimeDate = plan.repeatRule.oneTimeDate;
    if (oneTimeDate == null || oneTimeDate.compareTo(today) < 0) {
      return null;
    }
  }
  DateTime? nextFire;
  for (var offset = 0; offset <= 370; offset += 1) {
    final day = today.addDays(offset);
    if (!plan.occursOn(day)) {
      continue;
    }
    final targetAt = plan.targetAt(day);
    for (
      var alarmAt = plan.startAt(day);
      alarmAt.isBefore(targetAt);
      alarmAt = alarmAt.add(plan.interval)
    ) {
      if (!alarmAt.isBefore(now) &&
          (nextFire == null || alarmAt.isBefore(nextFire))) {
        nextFire = alarmAt;
      }
    }
    if (!targetAt.isBefore(now) &&
        (nextFire == null || targetAt.isBefore(nextFire))) {
      nextFire = targetAt;
    }
    if (nextFire != null) {
      break;
    }
  }

  return nextFire == null ? null : _dateTimeLabel(nextFire);
}

String _repeatLabel(RepeatRule repeatRule) {
  return switch (repeatRule.type) {
    RepeatType.oneTime => 'No repeat',
    RepeatType.weekly => 'Weekly on ${_weekdayLabels(repeatRule.weekdays)}',
  };
}

String _weekdayLabels(Set<Weekday> weekdays) {
  return Weekday.values
      .where(weekdays.contains)
      .map(
        (weekday) => switch (weekday) {
          Weekday.monday => 'Mon',
          Weekday.tuesday => 'Tue',
          Weekday.wednesday => 'Wed',
          Weekday.thursday => 'Thu',
          Weekday.friday => 'Fri',
          Weekday.saturday => 'Sat',
          Weekday.sunday => 'Sun',
        },
      )
      .join(', ');
}

String _exceptionLabel(WakePlanOccurrenceException exception) {
  return switch (exception.type) {
    WakePlanOccurrenceExceptionType.skipped =>
      'Skipped on ${_dateLabel(exception.originalDay)}',
    WakePlanOccurrenceExceptionType.moved =>
      'Moved from ${_dateLabel(exception.originalDay)} '
          'to ${_dateLabel(exception.movedToDay!)}',
  };
}

String _dateLabel(CalendarDay day) {
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

String _durationLabel(Duration duration) {
  if (duration.inMinutes < TimeOfDayMinutes.minutesPerHour) {
    return '${duration.inMinutes} min';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes % TimeOfDayMinutes.minutesPerHour;
  if (minutes == 0) {
    return '$hours hr';
  }
  return '$hours hr $minutes min';
}

String _dateTimeLabel(DateTime dateTime) {
  return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-'
      '${dateTime.day.toString().padLeft(2, '0')} '
      '${dateTime.hour.toString().padLeft(2, '0')}:'
      '${dateTime.minute.toString().padLeft(2, '0')}';
}

class _ExceptionRow extends StatelessWidget {
  const _ExceptionRow({
    required this.exception,
    required this.updating,
    required this.disabled,
    required this.onUndo,
  });

  final WakePlanOccurrenceException exception;
  final bool updating;
  final bool disabled;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(_exceptionLabel(exception))),
          TextButton(
            onPressed: disabled ? null : onUndo,
            child: updating
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Undo'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
