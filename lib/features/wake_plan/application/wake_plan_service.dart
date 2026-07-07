import '../../../core/platform/native_alarm_gateway.dart';
import '../../../core/time/time.dart';
import '../data/wake_plan_data.dart';
import '../domain/wake_plan_domain.dart';
import 'occurrence_planner.dart';

typedef WakePlanClock = DateTime Function();

class WakePlanService {
  WakePlanService({
    required WakePlanRepository repository,
    required NativeAlarmGateway nativeAlarmGateway,
    OccurrencePlanner occurrencePlanner = const OccurrencePlanner(),
    WakePlanClock? clock,
    int rollingScheduleDays = 7,
  }) : this.withStore(
         store: WakePlanRepositoryServiceStore(repository),
         nativeAlarmGateway: nativeAlarmGateway,
         occurrencePlanner: occurrencePlanner,
         clock: clock,
         rollingScheduleDays: rollingScheduleDays,
       );

  WakePlanService.withStore({
    required WakePlanServiceStore store,
    required NativeAlarmGateway nativeAlarmGateway,
    OccurrencePlanner occurrencePlanner = const OccurrencePlanner(),
    WakePlanClock? clock,
    int rollingScheduleDays = 7,
  }) : this._(
         store: store,
         nativeAlarmGateway: nativeAlarmGateway,
         occurrencePlanner: occurrencePlanner,
         clock: clock ?? DateTime.now,
         rollingScheduleDays: rollingScheduleDays,
       );

  WakePlanService._({
    required this._store,
    required this._nativeAlarmGateway,
    required this._occurrencePlanner,
    required this._clock,
    required int rollingScheduleDays,
  }) : _rollingScheduleDays = rollingScheduleDays {
    if (rollingScheduleDays <= 0) {
      throw ArgumentError.value(
        rollingScheduleDays,
        'rollingScheduleDays',
        'must be positive',
      );
    }
  }

  final WakePlanServiceStore _store;
  final NativeAlarmGateway _nativeAlarmGateway;
  final OccurrencePlanner _occurrencePlanner;
  final WakePlanClock _clock;
  final int _rollingScheduleDays;

  Future<WakePlanSchedulingResult> createPlan(WakePlan plan) async {
    final now = _clock();
    final persistedPlan = plan.copyWith(updatedAt: now);
    await _store.saveWakePlan(persistedPlan);

    return _generateAndSchedule(
      plan: persistedPlan,
      now: now,
      changeState: WakePlanChangeState.committed,
    );
  }

  Future<WakePlanSchedulingResult> editPlan(WakePlan plan) async {
    final now = _clock();
    final previousPlan = await _store.fetchWakePlan(plan.id);
    final pendingPlan = plan.copyWith(updatedAt: now);
    await _store.saveWakePlan(pendingPlan);

    final cancelResult = await _cancelFutureReservedOccurrences(
      wakePlanId: pendingPlan.id,
      now: now,
      usePlanCancel: false,
    );
    if (!cancelResult.isSuccess) {
      if (previousPlan != null) {
        await _store.saveWakePlan(previousPlan.copyWith(updatedAt: now));
      }
      return WakePlanSchedulingResult(
        wakePlanId: pendingPlan.id,
        status: WakePlanSchedulingStatus.cancelFailed,
        changeState: WakePlanChangeState.failed,
        scheduleResult: ScheduleResult.fromRequestResults(
          requests: const [],
          results: const [],
        ),
        cancelResult: cancelResult.cancelResult,
        occurrences: cancelResult.persistedOccurrences,
        warning: WakePlanSchedulingWarning._cancelFailed(cancelResult),
      );
    }

    final scheduleResult = await _generateAndSchedule(
      plan: pendingPlan,
      now: now,
      changeState: WakePlanChangeState.committed,
      cancelResult: cancelResult.cancelResult,
    );
    if (scheduleResult.status == WakePlanSchedulingStatus.scheduleFailed &&
        previousPlan != null) {
      final recoveredOccurrences = await _cancelReplacementOccurrences(
        scheduleResult.occurrences,
        now: now,
      );
      await _store.saveWakePlan(previousPlan.copyWith(updatedAt: now));
      return WakePlanSchedulingResult(
        wakePlanId: scheduleResult.wakePlanId,
        status: scheduleResult.status,
        changeState: scheduleResult.changeState,
        scheduleResult: scheduleResult.scheduleResult,
        cancelResult: scheduleResult.cancelResult,
        occurrences: recoveredOccurrences,
        warning: scheduleResult.warning,
      );
    }
    return scheduleResult;
  }

