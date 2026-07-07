import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/bootstrap/app_bootstrap.dart';
import '../../../core/platform/method_channel_native_alarm_gateway.dart';
import '../../../core/platform/native_alarm_gateway.dart';
import '../../../core/time/time.dart';
import '../../wake_plan/data/wake_plan_data.dart';
import '../application/alarm_ringing_controller.dart';

final alarmRingingClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

final alarmRingingNativeAlarmGatewayProvider = Provider<NativeAlarmGateway>((
  ref,
) {
  return MethodChannelNativeAlarmGateway();
});

final alarmRingingRepositoryProvider = FutureProvider<WakePlanRepository>((
  ref,
) async {
  final config = ref.watch(appDatabaseConfigProvider);
  final database = WakePlanDatabase(
    await openAlarmRingingDatabase(config.name),
  );
  ref.onDispose(database.close);
  return WakePlanRepository(database);
});

final alarmRingingControllerProvider = FutureProvider<AlarmRingingController>((
  ref,
) async {
  return AlarmRingingController(
    store: AlarmRingingRepositoryStore(
      await ref.watch(alarmRingingRepositoryProvider.future),
    ),
    nativeAlarmGateway: ref.watch(alarmRingingNativeAlarmGatewayProvider),
    clock: ref.watch(alarmRingingClockProvider),
  );
});

final alarmRingingSnapshotProvider = FutureProvider<AlarmRingingSnapshot?>((
  ref,
) async {
  final controller = await ref.watch(alarmRingingControllerProvider.future);
  return controller.loadCurrentRinging();
});

class AlarmRingingPlaceholder extends ConsumerWidget {
  const AlarmRingingPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(alarmRingingSnapshotProvider);
    return snapshot.when(
      data: (snapshot) {
        if (snapshot == null) {
          return const AlarmRingingEmptyState();
        }
        return AlarmRingingScreen(
          snapshot: snapshot,
          now: ref.watch(alarmRingingClockProvider)(),
          onStop: () async {
            final controller = await ref.read(
              alarmRingingControllerProvider.future,
            );
            final result = await controller.dismissCurrent(
              snapshot.currentOccurrence.id,
            );
            ref.invalidate(alarmRingingSnapshotProvider);
            return result;
          },
        );
      },
      loading: () => const _FeatureTile(
        title: 'Alarm ringing',
        subtitle: 'Checking active alarms...',
      ),
      error: (error, stackTrace) {
        debugPrint('Alarm ringing provider failed: $error');
        return const _FeatureTile(
          title: 'Alarm ringing',
          subtitle: 'Could not load active alarm state.',
        );
      },
    );
  }
}

class AlarmRingingEmptyState extends StatelessWidget {
  const AlarmRingingEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FeatureTile(
      title: 'Alarm ringing',
      subtitle: 'No alarm is ringing.',
    );
  }
}

class AlarmRingingScreen extends StatefulWidget {
  const AlarmRingingScreen({
    required this.snapshot,
    required this.now,
    required this.onStop,
    super.key,
  });

  final AlarmRingingSnapshot snapshot;
  final DateTime now;
  final Future<AlarmDismissResult> Function() onStop;

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen> {
  bool _stopping = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final snapshot = widget.snapshot;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Alarm ringing',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _RingingMetric(
              label: 'Current time',
              value: _formatDateTime(widget.now),
            ),
            _RingingMetric(
              label: 'Wake target',
              value: _formatTime(snapshot.wakePlan.targetTime),
            ),
            _RingingMetric(
              label: 'Alarm',
              value:
                  '${snapshot.occurrenceIndex} of ${snapshot.occurrenceCount}',
            ),
            _RingingMetric(
              label: 'Next scheduled',
              value: snapshot.nextScheduledAt == null
                  ? 'None'
                  : _formatDateMinute(snapshot.nextScheduledAt!),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _stopping ? null : _stopCurrentAlarm,
              icon: _stopping
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop),
              label: const Text('Stop current alarm'),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(_errorText!, style: TextStyle(color: colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _stopCurrentAlarm() async {
    setState(() {
      _stopping = true;
      _errorText = null;
    });

    final result = await widget.onStop();
    if (!mounted) {
      return;
    }

    switch (result) {
      case AlarmDismissResult.dismissed:
      case AlarmDismissResult.alreadyDismissed:
        setState(() {
          _stopping = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Current alarm stopped.')));
      case AlarmDismissResult.notFound:
        setState(() {
          _errorText = 'Could not find the current alarm.';
          _stopping = false;
        });
      case AlarmDismissResult.notRinging:
        setState(() {
          _errorText = 'This alarm is no longer ringing.';
          _stopping = false;
        });
      case AlarmDismissResult.nativeCancelFailed:
        setState(() {
          _errorText = 'Could not stop the native alarm. Try again.';
          _stopping = false;
        });
    }
  }
}

class _RingingMetric extends StatelessWidget {
  const _RingingMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

Future<QueryExecutor> openAlarmRingingDatabase(String name) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(
      File(p.join(directory.path, name)),
    );
  } on MissingPluginException catch (error) {
    debugPrint('Falling back to in-memory alarm ringing database: $error');
    return NativeDatabase.memory();
  }
}

String _formatDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day ${_formatClock(value.hour, value.minute)}';
}

String _formatDateMinute(DateMinute value) {
  final dateTime = value.toDateTime();
  return _formatDateTime(dateTime);
}

String _formatTime(TimeOfDayMinutes value) {
  final hour = value.minutesSinceMidnight ~/ TimeOfDayMinutes.minutesPerHour;
  final minute = value.minutesSinceMidnight % TimeOfDayMinutes.minutesPerHour;
  return _formatClock(hour, minute);
}

String _formatClock(int hour, int minute) {
  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}
