import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/app_bootstrap.dart';
import '../../../core/platform/native_alarm_gateway.dart';
import '../../../core/time/time.dart';
import '../../settings/application/wake_plan_defaults_controller.dart';
import '../../settings/application/alarm_health_controller.dart';
import '../../wake_plan/application/wake_plan_service.dart';
import '../../wake_plan/data/wake_plan_data.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../../wake_plan/ui/inline_wake_plan_editor.dart';
import '../../wake_plan/ui/wake_plan_detail_sheet.dart';
import '../week_calendar.dart';

final weekCalendarNativeAlarmGatewayProvider = Provider<NativeAlarmGateway>((
  ref,
) {
  return ref.watch(appNativeAlarmGatewayProvider);
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
    extends ConsumerState<WeekCalendarPlaceholder>
    with WidgetsBindingObserver {
  static final _draftRandom = Random.secure();
  static const double _minHourHeight = 36;
  static const double _maxHourHeight = 92;

  bool _sheetOpen = false;
  double _hourHeight = 52;
  int _visibleDays = DateTime.daysPerWeek;
  WeekCalendarDraft? _draft;
  bool _savingDraft = false;
  bool _draftSubmissionAttempted = false;
  String? _draftError;
  WakePlan? _submittedDraftPlan;
  late DateTime _now;
  Timer? _minuteBoundaryTimer;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = ref.read(weekCalendarClockProvider)();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isActive =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _scheduleMinuteBoundaryRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isActive = true;
        _refreshNow();
        _scheduleMinuteBoundaryRefresh();
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _isActive = false;
        _cancelMinuteBoundaryRefresh();
        return;
    }
  }

  @override
  void dispose() {
    _cancelMinuteBoundaryRefresh();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock = ref.watch(weekCalendarClockProvider);
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
        SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Calendar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _CalendarControlButton(
                key: const ValueKey('week-calendar-three-day-button'),
                tooltip: 'Show 3 days',
                selected: _visibleDays == 3,
                label: '3',
                onPressed: _draft == null ? () => _setVisibleDays(3) : null,
              ),
              _CalendarControlButton(
                key: const ValueKey('week-calendar-seven-day-button'),
                tooltip: 'Show 7 days',
                selected: _visibleDays == DateTime.daysPerWeek,
                label: '7',
                onPressed: _draft == null
                    ? () => _setVisibleDays(DateTime.daysPerWeek)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => WeekCalendarView(
              key: ValueKey<int>(_visibleDays),
              now: _now,
              wakePlans: currentWakePlans,
              height: constraints.maxHeight,
              hourHeight: _hourHeight,
              visibleDays: _visibleDays,
              onHourHeightChanged: _setHourHeight,
              draft: _draft,
              onDraftChanged: (draft) {
                if (_draftSubmissionAttempted) {
                  return;
                }
                setState(() {
                  _draft = draft;
                  _draftError = null;
                });
              },
              draftInteractionEnabled:
                  !_savingDraft && !_draftSubmissionAttempted,
              onTargetTap: (target) {
                _createDraft(target: target, defaults: currentDefaults);
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
          ),
        ),
        if (_draft case final draft?)
          InlineWakePlanEditor(
            startAt: draft.startAt,
            endAt: draft.endAt,
            now: clock(),
            clock: clock,
            saving: _savingDraft,
            submissionAttempted: _draftSubmissionAttempted,
            error: _draftError,
            onSave: () => _saveDraft(
              context: context,
              clock: clock,
              defaults: currentDefaults,
            ),
            onCancel: _cancelDraft,
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

  void _refreshNow() {
    if (!mounted) {
      return;
    }
    final nextNow = ref.read(weekCalendarClockProvider)();
    if (nextNow == _now) {
      return;
    }
    setState(() {
      _now = nextNow;
    });
  }

  void _scheduleMinuteBoundaryRefresh() {
    _cancelMinuteBoundaryRefresh();
    if (!_isActive) {
      return;
    }
    final clock = ref.read(weekCalendarClockProvider);
    final current = clock();
    final nextMinute = DateTime(
      current.year,
      current.month,
      current.day,
      current.hour,
      current.minute + 1,
    );
    final delay = nextMinute.difference(current);
    late final Timer timer;
    timer = Timer(delay, () {
      if (!mounted || !_isActive || !identical(_minuteBoundaryTimer, timer)) {
        return;
      }
      _minuteBoundaryTimer = null;
      _refreshNow();
      _scheduleMinuteBoundaryRefresh();
    });
    _minuteBoundaryTimer = timer;
  }

  void _cancelMinuteBoundaryRefresh() {
    _minuteBoundaryTimer?.cancel();
    _minuteBoundaryTimer = null;
  }

  void _setHourHeight(double hourHeight) {
    final boundedHeight = hourHeight.clamp(_minHourHeight, _maxHourHeight);
    if (boundedHeight == _hourHeight) {
      return;
    }
    setState(() {
      _hourHeight = boundedHeight;
    });
  }

  void _setVisibleDays(int visibleDays) {
    if (_draft != null) {
      return;
    }
    if (_visibleDays == visibleDays) {
      return;
    }
    setState(() {
      _visibleDays = visibleDays;
    });
  }

  void _createDraft({
    required WeekCalendarTapTarget target,
    required AppSettings defaults,
  }) {
    if (_draft != null) {
      return;
    }
    final now = ref.read(weekCalendarClockProvider)();
    setState(() {
      _draft = weekCalendarDraftFromTap(
        id: _newDraftId(),
        target: target,
        defaultDuration: defaults.defaultStartOffset,
        createdAt: now,
      );
      _draftSubmissionAttempted = false;
      _draftError = null;
      _submittedDraftPlan = null;
    });
  }

  void _cancelDraft() {
    if (_savingDraft || _draftSubmissionAttempted) {
      return;
    }
    setState(() {
      _draft = null;
      _draftError = null;
      _submittedDraftPlan = null;
    });
  }

  Future<void> _saveDraft({
    required BuildContext context,
    required DateTime Function() clock,
    required AppSettings defaults,
  }) async {
    final draft = _draft;
    if (draft == null || _savingDraft || !draft.endAt.isAfter(clock())) {
      return;
    }
    final plan =
        _submittedDraftPlan ??
        _wakePlanFromDraft(draft: draft, defaults: defaults);
    setState(() {
      _savingDraft = true;
      _draftSubmissionAttempted = true;
      _draftError = null;
      _submittedDraftPlan = plan;
    });
    try {
      final service = await ref.read(
        weekCalendarWakePlanServiceProvider.future,
      );
      final result = await service.createPlan(plan);
      if (!mounted || _draft?.id != draft.id) {
        return;
      }
      ref.invalidate(weekCalendarWakePlansProvider);
      if (result.isSuccess) {
        setState(() {
          _draft = null;
          _savingDraft = false;
          _draftSubmissionAttempted = false;
          _submittedDraftPlan = null;
        });
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Wake plan scheduled.')));
        }
        return;
      }
      if (_isAlarmReadinessFailure(result)) {
        unawaited(ref.read(alarmHealthProvider.notifier).refresh());
      }
      setState(() {
        _savingDraft = false;
        _draftError =
            result.warning?.message ?? 'Alarms could not be scheduled.';
      });
    } catch (error, stackTrace) {
      debugPrint('Inline wake plan save failed: $error\n$stackTrace');
      if (!mounted || _draft?.id != draft.id) {
        return;
      }
      ref.invalidate(weekCalendarWakePlansProvider);
      ref.invalidate(weekCalendarWakePlanServiceProvider);
      setState(() {
        _savingDraft = false;
        _draftError = 'Wake plan could not be saved.';
      });
    }
  }

  WakePlan _wakePlanFromDraft({
    required WeekCalendarDraft draft,
    required AppSettings defaults,
  }) {
    final targetDay = CalendarDay.fromDateTime(draft.endAt);
    final targetTime = TimeOfDayMinutes.fromHourMinute(
      hour: draft.endAt.hour,
      minute: draft.endAt.minute,
    );
    return WakePlan(
      id: draft.id,
      title: 'Wake $targetTime',
      targetTime: targetTime,
      startOffset: draft.duration,
      interval: defaults.defaultInterval,
      repeatRule: defaults.repeatRuleForDate(targetDay),
      isEnabled: true,
      status: WakePlanStatus.scheduled,
      soundId: defaults.defaultSoundId,
      vibrationEnabled: defaults.defaultVibrationEnabled,
      createdAt: draft.createdAt,
      updatedAt: draft.createdAt,
    );
  }

  String _newDraftId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final entropy = List.generate(
      3,
      (_) => _draftRandom.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
    ).join();
    return 'wake-plan-$timestamp-$entropy';
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
            loadOccurrences: service.fetchOccurrencesForPlan,
            onSetOccurrenceEnabled: service.setOccurrenceEnabled,
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

bool _isAlarmReadinessFailure(WakePlanSchedulingResult result) {
  final reasons = result.warning?.scheduleFailureReasons ?? const {};
  return reasons.contains(ScheduleFailureReason.permissionMissing) ||
      reasons.contains(ScheduleFailureReason.osConstraint);
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

class _CalendarControlButton extends StatelessWidget {
  const _CalendarControlButton({
    super.key,
    required this.tooltip,
    required this.selected,
    required this.label,
    required this.onPressed,
  });

  final String tooltip;
  final bool selected;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        isSelected: selected,
        onPressed: onPressed,
        icon: Text(label),
        selectedIcon: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 28,
            child: Center(child: Text(label)),
          ),
        ),
      ),
    );
  }
}