  Future<WakePlanSchedulingResult> deletePlan(String wakePlanId) async {
    final now = _clock();
    final cancelResult = await _cancelFutureReservedOccurrences(
      wakePlanId: wakePlanId,
      now: now,
      usePlanCancel: true,
    );
    if (cancelResult.isSuccess) {
      await _store.softDeleteWakePlan(id: wakePlanId, updatedAt: now);
    }

    return WakePlanSchedulingResult(
      wakePlanId: wakePlanId,
      status: cancelResult.isSuccess
          ? WakePlanSchedulingStatus.deleted
          : WakePlanSchedulingStatus.cancelFailed,
      changeState: cancelResult.isSuccess
          ? WakePlanChangeState.committed
          : WakePlanChangeState.failed,
      scheduleResult: ScheduleResult.fromRequestResults(
        requests: const [],
        results: const [],
      ),
      cancelResult: cancelResult.cancelResult,
      occurrences: cancelResult.persistedOccurrences,
      warning: cancelResult.isSuccess
          ? null
          : WakePlanSchedulingWarning._cancelFailed(cancelResult),
    );
  }

  Future<WakePlanSchedulingResult> skipNextOccurrence(WakePlan wakePlan) async {
    final currentPlan = await _store.fetchWakePlan(wakePlan.id);
    if (currentPlan == null) {
      return Future.value(
        _emptyResult(
          wakePlanId: wakePlan.id,
          status: WakePlanSchedulingStatus.scheduled,
        ),
      );
    }
    if (currentPlan.repeatRule.type == RepeatType.oneTime) {
      return _emptyResult(
        wakePlanId: currentPlan.id,
        status: WakePlanSchedulingStatus.scheduled,
      );
    }

    final now = _clock();
    final skipDate = nextWakePlanTargetDay(plan: currentPlan, now: now);
    if (skipDate == null) {
      return _emptyResult(
        wakePlanId: currentPlan.id,
        status: WakePlanSchedulingStatus.scheduled,
      );
    }

    return editPlan(currentPlan.copyWith(skipNextDate: skipDate));
  }

  Future<WakePlanSchedulingResult> undoSkipNextOccurrence(
    WakePlan wakePlan,
  ) async {
    final currentPlan = await _store.fetchWakePlan(wakePlan.id);
    if (currentPlan == null) {
      return _emptyResult(
        wakePlanId: wakePlan.id,
        status: WakePlanSchedulingStatus.scheduled,
      );
    }

    return editPlan(currentPlan.copyWith(skipNextDate: null));
  }

  Future<WakePlanSchedulingResult> _generateAndSchedule({
    required WakePlan plan,
    required DateTime now,
    required WakePlanChangeState changeState,
    CancelResult? cancelResult,
  }) async {
    final occurrenceBundle = _buildOccurrenceBundle(plan: plan, now: now);
    await _store.saveAlarmOccurrences(occurrenceBundle.occurrences);

    final scheduleResult = await _nativeAlarmGateway.scheduleOccurrences(
      occurrenceBundle.requests,
    );
    final completedOccurrences = _applyScheduleResult(
      occurrences: occurrenceBundle.occurrences,
      scheduleResult: scheduleResult,
      updatedAt: now,
    );
    await _store.saveAlarmOccurrences(completedOccurrences);

    final hasFailedOccurrences = completedOccurrences.any(
      (occurrence) => occurrence.status == AlarmOccurrenceStatus.failed,
    );
    final hasScheduleFailure =
        !scheduleResult.isSuccess || hasFailedOccurrences;
    final status = hasScheduleFailure
        ? WakePlanSchedulingStatus.scheduleFailed
        : WakePlanSchedulingStatus.scheduled;
    return WakePlanSchedulingResult(
      wakePlanId: plan.id,
      status: status,
      changeState: !hasScheduleFailure
          ? changeState
          : WakePlanChangeState.failed,
      scheduleResult: scheduleResult,
      cancelResult: cancelResult,
      occurrences: completedOccurrences,
      warning: !hasScheduleFailure
          ? null
          : WakePlanSchedulingWarning.scheduleFailed(scheduleResult),
    );
  }

