import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../../week_calendar/week_calendar.dart';
import '../application/wake_plan_service.dart';
import '../domain/wake_plan_domain.dart';
import 'create_wake_plan_sheet.dart';

typedef WakePlanEditSave =
    Future<WakePlanSchedulingResult> Function(WakePlan plan);
typedef WakePlanDelete = Future<WakePlanSchedulingResult> Function(String id);
typedef WakePlanSkip = Future<WakePlanSchedulingResult> Function(WakePlan plan);
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
    required this.onEdit,
    required this.onDelete,
    required this.onSkipNext,
    required this.onUndoSkipNext,
    required this.loadOccurrences,
    required this.onSetOccurrenceEnabled,
  });

  final WeekCalendarWakePlanTapTarget target;
  final DateTime now;
  final DateTime Function() clock;
  final AppSettings defaults;
  final List<WakePlan> existingWakePlans;
  final WakePlanEditSave onEdit;
  final WakePlanDelete onDelete;
  final WakePlanSkip onSkipNext;
  final WakePlanSkip onUndoSkipNext;
  final WakePlanOccurrenceLoader loadOccurrences;
  final WakePlanOccurrenceToggle onSetOccurrenceEnabled;

  @override
  State<WakePlanDetailSheet> createState() => _WakePlanDetailSheetState();
}

class _WakePlanDetailSheetState extends State<WakePlanDetailSheet> {
  bool _deleting = false;
  bool _updatingSkip = false;
  bool _loadingOccurrences = true;
  List<AlarmOccurrence> _occurrences = const [];
  final Set<String> _updatingOccurrenceIds = {};
  String? _occurrenceLoadError;
  String? _warning;

  WakePlan get _wakePlan => widget.target.wakePlan;

  @override
  void initState() {
    super.initState();
    _loadOccurrences();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _wakePlan;
    final nextFire = wakePlanNextFireLabel(plan: plan, now: widget.now);
    final nextTargetDay = nextWakePlanTargetDay(plan: plan, now: widget.now);
    final hasSkip = plan.skipNextDate != null;
    final actionsDisabled =
        _deleting || _updatingSkip || _updatingOccurrenceIds.isNotEmpty;
    final toggleableOccurrences =
        _occurrences
            .where(
              (occurrence) => occurrence.isUserToggleEligibleAt(widget.now),
            )
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
              _InfoRow(label: 'Skip state', value: _skipLabel(plan)),
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
              if (plan.repeatRule.type != RepeatType.oneTime || hasSkip) ...[
                OutlinedButton.icon(
                  onPressed: actionsDisabled
                      ? null
                      : hasSkip
                      ? _undoSkipNext
                      : nextTargetDay == null
                      ? null
                      : _skipNext,
                  icon: _updatingSkip
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(hasSkip ? Icons.undo : Icons.skip_next),
                  label: Text(
                    hasSkip
                        ? 'Undo skip'
                        : nextTargetDay == null
                        ? 'No next target to skip'
                        : 'Skip next target',
                  ),
                ),
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

  Future<void> _skipNext() {
    return _updateSkip(() => widget.onSkipNext(_wakePlan));
  }

  Future<void> _undoSkipNext() {
    return _updateSkip(() => widget.onUndoSkipNext(_wakePlan));
  }

  Future<void> _updateSkip(
    Future<WakePlanSchedulingResult> Function() action,
  ) async {
    if (_updatingSkip || _deleting) {
      return;
    }

    setState(() {
      _updatingSkip = true;
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
        _updatingSkip = false;
        _warning = result.warning?.message ?? 'Wake plan could not be updated.';
      });
    } catch (error, stackTrace) {
      debugPrint('WakePlanDetailSheet skip update failed: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _updatingSkip = false;
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

String _skipLabel(WakePlan plan) {
  final skipNextDate = plan.skipNextDate;
  if (skipNextDate == null) {
    return 'None';
  }
  return 'Skipping next target on ${_dateLabel(skipNextDate)}';
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
