import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../../week_calendar/week_calendar.dart';
import '../application/wake_plan_service.dart';
import '../domain/wake_plan_domain.dart';

typedef CreateWakePlanSave =
    Future<WakePlanSchedulingResult> Function(WakePlan plan);

class CreateWakePlanSheet extends StatefulWidget {
  const CreateWakePlanSheet({
    super.key,
    required this.initialTarget,
    required this.now,
    required this.defaults,
    required this.existingWakePlans,
    required this.onSave,
    this.existingWakePlan,
    this.clock,
  });

  final WeekCalendarTapTarget initialTarget;
  final DateTime now;
  final AppSettings defaults;
  final List<WakePlan> existingWakePlans;
  final CreateWakePlanSave onSave;
  final WakePlan? existingWakePlan;
  final DateTime Function()? clock;

  @override
  State<CreateWakePlanSheet> createState() => _CreateWakePlanSheetState();
}

class _CreateWakePlanSheetState extends State<CreateWakePlanSheet> {
  late Duration _startOffset;
  late Duration _interval;
  late RepeatType _initialRepeatType;
  late RepeatType _repeatType;
  late TimeOfDayMinutes _targetTime;
  late String _soundId;
  late bool _vibrationEnabled;
  bool _saving = false;
  bool _advancedExpanded = false;
  String? _scheduleWarning;

  CalendarDay get _targetDay => widget.initialTarget.day;

  DateTime get _targetAt => _targetDay.at(_targetTime);

  DateTime get _currentNow => widget.clock?.call() ?? DateTime.now();

  bool get _canProduceFutureSchedule {
    if (_repeatType == RepeatType.weekly) {
      return true;
    }
    return _targetAt.isAfter(_currentNow);
  }