  _OccurrenceBundle _buildOccurrenceBundle({
    required WakePlan plan,
    required DateTime now,
  }) {
    final startDay = CalendarDay.fromDateTime(now);
    final occurrencePlan = _occurrencePlanner.plan(
      wakePlan: plan,
      startDay: startDay,
      endExclusive: startDay.addDays(_rollingScheduleDays),
      now: now,
    );
    final createdOccurrences = <AlarmOccurrence>[];
    final requests = <NativeAlarmScheduleRequest>[];
    final seenScheduleTimes = <DateMinute>{};
    final createdAt = now;

    for (final instance in occurrencePlan.wakeInstances) {
      final uniqueDrafts = instance.occurrences
          .where((draft) {
            if (draft.scheduledAt.toDateTime().isBefore(now)) {
              return false;
            }
            return seenScheduleTimes.add(draft.scheduledAt);
          })
          .toList(growable: false);

      for (final draft in uniqueDrafts) {
        final occurrence = AlarmOccurrence(
          id: _occurrenceId(
            wakePlanId: plan.id,
            scheduledAt: draft.scheduledAt,
          ),
          wakePlanId: plan.id,
          scheduledAt: draft.scheduledAt,
          status: AlarmOccurrenceStatus.scheduled,
          createdAt: createdAt,
          updatedAt: createdAt,
        );
        createdOccurrences.add(occurrence);
      }
    }

    for (var index = 0; index < createdOccurrences.length; index += 1) {
      final occurrence = createdOccurrences[index];
      final targetAt = _targetAtFor(
        occurrence.scheduledAt,
        occurrencePlan.wakeInstances,
      );
      requests.add(
        NativeAlarmScheduleRequest(
          occurrenceId: occurrence.id,
          wakePlanId: occurrence.wakePlanId,
          scheduledAt: occurrence.scheduledAt.toDateTime(),
          targetAt: targetAt.toDateTime(),
          indexInPlan: index,
          totalInPlan: createdOccurrences.length,
          soundId: plan.soundId,
          vibrationEnabled: plan.vibrationEnabled,
        ),
      );
    }

    return _OccurrenceBundle(
      occurrences: createdOccurrences,
      requests: requests,
    );
  }

  List<AlarmOccurrence> _applyScheduleResult({
    required List<AlarmOccurrence> occurrences,
    required ScheduleResult scheduleResult,
    required DateTime updatedAt,
  }) {
    final resultsById = {
      for (final result in scheduleResult.occurrences)
        result.occurrenceId: result,
    };

    return occurrences
        .map((occurrence) {
          final result = resultsById[occurrence.id];
          if (result == null) {
            return occurrence.copyWith(
              status: AlarmOccurrenceStatus.failed,
              failureReason: ScheduleFailureReason.nativeError.name,
              updatedAt: updatedAt,
            );
          }
          if (result.isSuccess) {
            return occurrence.copyWith(
              platformAlarmId: result.platformAlarmId,
              updatedAt: updatedAt,
            );
          }

          return occurrence.copyWith(
            status: result.platformAlarmId == null
                ? AlarmOccurrenceStatus.failed
                : AlarmOccurrenceStatus.scheduled,
            platformAlarmId: result.platformAlarmId,
            failureReason: result.platformAlarmId == null
                ? result.failureReason?.name ?? 'unknown'
                : null,
            updatedAt: updatedAt,
          );
        })
        .toList(growable: false);
  }

  Future<_CancelFutureResult> _cancelFutureReservedOccurrences({
    required String wakePlanId,
    required DateTime now,
    required bool usePlanCancel,
  }) async {
    final reserved = await _store.fetchReservedOccurrencesForPlan(wakePlanId);
    final futureReserved = reserved
        .where((occurrence) {
          return !occurrence.scheduledAt.toDateTime().isBefore(now);
        })
        .toList(growable: false);
    final cancellableFutureReserved = futureReserved
        .where((occurrence) => occurrence.platformAlarmId != null)
        .toList(growable: false);
    final requests = cancellableFutureReserved
        .map(
          (occurrence) => NativeAlarmCancelRequest(
            occurrenceId: occurrence.id,
            platformAlarmId: occurrence.platformAlarmId!,
          ),
        )
        .toList(growable: false);

    final cancelResult = usePlanCancel
        ? await _nativeAlarmGateway.cancelPlan(requests)
        : await _nativeAlarmGateway.cancelOccurrences(requests);
    final successKeys = cancelResult.alarms
        .where((alarm) => alarm.isSuccess)
        .map(_cancelKey)
        .toSet();
    final failureKeys = cancelResult.alarms
        .where((alarm) => !alarm.isSuccess)
        .map(_cancelKey)
        .toSet();
    final persistedOccurrences = cancellableFutureReserved
        .map((occurrence) {
          final key = _cancelRequestKey(
            occurrenceId: occurrence.id,
            platformAlarmId: occurrence.platformAlarmId!,
          );
          if (successKeys.contains(key)) {
            return occurrence.copyWith(
              status: AlarmOccurrenceStatus.cancelled,
              platformAlarmId: null,
              updatedAt: now,
            );
          }
          if (failureKeys.contains(key)) {
            return occurrence.copyWith(
              status: occurrence.status,
              failureReason: null,
              updatedAt: now,
            );
          }
          return occurrence;
        })
        .toList(growable: false);

    if (persistedOccurrences.isNotEmpty) {
      await _store.saveAlarmOccurrences(persistedOccurrences);
    }

    return _CancelFutureResult(
      cancelResult: cancelResult,
      persistedOccurrences: persistedOccurrences,
    );
  }

