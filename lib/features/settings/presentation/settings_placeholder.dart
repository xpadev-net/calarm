import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wake_plan/domain/wake_plan_domain.dart';
import '../application/wake_plan_defaults_controller.dart';

class SettingsPlaceholder extends ConsumerWidget {
  const SettingsPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaults = ref.watch(wakePlanDefaultsProvider);

    return defaults.when(
      data: (settings) => _SettingsDefaultsPanel(settings: settings),
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
                  controller.setSoundId(value);
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibration'),
              value: settings.defaultVibrationEnabled,
              onChanged: controller.setVibrationEnabled,
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
                controller.setRepeatType(selection.single);
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
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Duration>(
      initialValue: values.contains(value) ? value : null,
      decoration: InputDecoration(labelText: label),
      hint: Text(_formatDuration(value)),
      items: [
        for (final option in values)
          DropdownMenuItem(value: option, child: Text(_formatDuration(option))),
      ],
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
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