  @override
  void initState() {
    super.initState();
    final existingWakePlan = widget.existingWakePlan;
    _startOffset =
        existingWakePlan?.startOffset ?? widget.defaults.defaultStartOffset;
    _interval = existingWakePlan?.interval ?? widget.defaults.defaultInterval;
    _repeatType =
        existingWakePlan?.repeatRule.type ?? widget.defaults.defaultRepeatType;
    _initialRepeatType = _repeatType;
    _targetTime = existingWakePlan?.targetTime ?? widget.initialTarget.time;
    _soundId = existingWakePlan?.soundId ?? widget.defaults.defaultSoundId;
    _vibrationEnabled =
        existingWakePlan?.vibrationEnabled ??
        widget.defaults.defaultVibrationEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final preview = WakePlanCreatePreview(
      targetAt: _targetAt,
      startOffset: _startOffset,
      interval: _interval,
      now: widget.now,
    );
    final overlaps = _findOverlaps();
    final canSave = !_saving && _canProduceFutureSchedule;

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
                      widget.existingWakePlan == null
                          ? 'Create wake plan'
                          : 'Edit wake plan',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _EditableInfoRow(
                label: 'Wake target',
                value: _dateTimeLabel(_targetAt),
                onPressed: _saving ? null : _pickTargetTime,
              ),
              const SizedBox(height: 12),
              _DurationMenu(
                label: 'Wake window',
                value: _startOffset,
                values: const [
                  Duration(minutes: 30),
                  Duration(minutes: 45),
                  Duration(minutes: 60),
                  Duration(minutes: 90),
                  Duration(hours: 2),
                  Duration(hours: 3),
                ],
                onChanged: (value) => setState(() => _startOffset = value),
              ),
              const SizedBox(height: 12),
              _DurationMenu(
                label: 'Interval',
                value: _interval,
                values: const [
                  Duration(minutes: 5),
                  Duration(minutes: 10),
                  Duration(minutes: 15),
                  Duration(minutes: 20),
                  Duration(minutes: 30),
                ],
                onChanged: (value) => setState(() => _interval = value),
              ),
              const SizedBox(height: 12),
              SegmentedButton<RepeatType>(
                segments: const [
                  ButtonSegment(
                    value: RepeatType.oneTime,
                    label: Text('No repeat'),
                    icon: Icon(Icons.today),
                  ),
                  ButtonSegment(
                    value: RepeatType.weekly,
                    label: Text('Weekly'),
                    icon: Icon(Icons.repeat),
                  ),
                ],
                selected: {_repeatType},
                onSelectionChanged: (selection) {
                  setState(() => _repeatType = selection.single);
                },
              ),
              const SizedBox(height: 12),
              _PreviewCard(preview: preview),
              if (!_canProduceFutureSchedule) ...[
                const SizedBox(height: 12),
                const _InlineWarning(
                  text: 'Choose a future wake target before saving.',
                ),
              ],
              if (overlaps.isNotEmpty) ...[
                const SizedBox(height: 12),
                _InlineWarning(text: _overlapWarningText(overlaps)),
              ],
              if (_scheduleWarning != null) ...[
                const SizedBox(height: 12),
                _InlineWarning(text: _scheduleWarning!),
              ],
              const SizedBox(height: 4),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _advancedExpanded,
                onExpansionChanged: (value) {
                  setState(() => _advancedExpanded = value);
                },
                title: const Text('Sound and vibration'),
                children: [
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_soundId),
                    initialValue: _soundId,
                    decoration: const InputDecoration(labelText: 'Sound'),
                    items: const [
                      DropdownMenuItem(
                        value: defaultWakePlanSoundId,
                        child: Text('Default sound'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _soundId = value);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vibration'),
                    value: _vibrationEnabled,
                    onChanged: (value) {
                      setState(() => _vibrationEnabled = value);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canSave ? _save : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.alarm_add),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_WakePlanOverlap> _findOverlaps() {
    final draftPlan = _buildWakePlan(createdAt: widget.now);
    final draftStart = draftPlan.startAt(widget.initialTarget.day);
    final draftEnd = draftPlan.targetAt(widget.initialTarget.day);
    final draftStartDay = CalendarDay.fromDateTime(draftStart);
    final draftEndDay = CalendarDay.fromDateTime(draftEnd);
    final overlaps = <_WakePlanOverlap>[];

    for (final existingPlan in widget.existingWakePlans) {
      if (existingPlan.id == widget.existingWakePlan?.id) {
        continue;
      }
      final lookbackDays =
          (existingPlan.startOffset.inMinutes / TimeOfDayMinutes.minutesPerDay)
              .ceil();
      final firstTargetDay = draftStartDay.addDays(-lookbackDays);
      final lastTargetDay = draftEndDay.addDays(lookbackDays + 1);

      for (
        var targetDay = firstTargetDay;
        targetDay.compareTo(lastTargetDay) <= 0;
        targetDay = targetDay.addDays(1)
      ) {
        if (!existingPlan.occursOn(targetDay)) {
          continue;
        }

        final existingStart = existingPlan.startAt(targetDay);
        final existingEnd = existingPlan.targetAt(targetDay);
        if (draftStart.isBefore(existingEnd) &&
            existingStart.isBefore(draftEnd)) {
          overlaps.add(
            _WakePlanOverlap(
              startAt: existingStart,
              endAt: existingEnd,
              wakePlan: existingPlan,
            ),
          );
        }
      }
    }

    return overlaps;
  }

  Future<void> _save() async {
    if (!_canProduceFutureSchedule || _saving) {
      return;
    }

    final now = _currentNow;
    setState(() {
      _saving = true;
      _scheduleWarning = null;
    });

    final plan = _buildWakePlan(createdAt: now);
    try {
      final result = await widget.onSave(plan);
      if (!mounted) {
        return;
      }
      if (result.isSuccess) {
        Navigator.pop(context, result);
        return;
      }
      setState(() {
        _saving = false;
        _scheduleWarning =
            result.warning?.message ?? 'Alarms could not be scheduled.';
      });
    } catch (error, stackTrace) {
      debugPrint('CreateWakePlanSheet save failed: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _scheduleWarning = 'Wake plan could not be saved.';
      });
    }
  }

  WakePlan _buildWakePlan({required DateTime createdAt}) {
    final repeatRule = _buildRepeatRule();
    final existingWakePlan = widget.existingWakePlan;

    return WakePlan(
      id: existingWakePlan?.id ?? _wakePlanId(createdAt),
      title: 'Wake $_targetTime',
      targetTime: _targetTime,
      startOffset: _startOffset,
      interval: _interval,
      repeatRule: repeatRule,
      isEnabled: existingWakePlan?.isEnabled ?? true,
      status: existingWakePlan?.status ?? WakePlanStatus.scheduled,
      skipNextDate: existingWakePlan?.skipNextDate,
      soundId: _soundId,
      vibrationEnabled: _vibrationEnabled,
      createdAt: existingWakePlan?.createdAt ?? createdAt,
      updatedAt: createdAt,
    );
  }

  RepeatRule _buildRepeatRule() {
    switch (_repeatType) {
      case RepeatType.oneTime:
        return RepeatRule.oneTime(_targetDay);
      case RepeatType.weekly:
        final existingRepeatRule = widget.existingWakePlan?.repeatRule;
        if (_initialRepeatType == RepeatType.weekly &&
            existingRepeatRule?.type == RepeatType.weekly) {
          return existingRepeatRule!;
        }
        return RepeatRule.weekly({
          Weekday.fromDateTimeValue(_targetDay.weekday),
        });
    }
  }

  Future<void> _pickTargetTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _targetTime.hour,
        minute: _targetTime.minute,
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _targetTime = TimeOfDayMinutes.fromHourMinute(
        hour: selected.hour,
        minute: selected.minute,
      );
    });
  }

  String _wakePlanId(DateTime createdAt) {
    return 'wake-${createdAt.microsecondsSinceEpoch}-${_targetAt.microsecondsSinceEpoch}';
  }
}