  Future<List<AlarmOccurrence>> _cancelReplacementOccurrences(
    List<AlarmOccurrence> occurrences, {
    required DateTime now,
  }) async {
    final cancellableOccurrences = occurrences
        .where((occurrence) => occurrence.platformAlarmId != null)
        .toList(growable: false);
    if (cancellableOccurrences.isEmpty) {
      return occurrences;
    }

    final requests = cancellableOccurrences
        .map(
          (occurrence) => NativeAlarmCancelRequest(
            occurrenceId: occurrence.id,
            platformAlarmId: occurrence.platformAlarmId!,
          ),
        )
        .toList(growable: false);
    final cancelResult = await _nativeAlarmGateway.cancelOccurrences(requests);
    final successKeys = cancelResult.alarms
        .where((alarm) => alarm.isSuccess)
        .map(_cancelKey)
        .toSet();
    final failureKeys = cancelResult.alarms
        .where((alarm) => !alarm.isSuccess)
        .map(_cancelKey)
        .toSet();
    final recoveredOccurrences = occurrences
        .map((occurrence) {
          final platformAlarmId = occurrence.platformAlarmId;
          if (platformAlarmId == null) {
            return occurrence;
          }
          final key = _cancelRequestKey(
            occurrenceId: occurrence.id,
            platformAlarmId: platformAlarmId,
          );
          if (successKeys.contains(key)) {
            return occurrence.copyWith(
              status: AlarmOccurrenceStatus.cancelled,
              platformAlarmId: null,
              updatedAt: now,
            );
          }
          if (failureKeys.contains(key)) {
            return occurrence.copyWith(updatedAt: now);
          }
          return occurrence;
        })
        .toList(growable: false);
    await _store.saveAlarmOccurrences(recoveredOccurrences);
    return recoveredOccurrences;
  }
}

WakePlanSchedulingResult _emptyResult({
  required String wakePlanId,
  required WakePlanSchedulingStatus status,
}) {
  return WakePlanSchedulingResult(
    wakePlanId: wakePlanId,
    status: status,
    changeState: WakePlanChangeState.committed,
    scheduleResult: ScheduleResult.fromRequestResults(
      requests: const [],
      results: const [],
    ),
    occurrences: const [],
  );
}

CalendarDay? nextWakePlanTargetDay({
  required WakePlan plan,
  required DateTime now,
}) {
  final today = CalendarDay.fromDateTime(now);
  for (var offset = 0; offset <= 370; offset += 1) {
    final day = today.addDays(offset);
    if (!plan.occursOn(day)) {
      continue;
    }
    if (plan.targetAt(day).isBefore(now)) {
      continue;
    }
    return day;
  }

  return null;
}

abstract class WakePlanServiceStore {
  Future<WakePlan?> fetchWakePlan(String id);

  Future<void> saveWakePlan(WakePlan plan);

  Future<void> softDeleteWakePlan({
    required String id,
    required DateTime updatedAt,
  });

  Future<void> saveAlarmOccurrences(Iterable<AlarmOccurrence> occurrences);

  Future<List<AlarmOccurrence>> fetchReservedOccurrencesForPlan(
    String wakePlanId,
  );
}

class WakePlanRepositoryServiceStore implements WakePlanServiceStore {
  WakePlanRepositoryServiceStore(this._repository);

  final WakePlanRepository _repository;

  @override
  Future<WakePlan?> fetchWakePlan(String id) {
    return _repository.fetchWakePlan(id);
  }

  @override
  Future<void> saveWakePlan(WakePlan plan) {
    return _repository.saveWakePlan(plan);
  }

  @override
  Future<void> softDeleteWakePlan({
    required String id,
    required DateTime updatedAt,
  }) {
    return _repository.softDeleteWakePlan(id: id, updatedAt: updatedAt);
  }

  @override
  Future<void> saveAlarmOccurrences(Iterable<AlarmOccurrence> occurrences) {
    return _repository.saveAlarmOccurrences(occurrences);
  }

  @override
  Future<List<AlarmOccurrence>> fetchReservedOccurrencesForPlan(
    String wakePlanId,
  ) {
    return _repository.fetchReservedOccurrencesForPlan(wakePlanId);
  }
}

