import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wake_plan/domain/wake_plan_domain.dart';
import '../application/alarm_health_controller.dart';
import '../application/wake_plan_defaults_controller.dart';

class SettingsPlaceholder extends ConsumerWidget {
  const SettingsPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaults = ref.watch(wakePlanDefaultsProvider);
    final health = ref.watch(alarmHealthProvider);

    return defaults.when(
      data: (settings) => _SettingsPanel(settings: settings, health: health),
      error: (error, stackTrace) => _SettingsStatusTile(
        title: 'Settings',
        subtitle: 'Defaults could not be loaded.',
        icon: Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      loading: () => const _SettingsStatusTile(
        title: 'Settings',
        subtitle: 'Loading defaults...',
        icon: Icons.tune,
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.settings, required this.health});

  final AppSettings settings;
  final AsyncValue<AlarmHealthState> health;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420.0;
        return SizedBox(
          height: maxHeight,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AlarmHealthPanel(settings: settings, health: health),
                const SizedBox(height: 12),
                _SettingsDefaultsPanel(settings: settings),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AlarmHealthPanel extends ConsumerWidget {
  const _AlarmHealthPanel({required this.settings, required this.health});

  final AppSettings settings;
  final AsyncValue<AlarmHealthState> health;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final healthState = health.value;
    final warnings = healthState?.warnings ?? const <AlarmHealthWarning>[];
    final testAlarmMessage = healthState?.testAlarmMessage;
    final isScheduling = healthState?.isSchedulingTestAlarm ?? false;
    final isRefreshing = healthState?.isRefreshing ?? false;
    final isRequestingPermission = healthState?.isRequestingPermission ?? false;
    final isBusy = healthState?.isBusy ?? health.isLoading;
    final canRequestPermission =
        healthState?.capability.canRequestPermission ?? false;
    final supportsTestAlarm =
        healthState?.capability.supportsTestAlarm ?? false;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Alarm readiness',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (health.isLoading && healthState == null)
              const _SettingsStatusRow(
                icon: Icons.hourglass_empty,
                text: 'Checking alarm permissions...',
              )
            else if (health.hasError ||
                healthState?.capabilityCheckFailed == true)
              _SettingsStatusRow(
                icon: Icons.error_outline,
                text: 'Could not check alarm readiness.',
                color: colorScheme.error,
              )
            else if (warnings.isEmpty)
              const _SettingsStatusRow(
                icon: Icons.check_circle_outline,
                text: 'Alarms are ready to schedule.',
              )
            else
              _InlineWarning(
                text: warnings.map((warning) => warning.message).join('\n'),
              ),
            if (testAlarmMessage != null) ...[
              const SizedBox(height: 8),
              _InlineWarning(
                text: testAlarmMessage,
                isError: healthState?.hasFailedTestAlarm ?? false,
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: healthState == null || isBusy || !supportsTestAlarm
                      ? null
                      : () {
                          _handleSave(
                            context,
                            ref
                                .read(alarmHealthProvider.notifier)
                                .scheduleTestAlarm(settings),
                            failureMessage:
                                'Could not schedule the test alarm.',
                          );
                        },
                  icon: isScheduling
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.alarm_add),
                  label: Text(
                    isScheduling
                        ? 'Scheduling test alarm'
                        : 'Schedule 1-minute test alarm',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: health.isLoading || isBusy
                      ? null
                      : () {
                          _handleSave(
                            context,
                            ref.read(alarmHealthProvider.notifier).refresh(),
                            failureMessage: 'Could not check alarm readiness.',
                          );
                        },
                  icon: isRefreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(isRefreshing ? 'Checking' : 'Check again'),
                ),
                if (canRequestPermission)
                  OutlinedButton.icon(
                    onPressed: isBusy
                        ? null
                        : () {
                            _handleSave(
                              context,
                              ref
                                  .read(alarmHealthProvider.notifier)
                                  .requestPermission(),
                              failureMessage: 'Could not open alarm settings.',
                            );
                          },
                    icon: isRequestingPermission
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.settings),
                    label: Text(
                      isRequestingPermission
                          ? 'Opening settings'
                          : 'Open alarm settings',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDefaultsPanel extends ConsumerWidget {
  const _SettingsDefaultsPanel({required this.settings});

  static const _wakeWindowOptions = [
    Duration(minutes: 30),
    defaultWakePlanStartOffset,
    Duration(minutes: 90),
    Duration(minutes: 120),
    maximumWakePlanStartOffset,
  ];
  static const _intervalOptions = [
    minimumWakePlanInterval,
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(wakePlanDefaultsProvider.notifier);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _DurationChoice(
              label: 'Wake window',
              value: settings.defaultStartOffset,
              values: _wakeWindowOptions,
              onChanged: controller.setWakeWindow,
            ),
            const SizedBox(height: 12),
            _DurationChoice(
              label: 'Interval',
              value: settings.defaultInterval,
              values: _intervalOptions,
              onChanged: controller.setInterval,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(settings.defaultSoundId),
              initialValue: settings.defaultSoundId,
              decoration: const InputDecoration(labelText: 'Sound'),
              items: const [
                DropdownMenuItem(
                  value: defaultWakePlanSoundId,
                  child: Text('OS default'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _handleSave(context, controller.setSoundId(value));
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibration'),
              value: settings.defaultVibrationEnabled,
              onChanged: (value) {
                _handleSave(context, controller.setVibrationEnabled(value));
              },
            ),
            const SizedBox(height: 4),
            SegmentedButton<RepeatType>(
              segments: const [
                ButtonSegment(
                  value: RepeatType.oneTime,
                  label: Text('No repeat'),
                  icon: Icon(Icons.event),
                ),
                ButtonSegment(
                  value: RepeatType.weekly,
                  label: Text('Weekday'),
                  icon: Icon(Icons.repeat),
                ),
              ],
              selected: {settings.defaultRepeatType},
              onSelectionChanged: (selection) {
                _handleSave(
                  context,
                  controller.setRepeatType(selection.single),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationChoice extends StatelessWidget {
  const _DurationChoice({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final Duration value;
  final List<Duration> values;
  final Future<void> Function(Duration) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Duration>(
      key: ValueKey(value),
      initialValue: values.contains(value) ? value : null,
      decoration: InputDecoration(labelText: label),
      hint: Text(_formatDuration(value)),
      items: [
        for (final option in values)
          DropdownMenuItem(value: option, child: Text(_formatDuration(option))),
      ],
      onChanged: (value) {
        if (value != null) {
          _handleSave(context, onChanged(value));
        }
      },
    );
  }
}

class _SettingsStatusTile extends StatelessWidget {
  const _SettingsStatusTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

class _SettingsStatusRow extends StatelessWidget {
  const _SettingsStatusRow({
    required this.icon,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.text, this.isError = true});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isError
        ? colorScheme.errorContainer
        : colorScheme.secondaryContainer;
    final foregroundColor = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.warning_amber : Icons.check_circle_outline,
              color: foregroundColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(color: foregroundColor)),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes;
  if (minutes < 60) {
    return '$minutes min';
  }
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (remainder == 0) {
    return '$hours h';
  }

  return '$hours h $remainder min';
}

void _handleSave(
  BuildContext context,
  Future<void> save, {
  String failureMessage = 'Could not save settings.',
}) {
  unawaited(_showSaveFailure(context, save, failureMessage));
}

Future<void> _showSaveFailure(
  BuildContext context,
  Future<void> save,
  String failureMessage,
) async {
  try {
    await save;
  } on Object {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failureMessage)));
  }
}
