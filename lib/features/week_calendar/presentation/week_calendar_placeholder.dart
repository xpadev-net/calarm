import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/method_channel_native_alarm_gateway.dart';
import '../../../core/platform/native_alarm_gateway.dart';
import '../../settings/application/wake_plan_defaults_controller.dart';
import '../../wake_plan/application/wake_plan_service.dart';
import '../../wake_plan/data/wake_plan_data.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../../wake_plan/ui/create_wake_plan_sheet.dart';
import '../../wake_plan/ui/wake_plan_detail_sheet.dart';
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
  return ref.watch(appWakePlanRepositoryProvider.future);
});

final weekCalendarWakePlanServiceProvider = FutureProvider<WakePlanService>((
  ref,
) async {
  return WakePlanService(
    repository: await ref.watch(weekCalendarRepositoryProvider.future),
    nativeAlarmGateway: ref.watch(weekCalendarNativeAlarmGatewayProvider),
    clock: ref.watch(weekCalendarClockProvider),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420.0;
        final errorHeight = wakePlans.hasError || defaults.hasError
            ? 32.0
            : 0.0;
        final calendarHeight = (availableHeight - 32.0 - errorHeight).clamp(
          120.0,
          720.0,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Week calendar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            WeekCalendarView(
              now: now,
              wakePlans: currentWakePlans,
              height: calendarHeight,
              hourHeight: 52,
              onTargetTap: (target) {
                _openCreateSheet(
                  context: context,
                  ref: ref,
                  clock: clock,
                  now: clock(),
                  target: target,
                  defaults: currentDefaults,
                  existingWakePlans: currentWakePlans,
                );
              },
              onWakePlanTap: (target) {
                _openDetailSheet(
                  context: context,
                  ref: ref,
                  clock: clock,
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
      },
    );
  }

  Future<void> _openCreateSheet({
    required BuildContext context,
    required WidgetRef ref,
    required DateTime Function() clock,
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
            clock: clock,
            defaults: defaults,
            existingWakePlans: existingWakePlans,
            onSave: (plan) async {
              try {
                return await service.createPlan(plan);
              } finally {
                if (mounted) {
                  ref.invalidate(weekCalendarWakePlansProvider);
                }
              }
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

  Future<void> _openDetailSheet({
    required BuildContext context,
    required WidgetRef ref,
    required DateTime Function() clock,
    required DateTime now,
    required WeekCalendarWakePlanTapTarget target,
    required AppSettings defaults,
    required List<WakePlan> existingWakePlans,
  }) async {
    if (_sheetOpen) {
      return;
    }
    _sheetOpen = true;

    try {
      final service = await ref.read(
        weekCalendarWakePlanServiceProvider.future,
      );
      if (!context.mounted) {
        return;
      }

      var action = _WakePlanDetailAction.edit;
      final result = await showModalBottomSheet<WakePlanSchedulingResult>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return WakePlanDetailSheet(
            target: target,
            now: now,
            clock: clock,
            defaults: defaults,
            existingWakePlans: existingWakePlans,
            onEdit: (plan) async {
              action = _WakePlanDetailAction.edit;
              final result = await service.editPlan(plan);
              ref.invalidate(weekCalendarWakePlansProvider);
              return result;
            },
            onDelete: (id) async {
              action = _WakePlanDetailAction.delete;
              final result = await service.deletePlan(id);
              ref.invalidate(weekCalendarWakePlansProvider);
              return result;
            },
            onSkipNext: (plan) async {
              action = _WakePlanDetailAction.skipNext;
              final result = await service.skipNextOccurrence(plan);
              ref.invalidate(weekCalendarWakePlansProvider);
              return result;
            },
            onUndoSkipNext: (plan) async {
              action = _WakePlanDetailAction.undoSkipNext;
              final result = await service.undoSkipNextOccurrence(plan);
              ref.invalidate(weekCalendarWakePlansProvider);
              return result;
            },
          );
        },
      );

      if (!context.mounted || result == null) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _detailResultMessage(result: result, now: now, action: action),
          ),
        ),
      );
    } catch (error) {
      debugPrint('Could not open wake plan detail: $error');
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open wake plan detail.')),
      );
    } finally {
      _sheetOpen = false;
    }
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

String _detailResultMessage({
  required WakePlanSchedulingResult result,
  required DateTime now,
  required _WakePlanDetailAction action,
}) {
  if (!result.isSuccess) {
    return result.warning?.message ??
        switch (action) {
          _WakePlanDetailAction.edit => 'Wake plan could not be updated.',
          _WakePlanDetailAction.delete => 'Wake plan could not be deleted.',
          _WakePlanDetailAction.skipNext => 'Wake plan could not be updated.',
          _WakePlanDetailAction.undoSkipNext =>
            'Wake plan could not be updated.',
        };
  }
  if (result.status == WakePlanSchedulingStatus.deleted) {
    return 'Wake plan deleted.';
  }
  if (action == _WakePlanDetailAction.skipNext) {
    return 'Next wake target skipped.';
  }
  if (action == _WakePlanDetailAction.undoSkipNext) {
    return 'Next wake target restored.';
  }
  final nextFire = wakePlanResultNextFireLabel(result: result, now: now);
  if (nextFire == null) {
    return 'Wake plan updated.';
  }
  return 'Wake plan updated. Next alarm: $nextFire';
}

enum _WakePlanDetailAction { edit, delete, skipNext, undoSkipNext }