class _WakePlanOverlap {
  const _WakePlanOverlap({
    required this.startAt,
    required this.endAt,
    required this.wakePlan,
  });

  final DateTime startAt;
  final DateTime endAt;
  final WakePlan wakePlan;
}

class WakePlanCreatePreview {
  WakePlanCreatePreview({
    required this.targetAt,
    required this.startOffset,
    required this.interval,
    required this.now,
  }) : startAt = targetStartAt(targetAt: targetAt, startOffset: startOffset),
       totalOccurrenceCount = _occurrenceCount(startOffset, interval),
       remainingOccurrenceCount = _remainingCount(
         targetAt: targetAt,
         startOffset: startOffset,
         interval: interval,
         now: now,
       );

  final DateTime targetAt;
  final DateTime startAt;
  final Duration startOffset;
  final Duration interval;
  final DateTime now;
  final int totalOccurrenceCount;
  final int remainingOccurrenceCount;
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final WakePlanCreatePreview preview;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Preview', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Time span',
              value:
                  '${_timeLabel(preview.startAt)}-${_timeLabel(preview.targetAt)}',
            ),
            _InfoRow(
              label: 'Interval',
              value: '${preview.interval.inMinutes} min',
            ),
            _InfoRow(
              label: 'Total',
              value: '${preview.totalOccurrenceCount} alarms',
            ),
            _InfoRow(
              label: 'Remaining',
              value: '${preview.remainingOccurrenceCount} alarms',
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
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

class _EditableInfoRow extends StatelessWidget {
  const _EditableInfoRow({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _InfoRow(label: label, value: value),
        ),
        IconButton(
          tooltip: 'Change wake target time',
          onPressed: onPressed,
          icon: const Icon(Icons.schedule),
        ),
      ],
    );
  }
}

class _DurationMenu extends StatelessWidget {
  const _DurationMenu({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final Duration value;
  final List<Duration> values;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Duration>(
      key: ValueKey(value),
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final option in values)
          DropdownMenuItem(value: option, child: Text(_durationLabel(option))),
      ],
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
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

int _occurrenceCount(Duration startOffset, Duration interval) {
  final offsetMinutes = startOffset.inMinutes;
  final intervalMinutes = interval.inMinutes;
  return ((offsetMinutes + intervalMinutes - 1) ~/ intervalMinutes) + 1;
}

int _remainingCount({
  required DateTime targetAt,
  required Duration startOffset,
  required Duration interval,
  required DateTime now,
}) {
  final startAt = targetStartAt(targetAt: targetAt, startOffset: startOffset);
  var count = 0;
  for (
    var alarmAt = startAt;
    alarmAt.isBefore(targetAt);
    alarmAt = alarmAt.add(interval)
  ) {
    if (!alarmAt.isBefore(now)) {
      count += 1;
    }
  }
  if (!targetAt.isBefore(now)) {
    count += 1;
  }
  return count;
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

String _overlapWarningText(List<_WakePlanOverlap> overlaps) {
  if (overlaps.length == 1) {
    final overlap = overlaps.single;
    return 'Overlaps ${_timeLabel(overlap.startAt)}-'
        '${_timeLabel(overlap.endAt)}.';
  }
  return 'Overlaps ${overlaps.length} wake plans.';
}

String _dateTimeLabel(DateTime dateTime) {
  return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-'
      '${dateTime.day.toString().padLeft(2, '0')} ${_timeLabel(dateTime)}';
}

String _timeLabel(DateTime dateTime) {
  return '${dateTime.hour.toString().padLeft(2, '0')}:'
      '${dateTime.minute.toString().padLeft(2, '0')}';
}
