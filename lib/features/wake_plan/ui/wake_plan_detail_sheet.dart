import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../../week_calendar/week_calendar.dart';
import '../application/wake_plan_service.dart';
import '../domain/wake_plan_domain.dart';
import 'create_wake_plan_sheet.dart';

typedef WakePlanEditSave =
    Future<WakePlanSchedulingResult> Function(WakePlan plan);
typedef WakePlanDelete = Future<WakePlanSchedulingResult> Function(String id);

class WakePlanDetailSheet extends StatefulWidget {
  const WakePlanDetailSheet({
    super.key,
    required this.target,
    required this.now,
    required this.defaults,
    required this.existingWakePlans,
    required this.onEdit,
    required this.onDelete,
  });

  final WeekCalendarWakePlanTapTarget target;
  final DateTime now;
  final AppSettings defaults;
  final List<WakePlan> existingWakePlans;
  final WakePlanEditSave onEdit;
  final WakePlanDelete onDelete;

  @override
  State<WakePlanDetailSheet> createState() => _WakePlanDetailSheetState();
}

class _WakePlanDetailSheetState extends State<WakePlanDetailSheet> {
  bool _deleting = false;
  String? _warning;

  WakePlan get _wakePlan => widget.target.wakePlan;

  @override
  Widget build(BuildContext context) {
    final plan = _wakePlan;
    final nextFire = wakePlanNextFireLabel(plan: plan, now: widget.now);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
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
                  onPressed: _deleting ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Wake target',
              value: _dateTimeLabel(plan.targetAt(widget.target.targetDay)),
            ),
            _InfoRow(label: 'Next fire', value: nextFire ?? 'No future alarm'),
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _deleting ? null : _openEditSheet,
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
                    onPressed: _deleting ? null : _delete,
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
          ],
        ),
      ),
    );
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
    if (_requiresDeleteConfirmation(_wakePlan)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Delete repeating wake plan?'),
            content: const Text(
              'This removes future alarms for every repeat of this wake plan.',
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

bool _requiresDeleteConfirmation(WakePlan plan) {
  return plan.repeatRule.type != RepeatType.oneTime;
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
  return 'Skipping $skipNextDate';
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
