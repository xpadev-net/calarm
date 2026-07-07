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
    this.clock,
  });

  final WeekCalendarTapTarget initialTarget;
  final DateTime now;
  final AppSettings defaults;
  final List<WakePlan> existingWakePlans;
  final CreateWakePlanSave onSave;
  final DateTime Function()? clock;

  @override
  State<CreateWakePlanSheet> createState() => _CreateWakePlanSheetState();
}

class _CreateWakePlanSheetState extends State<CreateWakePlanSheet> {
  late Duration _startOffset;
  late Duration _interval;
  late RepeatType _repeatType;
  late String _soundId;
  late bool _vibrationEnabled;
  bool _saving = false;
  bool _advancedExpanded = false;
  String? _scheduleWarning;

  DateTime get _targetAt => widget.initialTarget.dateTime;

  DateTime get _currentNow => widget.clock?.call() ?? DateTime.now();

  bool get _isPastTarget => !_targetAt.isAfter(_currentNow);

  @override
  void initState() {
    super.initState();
    _startOffset = widget.defaults.defaultStartOffset;
    _interval = widget.defaults.defaultInterval;
    _repeatType = widget.defaults.defaultRepeatType;
    _soundId = widget.defaults.defaultSoundId;
    _vibrationEnabled = widget.defaults.defaultVibrationEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final preview = WakePlanCreatePreview(
      targetAt: _targetAt,
      startOffset: _startOffset,
      interval: _interval,
      now: widget.now,
    );
    final overlap = _findOverlap();
    final canSave = !_saving && !_isPastTarget;

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
                      'Create wake plan',
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
              _InfoRow(label: 'Wake target', value: _dateTimeLabel(_targetAt)),
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
              if (_isPastTarget) ...[
                const SizedBox(height: 12),
                const _InlineWarning(
                  text: 'Choose a future wake target before saving.',
                ),
              ],
              if (overlap != null) ...[
                const SizedBox(height: 12),
                _InlineWarning(
                  text:
                      'Overlaps ${_timeLabel(overlap.startAt)}-'
                      '${_timeLabel(overlap.endAt)}.',
                ),
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

  WeekCalendarWakePlanBlock? _findOverlap() {
    final draftPlan = _buildWakePlan(createdAt: widget.now);
    final draftStart = draftPlan.startAt(widget.initialTarget.day);
    final draftEnd = draftPlan.targetAt(widget.initialTarget.day);
    final blocks = weekCalendarWakePlanBlocks(
      week: visibleWeekRange(_targetAt),
      wakePlans: widget.existingWakePlans,
    );

    for (final block in blocks) {
      if (draftStart.isBefore(block.endAt) &&
          block.startAt.isBefore(draftEnd)) {
        return block;
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_isPastTarget || _saving) {
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
    } catch (error) {
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
    final day = widget.initialTarget.day;
    final repeatRule = switch (_repeatType) {
      RepeatType.oneTime => RepeatRule.oneTime(day),
      RepeatType.weekly => RepeatRule.weekly({
        Weekday.fromDateTimeValue(day.weekday),
      }),
    };

    return WakePlan(
      id: _wakePlanId(createdAt),
      title: 'Wake ${widget.initialTarget.time}',
      targetTime: widget.initialTarget.time,
      startOffset: _startOffset,
      interval: _interval,
      repeatRule: repeatRule,
      isEnabled: true,
      status: WakePlanStatus.scheduled,
      soundId: _soundId,
      vibrationEnabled: _vibrationEnabled,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  String _wakePlanId(DateTime createdAt) {
    return 'wake-${createdAt.microsecondsSinceEpoch}-${_targetAt.microsecondsSinceEpoch}';
  }
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

String _dateTimeLabel(DateTime dateTime) {
  return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-'
      '${dateTime.day.toString().padLeft(2, '0')} ${_timeLabel(dateTime)}';
}

String _timeLabel(DateTime dateTime) {
  return '${dateTime.hour.toString().padLeft(2, '0')}:'
      '${dateTime.minute.toString().padLeft(2, '0')}';
}
