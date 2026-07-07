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
import '../../settings/application/wake_plan_defaults_controller.dart';
import '../../wake_plan/application/wake_plan_service.dart';
import '../../wake_plan/data/wake_plan_data.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../../wake_plan/ui/create_wake_plan_sheet.dart';
import '../week_calendar.dart';

final weekCalendarNativeAlarmGatewayProvider = Provider<NativeAlarmGateway>((
  ref,
) {
  return MethodChannelNativeAlarmGateway();
});

final weekCalendarClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

final weekCalendarRepositoryProvider = FutureProvider<WakePlanRepository>((
  ref,
) async {
  final config = ref.watch(appDatabaseConfigProvider);
  final database = WakePlanDatabase(await openWakePlanDatabase(config.name));
  ref.onDispose(database.close);
  return WakePlanRepository(database);
});

final weekCalendarWakePlanServiceProvider = FutureProvider<WakePlanService>((
  ref,
) async {
  return WakePlanService(
    repository: await ref.watch(weekCalendarRepositoryProvider.future),
    nativeAlarmGateway: ref.watch(weekCalendarNativeAlarmGatewayProvider),
  );
});

final weekCalendarWakePlansProvider = FutureProvider<List<WakePlan>>((
  ref,
) async {
  final now = ref.watch(weekCalendarClockProvider)();
  final repository = await ref.watch(weekCalendarRepositoryProvider.future);
  return repository.fetchWakePlans(now: now);
});

class WeekCalendarPlaceholder extends ConsumerStatefulWidget {
  const WeekCalendarPlaceholder({super.key});

  @override
  ConsumerState<WeekCalendarPlaceholder> createState() {
    return _WeekCalendarPlaceholderState();
  }
}

class _WeekCalendarPlaceholderState
    extends ConsumerState<WeekCalendarPlaceholder> {
  bool _sheetOpen = false;

  @override
  Widget build(BuildContext context) {
    final clock = ref.watch(weekCalendarClockProvider);
    final now = clock();
    final wakePlans = ref.watch(weekCalendarWakePlansProvider);
    final defaults = ref.watch(wakePlanDefaultsProvider);
    _logProviderError('Wake plans', wakePlans);
    _logProviderError('Wake plan defaults', defaults);
    final currentWakePlans = wakePlans.hasValue
        ? wakePlans.requireValue
        : const <WakePlan>[];
    final currentDefaults = defaults.hasValue
        ? defaults.requireValue
        : AppSettings.initial();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Week calendar', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        WeekCalendarView(
          now: now,
          wakePlans: currentWakePlans,
          height: 220,
          hourHeight: 44,
          onTargetTap: (target) {
            _openCreateSheet(
              context: context,
              ref: ref,
              now: clock(),
              target: target,
              defaults: currentDefaults,
              existingWakePlans: currentWakePlans,
            );
          },
        ),
        if (wakePlans.hasError || defaults.hasError) ...[
          const SizedBox(height: 8),
          Text(
            _loadErrorText(wakePlans: wakePlans, defaults: defaults),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Future<void> _openCreateSheet({
    required BuildContext context,
    required WidgetRef ref,
    required DateTime now,
    required WeekCalendarTapTarget target,
    required AppSettings defaults,
    required List<WakePlan> existingWakePlans,
  }) async {
    if (_sheetOpen) {
      return;
    }
    _sheetOpen = true;

    if (!target.dateTime.isAfter(now)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choose a future time.')));
      _sheetOpen = false;
      return;
    }

    try {
      final service = await ref.read(
        weekCalendarWakePlanServiceProvider.future,
      );
      if (!context.mounted) {
        return;
      }

      final result = await showModalBottomSheet<WakePlanSchedulingResult>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return CreateWakePlanSheet(
            initialTarget: target,
            now: now,
            defaults: defaults,
            existingWakePlans: existingWakePlans,
            onSave: (plan) async {
              final result = await service.createPlan(plan);
              ref.invalidate(weekCalendarWakePlansProvider);
              return result;
            },
          );
        },
      );

      if (!context.mounted || result == null) {
        return;
      }
      final message = result.isSuccess
          ? 'Wake plan scheduled.'
          : result.warning?.message ?? 'Alarms could not be scheduled.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      debugPrint('Could not open wake plan create sheet: $error');
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open wake plan editor.')),
      );
    } finally {
      _sheetOpen = false;
    }
  }
}

Future<QueryExecutor> openWakePlanDatabase(String name) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(
      File(p.join(directory.path, name)),
    );
  } on MissingPluginException catch (error) {
    debugPrint('Falling back to in-memory wake plan database: $error');
    return NativeDatabase.memory();
  }
}

void _logProviderError<T>(String label, AsyncValue<T> value) {
  if (!value.hasError) {
    return;
  }
  debugPrint('$label provider failed: ${value.error}');
}

String _loadErrorText({
  required AsyncValue<List<WakePlan>> wakePlans,
  required AsyncValue<AppSettings> defaults,
}) {
  if (wakePlans.hasError && defaults.hasError) {
    return 'Could not load wake plans or defaults.';
  }
  if (wakePlans.hasError) {
    return 'Could not load wake plans.';
  }
  return 'Could not load wake defaults.';
}