enum WakePlanSchedulingStatus {
  scheduled,
  scheduleFailed,
  cancelFailed,
  deleted,
}

enum WakePlanChangeState { pendingChange, committed, failed }

class WakePlanSchedulingResult {
  WakePlanSchedulingResult({
    required this.wakePlanId,
    required this.status,
    required this.changeState,
    required this.scheduleResult,
    required List<AlarmOccurrence> occurrences,
    this.cancelResult,
    this.warning,
  }) : occurrences = List.unmodifiable(occurrences);

  final String wakePlanId;
  final WakePlanSchedulingStatus status;
  final WakePlanChangeState changeState;
  final ScheduleResult scheduleResult;
  final CancelResult? cancelResult;
  final List<AlarmOccurrence> occurrences;
  final WakePlanSchedulingWarning? warning;

  bool get isSuccess => warning == null;
}

class WakePlanSchedulingWarning {
  const WakePlanSchedulingWarning({
    required this.kind,
    required this.message,
    this.scheduleStatus,
    this.cancelStatus,
    this.scheduleFailureReasons = const {},
    this.cancelFailureReasons = const {},
  });

  factory WakePlanSchedulingWarning.scheduleFailed(ScheduleResult result) {
    return WakePlanSchedulingWarning(
      kind: WakePlanSchedulingWarningKind.scheduleFailed,
      message: _scheduleWarningMessage(result.status),
      scheduleStatus: result.status,
      scheduleFailureReasons: result.occurrences
          .map((occurrence) => occurrence.failureReason)
          .whereType<ScheduleFailureReason>()
          .toSet(),
    );
  }

  factory WakePlanSchedulingWarning._cancelFailed(_CancelFutureResult result) {
    return WakePlanSchedulingWarning(
      kind: WakePlanSchedulingWarningKind.cancelFailed,
      message: 'Some existing alarms could not be cancelled.',
      cancelStatus: result.cancelResult.status,
      cancelFailureReasons: result.cancelResult.alarms
          .map((alarm) => alarm.failureReason)
          .whereType<CancelFailureReason>()
          .toSet(),
    );
  }

  final WakePlanSchedulingWarningKind kind;
  final String message;
  final ScheduleResultStatus? scheduleStatus;
  final CancelResultStatus? cancelStatus;
  final Set<ScheduleFailureReason> scheduleFailureReasons;
  final Set<CancelFailureReason> cancelFailureReasons;
}

enum WakePlanSchedulingWarningKind { scheduleFailed, cancelFailed }

class _OccurrenceBundle {
  const _OccurrenceBundle({required this.occurrences, required this.requests});

  final List<AlarmOccurrence> occurrences;
  final List<NativeAlarmScheduleRequest> requests;
}

class _CancelFutureResult {
  const _CancelFutureResult({
    required this.cancelResult,
    required this.persistedOccurrences,
  });

  final CancelResult cancelResult;
  final List<AlarmOccurrence> persistedOccurrences;

  bool get isSuccess => cancelResult.isSuccess;
}

DateMinute _targetAtFor(
  DateMinute scheduledAt,
  List<WakeInstanceDraft> instances,
) {
  for (final instance in instances) {
    if (instance.occurrences.any((draft) => draft.scheduledAt == scheduledAt)) {
      return instance.targetAt;
    }
  }

  return scheduledAt;
}

String _occurrenceId({
  required String wakePlanId,
  required DateMinute scheduledAt,
}) {
  return [
    wakePlanId,
    scheduledAt.day.daysSinceUnixEpoch,
    scheduledAt.time.minutesSinceMidnight,
  ].join(':');
}

String _cancelKey(CancelAlarmResult alarm) {
  return _cancelRequestKey(
    occurrenceId: alarm.occurrenceId,
    platformAlarmId: alarm.platformAlarmId,
  );
}

String _cancelRequestKey({
  required String occurrenceId,
  required String platformAlarmId,
}) {
  return '$occurrenceId\u0000$platformAlarmId';
}

String _scheduleWarningMessage(ScheduleResultStatus status) {
  return switch (status) {
    ScheduleResultStatus.permissionMissing =>
      'Alarm permission is required before alarms can be scheduled.',
    ScheduleResultStatus.osConstraint =>
      'The operating system blocked alarm scheduling.',
    ScheduleResultStatus.partialFailure =>
      'Some alarms could not be scheduled.',
    ScheduleResultStatus.failure => 'Alarms could not be scheduled.',
    ScheduleResultStatus.success => 'Alarms could not be scheduled.',
  };
}
