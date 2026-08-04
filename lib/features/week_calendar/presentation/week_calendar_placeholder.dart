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
import '../../wake_plan/application/wake_plan_service_providers.dart';
import '../../wake_plan/data/wake_plan_data.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../../wake_plan/ui/inline_wake_plan_editor.dart';
import '../../wake_plan/ui/wake_plan_detail_sheet.dart';
import '../week_calendar.dart';

final weekCalendarNativeAlarmGatewayProvider = appNativeAlarmGatewayProvider;

final weekCalendarClockProvider = wakePlanClockProvider;

final weekCalendarRepositoryProvider = appWakePlanRepositoryProvider;

final weekCalendarWakePlanServiceProvider = wakePlanServiceProvider;

final weekCalendarWakePlansProvider = FutureProvider<List<WakePlan>>((
  ref,
) async {
  final now = ref.watch(weekCalendarClockProvider)();
  final repository = await ref.watch(weekCalendarRepositoryProvider.future);
  return repository.fetchWakePlans(now: now);
});

class WeekCalendarPlaceholder extends ConsumerStatefulWidget {
  const WeekCalendarPlaceholder({
    super.key,
    required this.visibleDays,
    this.onDraftActiveChanged,
    this.bottomPadding = 0,
  });

  final int visibleDays;

  /// Notified whenever an inline wake-plan draft starts or stops being
  /// active, so a caller-owned view switcher can disable itself while the
  /// draft is in progress the way the header switcher used to.
  final ValueChanged<bool>? onDraftActiveChanged;

  /// Extra scrollable space reserved at the bottom of the calendar's day
  /// grid, so the last hour row can still be scrolled clear of a system bar
  /// the calendar is otherwise drawn behind (edge-to-edge layout).
  final double bottomPadding;

  @override
  ConsumerState<WeekCalendarPlaceholder> createState() {
    return _WeekCalendarPlaceholderState();
  }
}

class _WeekCalendarPlaceholderState
    extends ConsumerState<WeekCalendarPlaceholder>
    with WidgetsBindingObserver {
  static final _draftRandom = Random.secure();
  static const double _minHourHeight = weekCalendarMinHourHeight;
  static const double _maxHourHeight = weekCalendarMaxHourHeight;

  bool _sheetOpen = false;
  double _hourHeight = 52;
  WeekCalendarDraft? _draft;
  bool _savingDraft = false;
  bool _draftSubmissionAttempted = false;
  String? _draftError;
  WakePlan? _submittedDraftPlan;
  late DateTime _now;
  Timer? _minuteBoundaryTimer;
  bool _isActive = false;
  bool _enteredBackground = false;
  int _recenterRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = ref.read(weekCalendarClockProvider)();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isActive =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _enteredBackground =
        lifecycleState == AppLifecycleState.hidden ||
        lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.detached;
    _scheduleMinuteBoundaryRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final shouldRecenter = _enteredBackground;
        _isActive = true;
        _enteredBackground = false;
        _refreshNow(recenter: shouldRecenter);
        _scheduleMinuteBoundaryRefresh();
        return;
      case AppLifecycleState.inactive:
        _isActive = false;
        _cancelMinuteBoundaryRefresh();
        return;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _isActive = false;
        _enteredBackground = true;
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
    final onDraftActiveChanged = widget.onDraftActiveChanged;
    if (onDraftActiveChanged != null) {
      final draftActive = _draft != null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          onDraftActiveChanged(draftActive);
        }
      });
    }
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
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => WeekCalendarView(
              key: ValueKey<int>(widget.visibleDays),
              now: _now,
              wakePlans: currentWakePlans,
              height: constraints.maxHeight,
              hourHeight: _hourHeight,
              visibleDays: widget.visibleDays,
              bottomPadding: widget.bottomPadding,
              draftDuration: currentDefaults.defaultStartOffset,
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
              recenterRequest: _recenterRequest,
              onTargetTap: (target, week) {
                _createDraft(
                  target: target,
                  week: week,
                  defaults: currentDefaults,
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
            onRangeChanged: _editDraftRange,
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

  void _refreshNow({bool recenter = false}) {
    if (!mounted) {
      return;
    }
    final nextNow = ref.read(weekCalendarClockProvider)();
    if (nextNow == _now && !recenter) {
      return;
    }
    setState(() {
      _now = nextNow;
      if (recenter) {
        _recenterRequest += 1;
      }
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

  void _createDraft({
    required WeekCalendarTapTarget target,
    required WeekRange week,
    required AppSettings defaults,
  }) {
    if (_draft != null) {
      return;
    }
    final now = ref.read(weekCalendarClockProvider)();
    // Capped to the tapped page's visible range: a duration that crossed
    // into a day beyond it would have no adjacent page built to render its
    // continuation on, so it'd be an invisible, unverifiable commitment.
    final cappedDuration = weekCalendarClampDraftDurationToWeek(
      startAt: target.dateTime,
      duration: defaults.defaultStartOffset,
      week: week,
    );
    setState(() {
      _draft = weekCalendarDraftFromTap(
        id: _newDraftId(),
        target: target,
        defaultDuration: cappedDuration,
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

  InlineWakePlanRangeChange _editDraftRange(DateTime startAt, DateTime endAt) {
    final draft = _draft;
    if (draft == null || _savingDraft || _draftSubmissionAttempted) {
      return const InlineWakePlanRangeChange.rejected(
        'The range cannot be changed after submission.',
      );
    }

    final edit = editWeekCalendarDraftRange(
      draft: draft,
      startAt: startAt,
      endAt: endAt,
    );
    final error = edit.error;
    if (error != null) {
      final guidance = switch (error) {
        WeekCalendarDraftRangeError.notOrdered => 'Start must be before end.',
        WeekCalendarDraftRangeError.tooShort =>
          'Choose a range of at least 5 minutes.',
        WeekCalendarDraftRangeError.tooLong =>
          'Choose a range no longer than 3 hours.',
      };
      return InlineWakePlanRangeChange.rejected(guidance);
    }

    final nextDraft = edit.draft!;
    setState(() {
      _draft = nextDraft;
      _draftError = null;
    });
    return InlineWakePlanRangeChange.accepted(
      startAt: nextDraft.startAt,
      endAt: nextDraft.endAt,
    );
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
