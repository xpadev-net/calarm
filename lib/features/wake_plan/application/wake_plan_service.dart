import 'dart:async';

import '../../../core/platform/native_alarm_gateway.dart';
import '../../../core/time/time.dart';
import '../data/wake_plan_data.dart';
import '../domain/wake_plan_domain.dart';
import 'occurrence_planner.dart';

typedef WakePlanClock = DateTime Function();

class WakePlanService {
  static final Expando<_WakePlanServiceCoordinator> _coordinators =
      Expando<_WakePlanServiceCoordinator>();

  WakePlanService({
    required WakePlanRepository repository,
    required NativeAlarmGateway nativeAlarmGateway,
    OccurrencePlanner occurrencePlanner = const OccurrencePlanner(),
    WakePlanClock? clock,
    int rollingScheduleDays = 7,
  }) : this._(
         store: WakePlanRepositoryServiceStore(repository),
         coordinator: _coordinatorFor(repository),
         nativeAlarmGateway: nativeAlarmGateway,
         occurrencePlanner: occurrencePlanner,
         clock: clock ?? DateTime.now,
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
         coordinator: _coordinatorFor(store),
         nativeAlarmGateway: nativeAlarmGateway,
         occurrencePlanner: occurrencePlanner,
         clock: clock ?? DateTime.now,
         rollingScheduleDays: rollingScheduleDays,
       );

  WakePlanService._({
    required this._store,
    required this._coordinator,
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
  final _WakePlanServiceCoordinator _coordinator;
  final NativeAlarmGateway _nativeAlarmGateway;
  final OccurrencePlanner _occurrencePlanner;
  final WakePlanClock _clock;
  final int _rollingScheduleDays;
  Future<List<WakePlanSchedulingResult>>? _reconciliation;
  bool _reconciliationPending = false;
  final Map<String, Future<WakePlanSchedulingResult>> _createOperations = {};

  static _WakePlanServiceCoordinator _coordinatorFor(Object key) {
    return _coordinators[key] ??= _WakePlanServiceCoordinator();
  }

  Future<WakePlanSchedulingResult> createPlan(WakePlan plan) {
    final currentOperation = _createOperations[plan.id];
    if (currentOperation != null) {
      return currentOperation;
    }

    final completer = Completer<WakePlanSchedulingResult>();
    final operation = completer.future;
    _createOperations[plan.id] = operation;
    unawaited(_completeCreatePlan(plan: plan, completer: completer));
    return operation;
  }

  Future<void> _completeCreatePlan({
    required WakePlan plan,
    required Completer<WakePlanSchedulingResult> completer,
  }) async {
    try {
      final result = await _createPlan(plan);
      _createOperations.remove(plan.id);
      completer.complete(result);
    } catch (error, stackTrace) {
      _createOperations.remove(plan.id);
      completer.completeError(error, stackTrace);
    }
  }

  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(String wakePlanId) {
    return _store.fetchOccurrencesForPlan(wakePlanId);
  }

  Future<AlarmOccurrenceToggleResult> setOccurrenceEnabled({
    required String wakePlanId,
    required String occurrenceId,
    required bool enabled,
  }) {
    return _coordinator.run(
      () => _setOccurrenceEnabled(
        wakePlanId: wakePlanId,
        occurrenceId: occurrenceId,
        enabled: enabled,
      ),
    );
  }

  Future<AlarmOccurrenceToggleResult> _setOccurrenceEnabled({
    required String wakePlanId,
    required String occurrenceId,
    required bool enabled,
  }) async {
    final now = _clock();
    final occurrences = await _store.fetchOccurrencesForPlan(wakePlanId);
    AlarmOccurrence? occurrence;
    for (final candidate in occurrences) {
      if (candidate.id == occurrenceId) {
        occurrence = candidate;
        break;
      }
    }
    if (occurrence == null || occurrence.wakePlanId != wakePlanId) {
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.invalidState,
        warning: 'The selected alarm occurrence no longer exists.',
      );
    }

    if (enabled &&
        occurrence.status == AlarmOccurrenceStatus.scheduled &&
        occurrence.hasNativeReservation &&
        occurrence.scheduledAt.toDateTime().isAfter(now)) {
      return AlarmOccurrenceToggleResult.success(
        status: AlarmOccurrenceToggleStatus.enabled,
        occurrence: occurrence,
      );
    }
    if (!enabled &&
        occurrence.isUserDisabled &&
        occurrence.scheduledAt.toDateTime().isAfter(now)) {
      return AlarmOccurrenceToggleResult.success(
        status: AlarmOccurrenceToggleStatus.disabled,
        occurrence: occurrence,
      );
    }
    if (!occurrence.isUserToggleEligibleAt(now)) {
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.invalidState,
        occurrence: occurrence,
        warning: 'This alarm occurrence can no longer be changed.',
      );
    }

    final plan = await _store.fetchWakePlan(wakePlanId);
    if (plan == null ||
        !plan.isEnabled ||
        plan.isDeleted ||
        plan.status == WakePlanStatus.finished) {
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.invalidState,
        occurrence: occurrence,
        warning: 'The wake plan is no longer available for scheduling.',
      );
    }

    return enabled
        ? _enableOccurrence(plan: plan, occurrence: occurrence, now: now)
        : _disableOccurrence(plan: plan, occurrence: occurrence, now: now);
  }

  Future<AlarmOccurrenceToggleResult> _disableOccurrence({
    required WakePlan plan,
    required AlarmOccurrence occurrence,
    required DateTime now,
  }) async {
    final cancelRequest = NativeAlarmCancelRequest(
      occurrenceId: occurrence.id,
      platformAlarmId: occurrence.platformAlarmId!,
    );
    CancelResult cancelResult;
    try {
      cancelResult = await _nativeAlarmGateway.cancelOccurrences([
        cancelRequest,
      ]);
    } catch (_) {
      final observation = await _observeNativeReservation(
        occurrenceId: occurrence.id,
        wakePlanId: occurrence.wakePlanId,
      );
      final nativeRow = observation.activeRow;
      if (observation.isAuthoritative && nativeRow == null) {
        cancelResult = CancelResult.fromRequestResults(
          requests: [cancelRequest],
          results: [
            CancelAlarmResult.success(
              occurrenceId: cancelRequest.occurrenceId,
              platformAlarmId: cancelRequest.platformAlarmId,
              reservationId: cancelRequest.reservationId,
            ),
          ],
        );
      } else if (observation.isAuthoritative) {
        final observed = occurrence.copyWith(
          status: AlarmOccurrenceStatus.scheduled,
          platformAlarmId: nativeRow!.platformAlarmId,
          updatedAt: now,
        );
        final persistenceError = await _trySaveAlarmOccurrences([observed]);
        return AlarmOccurrenceToggleResult.failure(
          status: AlarmOccurrenceToggleStatus.cancelFailed,
          occurrence: observed,
          databaseState: persistenceError == null
              ? WakePlanDatabaseState.persisted
              : WakePlanDatabaseState.unknown,
          persistenceError: persistenceError,
          warning: 'The native alarm is still on after cancellation failed.',
        );
      } else {
        final pendingRecovery = occurrence.copyWith(
          status: AlarmOccurrenceStatus.scheduled,
          platformAlarmId: null,
          updatedAt: now,
        );
        final persistenceError = await _trySaveAlarmOccurrences([
          pendingRecovery,
        ]);
        return AlarmOccurrenceToggleResult.failure(
          status: AlarmOccurrenceToggleStatus.recoveryRequired,
          occurrence: pendingRecovery,
          databaseState: persistenceError == null
              ? WakePlanDatabaseState.persisted
              : WakePlanDatabaseState.unknown,
          persistenceError: persistenceError,
          warning: persistenceError == null
              ? 'The native cancellation state is unknown and will be reconciled.'
              : 'The native alarm cancellation and stored state are unknown.',
        );
      }
    }
    if (!cancelResult.isSuccess) {
      final observation = await _observeNativeReservation(
        occurrenceId: occurrence.id,
        wakePlanId: occurrence.wakePlanId,
      );
      final nativeRow = observation.activeRow;
      if (observation.isAuthoritative && nativeRow == null) {
        cancelResult = CancelResult.fromRequestResults(
          requests: [cancelRequest],
          results: [
            CancelAlarmResult.success(
              occurrenceId: cancelRequest.occurrenceId,
              platformAlarmId: cancelRequest.platformAlarmId,
              reservationId: cancelRequest.reservationId,
            ),
          ],
        );
      } else {
        final observed = nativeRow == null
            ? occurrence
            : occurrence.copyWith(
                status: AlarmOccurrenceStatus.scheduled,
                platformAlarmId: nativeRow.platformAlarmId,
                updatedAt: now,
              );
        return AlarmOccurrenceToggleResult.failure(
          status: AlarmOccurrenceToggleStatus.cancelFailed,
          occurrence: observed,
          cancelResult: cancelResult,
          warning: 'The native alarm could not be turned off.',
        );
      }
    }

    final disabled = occurrence.copyWith(
      status: AlarmOccurrenceStatus.userDisabled,
      platformAlarmId: null,
      failureReason: null,
      updatedAt: now,
    );
    final persistenceError = await _trySaveAlarmOccurrences([disabled]);
    if (persistenceError == null) {
      return AlarmOccurrenceToggleResult.success(
        status: AlarmOccurrenceToggleStatus.disabled,
        occurrence: disabled,
        cancelResult: cancelResult,
      );
    }

    _RestorationResult restoration;
    try {
      restoration = await _restoreCancelledOccurrences(
        plan: plan,
        occurrences: [occurrence],
        now: now,
      );
    } catch (_) {
      final pendingRecovery = occurrence.copyWith(
        status: AlarmOccurrenceStatus.scheduled,
        platformAlarmId: null,
        failureReason: null,
        updatedAt: now,
      );
      final recoveryPersistenceError = await _trySaveAlarmOccurrences([
        pendingRecovery,
      ]);
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: pendingRecovery,
        cancelResult: cancelResult,
        databaseState: recoveryPersistenceError == null
            ? WakePlanDatabaseState.persisted
            : WakePlanDatabaseState.unknown,
        persistenceError: _firstPersistenceError([
          persistenceError,
          recoveryPersistenceError,
        ]),
        warning: recoveryPersistenceError == null
            ? 'The alarm could not be restored immediately and will be reconciled.'
            : 'The alarm restoration state is unknown.',
      );
    }
    return AlarmOccurrenceToggleResult.failure(
      status: AlarmOccurrenceToggleStatus.recoveryRequired,
      occurrence: restoration.occurrences.isEmpty
          ? occurrence
          : restoration.occurrences.single,
      cancelResult: cancelResult,
      compensationScheduleResult: restoration.scheduleResult,
      databaseState: restoration.databaseStateKnown
          ? WakePlanDatabaseState.persisted
          : WakePlanDatabaseState.unknown,
      persistenceError: _firstPersistenceError([
        persistenceError,
        restoration.persistenceError,
      ]),
      warning: restoration.isSuccess
          ? 'The disabled state could not be saved, so the alarm was restored.'
          : 'The disabled state could not be saved and recovery is required.',
    );
  }

  Future<AlarmOccurrenceToggleResult> _enableOccurrence({
    required WakePlan plan,
    required AlarmOccurrence occurrence,
    required DateTime now,
  }) async {
    final requests = _buildRestorationRequests(
      plan: plan,
      occurrences: [occurrence],
      now: now,
    );
    if (requests == null || requests.length != 1) {
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.invalidState,
        occurrence: occurrence,
        warning: 'The alarm occurrence could not be mapped to its wake target.',
      );
    }

    final pending = occurrence.copyWith(
      status: AlarmOccurrenceStatus.scheduled,
      platformAlarmId: null,
      failureReason: null,
      updatedAt: now,
    );
    final pendingPersistenceError = await _trySaveAlarmOccurrences([pending]);
    if (pendingPersistenceError != null) {
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: occurrence,
        databaseState: WakePlanDatabaseState.unknown,
        persistenceError: pendingPersistenceError,
        warning:
            'The alarm could not be enabled because its state was not saved.',
      );
    }

    ScheduleResult scheduleResult;
    try {
      scheduleResult = await _nativeAlarmGateway.scheduleOccurrences(requests);
    } catch (_) {
      final observation = await _observeNativeReservation(
        occurrenceId: occurrence.id,
        wakePlanId: occurrence.wakePlanId,
      );
      final nativeRow = observation.activeRow;
      if (!observation.isAuthoritative) {
        return AlarmOccurrenceToggleResult.failure(
          status: AlarmOccurrenceToggleStatus.recoveryRequired,
          occurrence: pending,
          warning:
              'The native scheduling state is unknown and will be reconciled.',
        );
      }
      if (nativeRow != null) {
        final observed = pending.copyWith(
          platformAlarmId: nativeRow.platformAlarmId,
          updatedAt: now,
        );
        final persistenceError = await _trySaveAlarmOccurrences([observed]);
        if (persistenceError == null) {
          return AlarmOccurrenceToggleResult.success(
            status: AlarmOccurrenceToggleStatus.enabled,
            occurrence: observed,
          );
        }
        return AlarmOccurrenceToggleResult.failure(
          status: AlarmOccurrenceToggleStatus.recoveryRequired,
          occurrence: observed,
          databaseState: WakePlanDatabaseState.unknown,
          persistenceError: persistenceError,
          warning:
              'The native alarm is on, but its enabled state could not be saved.',
        );
      }
      final rollbackPersistenceError = await _trySaveAlarmOccurrences([
        occurrence.copyWith(updatedAt: now),
      ]);
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: occurrence,
        databaseState: rollbackPersistenceError == null
            ? WakePlanDatabaseState.persisted
            : WakePlanDatabaseState.unknown,
        persistenceError: rollbackPersistenceError,
        warning: rollbackPersistenceError == null
            ? 'The native alarm could not be enabled and remains off.'
            : 'The native alarm scheduling state is unknown.',
      );
    }
    final completed = _applyScheduleResult(
      occurrences: [pending],
      scheduleResult: scheduleResult,
      updatedAt: now,
    ).single;
    final completionPersistenceError = await _trySaveAlarmOccurrences([
      completed,
    ]);
    if (completionPersistenceError == null) {
      if (scheduleResult.isSuccess &&
          completed.status == AlarmOccurrenceStatus.scheduled &&
          completed.hasNativeReservation) {
        return AlarmOccurrenceToggleResult.success(
          status: AlarmOccurrenceToggleStatus.enabled,
          occurrence: completed,
          scheduleResult: scheduleResult,
        );
      }
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.scheduleFailed,
        occurrence: completed,
        scheduleResult: scheduleResult,
        warning: 'The native alarm could not be turned on.',
      );
    }

    final platformAlarmId = completed.platformAlarmId;
    if (platformAlarmId == null) {
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: completed,
        scheduleResult: scheduleResult,
        databaseState: WakePlanDatabaseState.unknown,
        persistenceError: completionPersistenceError,
        warning:
            'The scheduling result could not be saved; recovery is required.',
      );
    }

    CancelResult compensationCancelResult;
    try {
      compensationCancelResult = await _nativeAlarmGateway.cancelOccurrences([
        NativeAlarmCancelRequest(
          occurrenceId: completed.id,
          platformAlarmId: platformAlarmId,
        ),
      ]);
    } catch (_) {
      final retryPersistenceError = await _trySaveAlarmOccurrences([completed]);
      if (retryPersistenceError == null) {
        return AlarmOccurrenceToggleResult.failure(
          status: AlarmOccurrenceToggleStatus.scheduleFailed,
          occurrence: completed,
          scheduleResult: scheduleResult,
          warning:
              'The alarm was enabled, but cancellation recovery is unknown.',
        );
      }
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: completed,
        scheduleResult: scheduleResult,
        databaseState: WakePlanDatabaseState.unknown,
        persistenceError: _firstPersistenceError([
          completionPersistenceError,
          retryPersistenceError,
        ]),
        warning: 'The enabled alarm state is unknown and recovery is required.',
      );
    }
    if (compensationCancelResult.isSuccess) {
      final rollbackPersistenceError = await _trySaveAlarmOccurrences([
        occurrence.copyWith(updatedAt: now),
      ]);
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: occurrence,
        scheduleResult: scheduleResult,
        compensationCancelResult: compensationCancelResult,
        databaseState: rollbackPersistenceError == null
            ? WakePlanDatabaseState.persisted
            : WakePlanDatabaseState.unknown,
        persistenceError: _firstPersistenceError([
          completionPersistenceError,
          rollbackPersistenceError,
        ]),
        warning: rollbackPersistenceError == null
            ? 'The enabled state could not be saved, so the alarm remains off.'
            : 'The enabled state could not be saved and recovery is required.',
      );
    }

    final retryPersistenceError = await _trySaveAlarmOccurrences([completed]);
    if (retryPersistenceError == null) {
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.scheduleFailed,
        occurrence: completed,
        scheduleResult: scheduleResult,
        compensationCancelResult: compensationCancelResult,
        warning: 'The alarm was enabled, but cancellation recovery failed.',
      );
    }
    return AlarmOccurrenceToggleResult.failure(
      status: AlarmOccurrenceToggleStatus.recoveryRequired,
      occurrence: completed,
      scheduleResult: scheduleResult,
      compensationCancelResult: compensationCancelResult,
      databaseState: WakePlanDatabaseState.unknown,
      persistenceError: _firstPersistenceError([
        completionPersistenceError,
        retryPersistenceError,
      ]),
      warning: 'The enabled alarm state is unknown and recovery is required.',
    );
  }

  Future<_NativeReservationObservation> _observeNativeReservation({
    required String occurrenceId,
    required String wakePlanId,
  }) async {
    NativeAlarmInventoryResult inventory;
    try {
      inventory = await _nativeAlarmGateway.getInventory();
    } catch (_) {
      return const _NativeReservationObservation.unavailable();
    }
    if (!inventory.isSuccess) {
      return const _NativeReservationObservation.unavailable();
    }
    NativeAlarmInventoryRow? activeRow;
    var hasConflictingIdentity = false;
    for (final row in inventory.rows) {
      final isRelated =
          row.reservationId == occurrenceId || row.occurrenceId == occurrenceId;
      if (!isRelated) {
        continue;
      }
      if (row.reservationId != occurrenceId ||
          row.occurrenceId != occurrenceId ||
          row.wakePlanId != wakePlanId) {
        hasConflictingIdentity = true;
        continue;
      }
      if (row.status == NativeAlarmReservationStatus.scheduled ||
          row.status == NativeAlarmReservationStatus.ringing) {
        activeRow = row;
      }
    }
    if (hasConflictingIdentity) {
      return const _NativeReservationObservation.unavailable();
    }
    return _NativeReservationObservation.authoritative(activeRow: activeRow);
  }

  Future<WakePlanSchedulingResult> _createPlan(WakePlan plan) async {
    final now = _clock();
    final persistedPlan = plan.copyWith(updatedAt: now);
    await _store.saveWakePlan(persistedPlan);
    final existingOccurrences = await _store.fetchOccurrencesForPlan(plan.id);

    return _generateAndSchedule(
      plan: persistedPlan,
      now: now,
      changeState: WakePlanChangeState.committed,
      existingOccurrences: existingOccurrences,
    );
  }

  Future<List<WakePlanSchedulingResult>> reconcileSchedules() {
    _reconciliationPending = true;
    final currentReconciliation = _reconciliation;
    if (currentReconciliation != null) {
      return currentReconciliation;
    }

    final completer = Completer<List<WakePlanSchedulingResult>>();
    _reconciliation = completer.future;
    unawaited(_drainReconciliations(completer));
    return completer.future;
  }

  Future<void> _drainReconciliations(
    Completer<List<WakePlanSchedulingResult>> completer,
  ) async {
    var hasError = false;
    Object? lastError;
    StackTrace? lastStackTrace;
    List<WakePlanSchedulingResult> results = const [];

    try {
      do {
        _reconciliationPending = false;
        try {
          results = await _coordinator.run(_runReconciliation);
          hasError = false;
        } catch (error, stackTrace) {
          hasError = true;
          lastError = error;
          lastStackTrace = stackTrace;
        }
      } while (_reconciliationPending);

      if (hasError) {
        completer.completeError(lastError!, lastStackTrace!);
      } else {
        completer.complete(results);
      }
    } finally {
      _reconciliation = null;
    }
  }

  Future<List<WakePlanSchedulingResult>> _runReconciliation() async {
    final now = _clock();
    final plans = await _store.fetchWakePlans(now: now);
    final results = <WakePlanSchedulingResult>[];

    for (final plan in plans) {
      if (!plan.isEnabled ||
          plan.isDeleted ||
          plan.status == WakePlanStatus.finished ||
          plan.repeatRule.type != RepeatType.weekly) {
        continue;
      }
      results.add(await _reconcilePlan(plan: plan, now: now));
    }

    return results;
  }

  Future<List<WakePlanSchedulingResult>> reconcile() {
    return reconcileSchedules();
  }

  Future<WakePlanSchedulingResult> editPlan(WakePlan plan) async {
    return _editPlan(plan, skipNextDate: _preserveCurrentSkipDate);
  }

  Future<WakePlanSchedulingResult> _editPlan(
    WakePlan plan, {
    required Object? skipNextDate,
  }) async {
    final now = _clock();
    final previousPlan = await _store.fetchWakePlan(plan.id);
    final pendingPlan = plan.copyWith(
      updatedAt: now,
      skipNextDate: _resolveEditedSkipDate(
        requestedSkipNextDate: skipNextDate,
        previousPlan: previousPlan,
        repeatRule: plan.repeatRule,
      ),
    );
    await _store.saveWakePlan(pendingPlan);

    final cancelResult = await _cancelFutureReservedOccurrences(
      wakePlanId: pendingPlan.id,
      now: now,
      usePlanCancel: false,
    );
    if (!cancelResult.isSuccess) {
      final restoration = previousPlan == null
          ? const _RestorationResult(scheduleResult: null, occurrences: [])
          : await _restoreCancelledOccurrences(
              plan: previousPlan,
              occurrences: cancelResult.successfullyCancelledOccurrences,
              now: now,
            );
      final planPersistenceError = previousPlan == null
          ? null
          : await _trySaveWakePlan(previousPlan.copyWith(updatedAt: now));
      final persistenceError = _firstPersistenceError([
        cancelResult.persistenceError,
        restoration.persistenceError,
        planPersistenceError,
      ]);
      final restoredOccurrences = _mergeOccurrenceStates(
        cancelResult.persistedOccurrences,
        restoration.occurrences,
      );
      final isRecoveryRequired =
          persistenceError != null || !restoration.isSuccess;
      return _failedMutationResult(
        wakePlanId: pendingPlan.id,
        status: isRecoveryRequired
            ? WakePlanSchedulingStatus.recoveryRequired
            : WakePlanSchedulingStatus.cancelFailed,
        scheduleResult: null,
        cancelResult: cancelResult.cancelResult,
        compensationScheduleResult: restoration.scheduleResult,
        occurrences: restoredOccurrences,
        databaseState:
            restoration.databaseStateKnown &&
                (cancelResult.persistenceError == null ||
                    cancelResult.successfullyCancelledOccurrences.isNotEmpty) &&
                planPersistenceError == null
            ? WakePlanDatabaseState.persisted
            : WakePlanDatabaseState.unknown,
        persistenceError: persistenceError,
        warning: !isRecoveryRequired
            ? WakePlanSchedulingWarning._cancelFailed(cancelResult)
            : WakePlanSchedulingWarning.recoveryRequired(
                'Wake plan cancellation could not be fully compensated.',
              ),
      );
    }

    final scheduleResult = await _generateAndSchedule(
      plan: pendingPlan,
      now: now,
      changeState: WakePlanChangeState.committed,
      cancelResult: cancelResult.cancelResult,
    );
    if ((scheduleResult.status == WakePlanSchedulingStatus.scheduleFailed ||
            scheduleResult.status ==
                WakePlanSchedulingStatus.recoveryRequired) &&
        previousPlan != null) {
      final replacementCancellation = await _cancelReplacementOccurrences(
        scheduleResult.occurrences,
        now: now,
      );
      if (!replacementCancellation.nativeCancellationComplete) {
        return _failedMutationResult(
          wakePlanId: scheduleResult.wakePlanId,
          status: WakePlanSchedulingStatus.recoveryRequired,
          scheduleResult: scheduleResult.scheduleResult,
          cancelResult: scheduleResult.cancelResult,
          compensationCancelResult: replacementCancellation.cancelResult,
          occurrences: _mergeOccurrenceStates(
            cancelResult.persistedOccurrences,
            replacementCancellation.persistedOccurrences,
          ),
          databaseState: replacementCancellation.databaseStateKnown
              ? scheduleResult.databaseState
              : WakePlanDatabaseState.unknown,
          persistenceError: _firstPersistenceError([
            scheduleResult.persistenceError,
            replacementCancellation.persistenceError,
          ]),
          warning: WakePlanSchedulingWarning.recoveryRequired(
            'Replacement alarms could not be fully cancelled; recovery is required.',
          ),
        );
      }
      final restoration = await _restoreCancelledOccurrences(
        plan: previousPlan,
        occurrences: cancelResult.successfullyCancelledOccurrences,
        now: now,
      );
      final planPersistenceError = await _trySaveWakePlan(
        previousPlan.copyWith(updatedAt: now),
      );
      final persistenceError = _firstPersistenceError([
        scheduleResult.persistenceError,
        replacementCancellation.persistenceError,
        restoration.persistenceError,
        planPersistenceError,
      ]);
      final isRecoveryRequired =
          persistenceError != null || !restoration.isSuccess;
      final recoveredOccurrences = _mergeOccurrenceStates(
        replacementCancellation.persistedOccurrences,
        restoration.occurrences,
      );
      return _failedMutationResult(
        wakePlanId: scheduleResult.wakePlanId,
        status: isRecoveryRequired
            ? WakePlanSchedulingStatus.recoveryRequired
            : scheduleResult.status,
        scheduleResult: scheduleResult.scheduleResult,
        cancelResult: scheduleResult.cancelResult,
        compensationCancelResult: replacementCancellation.cancelResult,
        compensationScheduleResult: restoration.scheduleResult,
        occurrences: recoveredOccurrences,
        databaseState:
            replacementCancellation.databaseStateKnown &&
                restoration.databaseStateKnown &&
                planPersistenceError == null
            ? WakePlanDatabaseState.persisted
            : WakePlanDatabaseState.unknown,
        persistenceError: persistenceError,
        warning: !isRecoveryRequired
            ? scheduleResult.warning!
            : WakePlanSchedulingWarning.recoveryRequired(
                'The previous schedule could not be fully restored.',
              ),
      );
    }
    return scheduleResult;
  }

  Future<WakePlanSchedulingResult> deletePlan(String wakePlanId) async {
    final now = _clock();
    final previousPlan = await _store.fetchWakePlan(wakePlanId);
    final cancelResult = await _cancelFutureReservedOccurrences(
      wakePlanId: wakePlanId,
      now: now,
      usePlanCancel: true,
    );
    if (!cancelResult.isSuccess) {
      final restoration = previousPlan == null
          ? const _RestorationResult(scheduleResult: null, occurrences: [])
          : await _restoreCancelledOccurrences(
              plan: previousPlan,
              occurrences: cancelResult.successfullyCancelledOccurrences,
              now: now,
            );
      final occurrences = _mergeOccurrenceStates(
        cancelResult.persistedOccurrences,
        restoration.occurrences,
      );
      final persistenceError = _firstPersistenceError([
        cancelResult.persistenceError,
        restoration.persistenceError,
      ]);
      final isRecoveryRequired =
          persistenceError != null || !restoration.isSuccess;
      return _failedMutationResult(
        wakePlanId: wakePlanId,
        status: isRecoveryRequired
            ? WakePlanSchedulingStatus.recoveryRequired
            : WakePlanSchedulingStatus.cancelFailed,
        scheduleResult: null,
        cancelResult: cancelResult.cancelResult,
        compensationScheduleResult: restoration.scheduleResult,
        occurrences: occurrences,
        databaseState:
            restoration.databaseStateKnown &&
                (cancelResult.persistenceError == null ||
                    cancelResult.successfullyCancelledOccurrences.isNotEmpty)
            ? WakePlanDatabaseState.persisted
            : WakePlanDatabaseState.unknown,
        persistenceError: persistenceError,
        warning: !isRecoveryRequired
            ? WakePlanSchedulingWarning._cancelFailed(cancelResult)
            : WakePlanSchedulingWarning.recoveryRequired(
                'Wake plan deletion cancellation could not be fully compensated.',
              ),
      );
    }

    try {
      await _store.softDeleteWakePlan(id: wakePlanId, updatedAt: now);
    } catch (error) {
      final restoration = previousPlan == null
          ? const _RestorationResult(scheduleResult: null, occurrences: [])
          : await _restoreCancelledOccurrences(
              plan: previousPlan,
              occurrences: cancelResult.successfullyCancelledOccurrences,
              now: now,
            );
      return _failedMutationResult(
        wakePlanId: wakePlanId,
        status: WakePlanSchedulingStatus.recoveryRequired,
        scheduleResult: null,
        cancelResult: cancelResult.cancelResult,
        compensationScheduleResult: restoration.scheduleResult,
        occurrences: _mergeOccurrenceStates(
          cancelResult.persistedOccurrences,
          restoration.occurrences,
        ),
        databaseState: WakePlanDatabaseState.unknown,
        persistenceError: _firstPersistenceError([
          'Wake plan persistence failed: $error',
          restoration.persistenceError,
        ]),
        warning: WakePlanSchedulingWarning.recoveryRequired(
          'Wake plan deletion could not be persisted; recovery is required.',
        ),
      );
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

    return _editPlan(
      currentPlan.copyWith(skipNextDate: skipDate),
      skipNextDate: skipDate,
    );
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

    return _editPlan(
      currentPlan.copyWith(skipNextDate: null),
      skipNextDate: null,
    );
  }

  Future<WakePlanSchedulingResult> _generateAndSchedule({
    required WakePlan plan,
    required DateTime now,
    required WakePlanChangeState changeState,
    CancelResult? cancelResult,
    List<AlarmOccurrence>? existingOccurrences,
  }) async {
    final occurrenceBundle = _buildOccurrenceBundle(plan: plan, now: now);
    if (_requiresFutureOccurrence(plan) &&
        occurrenceBundle.occurrences.isEmpty) {
      return _emptyScheduleFailureResult(
        wakePlanId: plan.id,
        cancelResult: cancelResult,
      );
    }

    final existingById = {
      for (final occurrence in existingOccurrences ?? const <AlarmOccurrence>[])
        occurrence.id: occurrence,
    };
    final preparedOccurrences = <AlarmOccurrence>[];
    final pendingOccurrences = <AlarmOccurrence>[];
    for (final desired in occurrenceBundle.occurrences) {
      final existing = existingById[desired.id];
      if (_preservesAuthoritativeSuppression(
        existing: existing,
        desired: desired,
        now: now,
      )) {
        preparedOccurrences.add(existing!.copyWith(updatedAt: now));
        continue;
      }
      if (_hasUsableCreateReservation(
        existing: existing,
        desired: desired,
        now: now,
      )) {
        preparedOccurrences.add(existing!.copyWith(updatedAt: now));
      } else {
        preparedOccurrences.add(desired);
        pendingOccurrences.add(desired);
      }
    }

    if (pendingOccurrences.isEmpty) {
      return _successfulReconciliationResult(
        plan: plan,
        occurrences: preparedOccurrences,
      );
    }

    final pendingIds = pendingOccurrences.map((occurrence) => occurrence.id);
    final pendingIdSet = pendingIds.toSet();
    final pendingRequests = existingOccurrences == null
        ? occurrenceBundle.requests
        : _reindexRequests(
            occurrenceBundle.requests
                .where((request) => pendingIdSet.contains(request.occurrenceId))
                .toList(growable: false),
          );
    await _store.saveAlarmOccurrences(pendingOccurrences);

    final scheduleResult = await _nativeAlarmGateway.scheduleOccurrences(
      pendingRequests,
    );
    final completedOccurrences = _applyScheduleResult(
      occurrences: pendingOccurrences,
      scheduleResult: scheduleResult,
      updatedAt: now,
    );
    final persistenceError = await _trySaveAlarmOccurrences(
      completedOccurrences,
    );

    final completedById = {
      for (final occurrence in completedOccurrences) occurrence.id: occurrence,
    };
    final reconciledOccurrences = preparedOccurrences
        .map((occurrence) => completedById[occurrence.id] ?? occurrence)
        .toList(growable: false);

    final hasFailedOccurrences = reconciledOccurrences.any(
      (occurrence) => occurrence.status == AlarmOccurrenceStatus.failed,
    );
    final hasScheduleFailure =
        !scheduleResult.isSuccess || hasFailedOccurrences;
    final status = persistenceError != null
        ? WakePlanSchedulingStatus.recoveryRequired
        : hasScheduleFailure
        ? WakePlanSchedulingStatus.scheduleFailed
        : WakePlanSchedulingStatus.scheduled;
    return WakePlanSchedulingResult(
      wakePlanId: plan.id,
      status: status,
      changeState: persistenceError != null
          ? WakePlanChangeState.recoveryRequired
          : !hasScheduleFailure
          ? changeState
          : WakePlanChangeState.failed,
      scheduleResult: scheduleResult,
      cancelResult: cancelResult,
      occurrences: reconciledOccurrences,
      databaseState: persistenceError == null
          ? WakePlanDatabaseState.persisted
          : WakePlanDatabaseState.unknown,
      persistenceError: persistenceError,
      warning: persistenceError != null
          ? WakePlanSchedulingWarning.recoveryRequired(
              'Scheduled alarm results could not be persisted; recovery is required.',
            )
          : !hasScheduleFailure
          ? null
          : WakePlanSchedulingWarning.scheduleFailed(scheduleResult),
    );
  }

  bool _hasUsableCreateReservation({
    required AlarmOccurrence? existing,
    required AlarmOccurrence desired,
    required DateTime now,
  }) {
    return existing != null &&
        existing.wakePlanId == desired.wakePlanId &&
        existing.scheduledAt == desired.scheduledAt &&
        (existing.status == AlarmOccurrenceStatus.scheduled ||
            existing.status == AlarmOccurrenceStatus.ringing) &&
        existing.hasNativeReservation &&
        (existing.status == AlarmOccurrenceStatus.ringing ||
            !existing.scheduledAt.toDateTime().isBefore(now));
  }

  Future<WakePlanSchedulingResult> _reconcilePlan({
    required WakePlan plan,
    required DateTime now,
  }) async {
    final existingOccurrences = await _store.fetchOccurrencesForPlan(plan.id);
    final existingById = {
      for (final occurrence in existingOccurrences) occurrence.id: occurrence,
    };
    final desiredBundle = _buildOccurrenceBundle(plan: plan, now: now);
    if (desiredBundle.occurrences.isEmpty) {
      if (plan.skipNextDate != null) {
        return _successfulReconciliationResult(
          plan: plan,
          occurrences: const [],
        );
      }
      return _emptyScheduleFailureResult(wakePlanId: plan.id);
    }

    final pendingOccurrences = desiredBundle.occurrences
        .map((desired) {
          final existing = existingById[desired.id];
          if (_preservesAuthoritativeSuppression(
            existing: existing,
            desired: desired,
            now: now,
          )) {
            return null;
          }
          if (_hasValidNativeReservation(existing, desired, now)) {
            return null;
          }
          if (existing == null) {
            return desired;
          }
          return existing.copyWith(
            status: AlarmOccurrenceStatus.scheduled,
            platformAlarmId: null,
            failureReason: null,
            updatedAt: now,
          );
        })
        .whereType<AlarmOccurrence>()
        .toList(growable: false);
    final pendingIds = pendingOccurrences.map((occurrence) => occurrence.id);
    final pendingIdSet = pendingIds.toSet();
    final pendingRequests = _reindexRequests(
      desiredBundle.requests
          .where((request) => pendingIdSet.contains(request.occurrenceId))
          .toList(growable: false),
    );

    if (pendingOccurrences.isEmpty) {
      return _successfulReconciliationResult(
        plan: plan,
        occurrences: desiredBundle.occurrences
            .map((desired) => existingById[desired.id] ?? desired)
            .toList(growable: false),
      );
    }

    await _store.saveAlarmOccurrences(pendingOccurrences);
    final scheduleResult = await _nativeAlarmGateway.scheduleOccurrences(
      pendingRequests,
    );
    final completedOccurrences = _applyScheduleResult(
      occurrences: pendingOccurrences,
      scheduleResult: scheduleResult,
      updatedAt: now,
    );
    final persistenceError = await _trySaveAlarmOccurrences(
      completedOccurrences,
    );

    final completedById = {
      for (final occurrence in completedOccurrences) occurrence.id: occurrence,
    };
    final reconciledOccurrences = desiredBundle.occurrences
        .map(
          (desired) =>
              completedById[desired.id] ?? existingById[desired.id] ?? desired,
        )
        .toList(growable: false);
    final hasFailedOccurrences = completedOccurrences.any(
      (occurrence) => occurrence.status == AlarmOccurrenceStatus.failed,
    );
    final hasScheduleFailure =
        !scheduleResult.isSuccess || hasFailedOccurrences;
    return WakePlanSchedulingResult(
      wakePlanId: plan.id,
      status: persistenceError != null
          ? WakePlanSchedulingStatus.recoveryRequired
          : hasScheduleFailure
          ? WakePlanSchedulingStatus.scheduleFailed
          : WakePlanSchedulingStatus.scheduled,
      changeState: persistenceError != null
          ? WakePlanChangeState.recoveryRequired
          : hasScheduleFailure
          ? WakePlanChangeState.failed
          : WakePlanChangeState.committed,
      scheduleResult: scheduleResult,
      occurrences: reconciledOccurrences,
      databaseState: persistenceError == null
          ? WakePlanDatabaseState.persisted
          : WakePlanDatabaseState.unknown,
      persistenceError: persistenceError,
      warning: persistenceError != null
          ? WakePlanSchedulingWarning.recoveryRequired(
              'Reconciled alarm results could not be persisted; recovery is required.',
            )
          : hasScheduleFailure
          ? WakePlanSchedulingWarning.scheduleFailed(scheduleResult)
          : null,
    );
  }

  bool _hasValidNativeReservation(
    AlarmOccurrence? existing,
    AlarmOccurrence desired,
    DateTime now,
  ) {
    if (existing == null ||
        !existing.hasNativeReservation ||
        (existing.status != AlarmOccurrenceStatus.scheduled &&
            existing.status != AlarmOccurrenceStatus.ringing)) {
      return false;
    }

    return existing.scheduledAt == desired.scheduledAt &&
        (existing.status == AlarmOccurrenceStatus.ringing ||
            !existing.scheduledAt.toDateTime().isBefore(now));
  }

  bool _preservesAuthoritativeSuppression({
    required AlarmOccurrence? existing,
    required AlarmOccurrence desired,
    required DateTime now,
  }) {
    if (existing == null) {
      return false;
    }
    final preservesStatus = switch (existing.status) {
      AlarmOccurrenceStatus.userDisabled => !existing.hasNativeReservation,
      AlarmOccurrenceStatus.unknownPersisted => true,
      _ => false,
    };
    return preservesStatus &&
        existing.wakePlanId == desired.wakePlanId &&
        existing.scheduledAt == desired.scheduledAt &&
        !existing.scheduledAt.toDateTime().isBefore(now);
  }

  WakePlanSchedulingResult _successfulReconciliationResult({
    required WakePlan plan,
    required List<AlarmOccurrence> occurrences,
  }) {
    return WakePlanSchedulingResult(
      wakePlanId: plan.id,
      status: WakePlanSchedulingStatus.scheduled,
      changeState: WakePlanChangeState.committed,
      scheduleResult: ScheduleResult.fromRequestResults(
        requests: const [],
        results: const [],
      ),
      occurrences: occurrences,
    );
  }

  List<NativeAlarmScheduleRequest> _reindexRequests(
    List<NativeAlarmScheduleRequest> requests,
  ) {
    return [
      for (var index = 0; index < requests.length; index += 1)
        NativeAlarmScheduleRequest(
          occurrenceId: requests[index].occurrenceId,
          wakePlanId: requests[index].wakePlanId,
          scheduledAt: requests[index].scheduledAt,
          targetAt: requests[index].targetAt,
          indexInPlan: index,
          totalInPlan: requests.length,
          soundId: requests[index].soundId,
          vibrationEnabled: requests[index].vibrationEnabled,
        ),
    ];
  }

  bool _requiresFutureOccurrence(WakePlan plan) {
    return plan.isEnabled &&
        !plan.isDeleted &&
        plan.status != WakePlanStatus.finished &&
        plan.skipNextDate == null &&
        plan.repeatRule.type == RepeatType.weekly;
  }

  WakePlanSchedulingResult _emptyScheduleFailureResult({
    required String wakePlanId,
    CancelResult? cancelResult,
  }) {
    final scheduleResult = ScheduleResult(
      status: ScheduleResultStatus.failure,
      occurrences: const [],
    );
    return WakePlanSchedulingResult(
      wakePlanId: wakePlanId,
      status: WakePlanSchedulingStatus.scheduleFailed,
      changeState: WakePlanChangeState.failed,
      scheduleResult: scheduleResult,
      cancelResult: cancelResult,
      occurrences: const [],
      warning: WakePlanSchedulingWarning.emptySchedule(),
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
    return _cancelOccurrences(
      occurrences: cancellableFutureReserved,
      now: now,
      usePlanCancel: usePlanCancel,
    );
  }

  Future<_CancelFutureResult> _cancelOccurrences({
    required List<AlarmOccurrence> occurrences,
    required DateTime now,
    required bool usePlanCancel,
  }) async {
    final cancellableOccurrences = occurrences
        .where((occurrence) => occurrence.platformAlarmId != null)
        .toList(growable: false);
    final requests = cancellableOccurrences
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
    final persistedOccurrences = cancellableOccurrences
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

    final persistenceError = persistedOccurrences.isEmpty
        ? null
        : await _trySaveAlarmOccurrences(persistedOccurrences);

    return _CancelFutureResult(
      cancelResult: cancelResult,
      persistedOccurrences: persistedOccurrences,
      databaseStateKnown: persistenceError == null,
      persistenceError: persistenceError,
      successfullyCancelledOccurrences: cancellableOccurrences
          .where((occurrence) {
            final key = _cancelRequestKey(
              occurrenceId: occurrence.id,
              platformAlarmId: occurrence.platformAlarmId!,
            );
            return successKeys.contains(key);
          })
          .toList(growable: false),
    );
  }

  Future<_CancelFutureResult> _cancelReplacementOccurrences(
    List<AlarmOccurrence> occurrences, {
    required DateTime now,
  }) async {
    final cancellation = await _cancelOccurrences(
      occurrences: occurrences,
      now: now,
      usePlanCancel: false,
    );
    return _CancelFutureResult(
      cancelResult: cancellation.cancelResult,
      persistedOccurrences: _mergeOccurrenceStates(
        occurrences,
        cancellation.persistedOccurrences,
      ),
      databaseStateKnown: cancellation.databaseStateKnown,
      persistenceError: cancellation.persistenceError,
      successfullyCancelledOccurrences:
          cancellation.successfullyCancelledOccurrences,
    );
  }

  Future<_RestorationResult> _restoreCancelledOccurrences({
    required WakePlan plan,
    required List<AlarmOccurrence> occurrences,
    required DateTime now,
  }) async {
    if (occurrences.isEmpty) {
      return const _RestorationResult(scheduleResult: null, occurrences: []);
    }

    final pendingOccurrences = occurrences
        .map(
          (occurrence) => occurrence.copyWith(
            status: AlarmOccurrenceStatus.scheduled,
            platformAlarmId: null,
            failureReason: null,
            updatedAt: now,
          ),
        )
        .toList(growable: false);
    final restorationRequests = _buildRestorationRequests(
      plan: plan,
      occurrences: occurrences,
      now: now,
    );
    if (restorationRequests == null) {
      final scheduleResult = ScheduleResult.fromOccurrences([
        for (final occurrence in pendingOccurrences)
          ScheduleOccurrenceResult.failure(
            occurrenceId: occurrence.id,
            wakePlanId: occurrence.wakePlanId,
            reason: ScheduleFailureReason.nativeError,
            message: 'Could not map occurrence to its owning wake instance.',
          ),
      ]);
      final restoredOccurrences = _applyScheduleResult(
        occurrences: pendingOccurrences,
        scheduleResult: scheduleResult,
        updatedAt: now,
      );
      final persistenceError = await _trySaveAlarmOccurrences(
        restoredOccurrences,
      );
      return _RestorationResult(
        scheduleResult: scheduleResult,
        occurrences: restoredOccurrences,
        databaseStateKnown: persistenceError == null,
        persistenceError: persistenceError,
      );
    }
    final scheduleResult = await _nativeAlarmGateway.scheduleOccurrences(
      restorationRequests,
    );
    final restoredOccurrences = _applyScheduleResult(
      occurrences: pendingOccurrences,
      scheduleResult: scheduleResult,
      updatedAt: now,
    );
    final persistenceError = await _trySaveAlarmOccurrences(
      restoredOccurrences,
    );
    return _RestorationResult(
      scheduleResult: scheduleResult,
      occurrences: restoredOccurrences,
      databaseStateKnown: persistenceError == null,
      persistenceError: persistenceError,
    );
  }

  Future<String?> _trySaveAlarmOccurrences(
    Iterable<AlarmOccurrence> occurrences,
  ) async {
    try {
      await _store.saveAlarmOccurrences(occurrences);
      return null;
    } catch (error) {
      return 'Alarm occurrence persistence failed: $error';
    }
  }

  Future<String?> _trySaveWakePlan(WakePlan plan) async {
    try {
      await _store.saveWakePlan(plan);
      return null;
    } catch (error) {
      return 'Wake plan persistence failed: $error';
    }
  }

  String? _firstPersistenceError(Iterable<String?> errors) {
    for (final error in errors) {
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  List<NativeAlarmScheduleRequest>? _buildRestorationRequests({
    required WakePlan plan,
    required List<AlarmOccurrence> occurrences,
    required DateTime now,
  }) {
    final canonicalRequests = _buildOccurrenceBundle(
      plan: plan,
      now: now,
    ).requests;
    final canonicalById = {
      for (final request in canonicalRequests) request.occurrenceId: request,
    };
    final canonicalByScheduledAt = {
      for (final request in canonicalRequests) request.scheduledAt: request,
    };
    final matchedRequests = <NativeAlarmScheduleRequest>[];
    for (final occurrence in occurrences) {
      final canonical =
          canonicalById[occurrence.id] ??
          canonicalByScheduledAt[occurrence.scheduledAt.toDateTime()];
      if (canonical == null) {
        return null;
      }
      matchedRequests.add(
        NativeAlarmScheduleRequest(
          occurrenceId: occurrence.id,
          wakePlanId: occurrence.wakePlanId,
          scheduledAt: occurrence.scheduledAt.toDateTime(),
          targetAt: canonical.targetAt,
          indexInPlan: canonical.indexInPlan,
          totalInPlan: canonical.totalInPlan,
          soundId: plan.soundId,
          vibrationEnabled: plan.vibrationEnabled,
        ),
      );
    }
    return matchedRequests;
  }

  List<AlarmOccurrence> _mergeOccurrenceStates(
    List<AlarmOccurrence> base,
    List<AlarmOccurrence> overlay,
  ) {
    final byId = <String, AlarmOccurrence>{
      for (final occurrence in base) occurrence.id: occurrence,
    };
    for (final occurrence in overlay) {
      byId[occurrence.id] = occurrence;
    }
    return byId.values.toList(growable: false);
  }

  WakePlanSchedulingResult _failedMutationResult({
    required String wakePlanId,
    required WakePlanSchedulingStatus status,
    required ScheduleResult? scheduleResult,
    required CancelResult? cancelResult,
    required List<AlarmOccurrence> occurrences,
    required WakePlanSchedulingWarning warning,
    ScheduleResult? compensationScheduleResult,
    CancelResult? compensationCancelResult,
    WakePlanDatabaseState databaseState = WakePlanDatabaseState.persisted,
    String? persistenceError,
  }) {
    return WakePlanSchedulingResult(
      wakePlanId: wakePlanId,
      status: status,
      changeState: status == WakePlanSchedulingStatus.recoveryRequired
          ? WakePlanChangeState.recoveryRequired
          : WakePlanChangeState.failed,
      scheduleResult:
          scheduleResult ??
          ScheduleResult.fromRequestResults(
            requests: const [],
            results: const [],
          ),
      cancelResult: cancelResult,
      occurrences: occurrences,
      warning: warning,
      compensationScheduleResult: compensationScheduleResult,
      compensationCancelResult: compensationCancelResult,
      databaseState: databaseState,
      persistenceError: persistenceError,
    );
  }
}

const Object _preserveCurrentSkipDate = Object();

CalendarDay? _resolveEditedSkipDate({
  required Object? requestedSkipNextDate,
  required WakePlan? previousPlan,
  required RepeatRule repeatRule,
}) {
  final skipNextDate = requestedSkipNextDate == _preserveCurrentSkipDate
      ? previousPlan?.skipNextDate
      : requestedSkipNextDate as CalendarDay?;
  if (skipNextDate == null || !repeatRule.includes(skipNextDate)) {
    return null;
  }
  return skipNextDate;
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

  Future<List<WakePlan>> fetchWakePlans({required DateTime now});

  Future<void> saveWakePlan(WakePlan plan);

  Future<void> softDeleteWakePlan({
    required String id,
    required DateTime updatedAt,
  });

  Future<void> saveAlarmOccurrences(Iterable<AlarmOccurrence> occurrences);

  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(String wakePlanId);

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
  Future<List<WakePlan>> fetchWakePlans({required DateTime now}) {
    return _repository.fetchWakePlans(now: now);
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
  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(String wakePlanId) {
    return _repository.fetchOccurrencesForPlan(wakePlanId);
  }

  @override
  Future<List<AlarmOccurrence>> fetchReservedOccurrencesForPlan(
    String wakePlanId,
  ) {
    return _repository.fetchReservedOccurrencesForPlan(wakePlanId);
  }
}

class _WakePlanServiceCoordinator {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class _NativeReservationObservation {
  const _NativeReservationObservation.authoritative({this.activeRow})
    : isAuthoritative = true;

  const _NativeReservationObservation.unavailable()
    : isAuthoritative = false,
      activeRow = null;

  final bool isAuthoritative;
  final NativeAlarmInventoryRow? activeRow;
}

enum AlarmOccurrenceToggleStatus {
  enabled,
  disabled,
  invalidState,
  cancelFailed,
  scheduleFailed,
  recoveryRequired,
}

class AlarmOccurrenceToggleResult {
  const AlarmOccurrenceToggleResult._({
    required this.status,
    required this.occurrence,
    required this.warning,
    required this.databaseState,
    required this.persistenceError,
    required this.scheduleResult,
    required this.cancelResult,
    required this.compensationScheduleResult,
    required this.compensationCancelResult,
  });

  factory AlarmOccurrenceToggleResult.success({
    required AlarmOccurrenceToggleStatus status,
    required AlarmOccurrence occurrence,
    ScheduleResult? scheduleResult,
    CancelResult? cancelResult,
  }) {
    return AlarmOccurrenceToggleResult._(
      status: status,
      occurrence: occurrence,
      warning: null,
      databaseState: WakePlanDatabaseState.persisted,
      persistenceError: null,
      scheduleResult: scheduleResult,
      cancelResult: cancelResult,
      compensationScheduleResult: null,
      compensationCancelResult: null,
    );
  }

  factory AlarmOccurrenceToggleResult.failure({
    required AlarmOccurrenceToggleStatus status,
    required String warning,
    AlarmOccurrence? occurrence,
    WakePlanDatabaseState databaseState = WakePlanDatabaseState.persisted,
    String? persistenceError,
    ScheduleResult? scheduleResult,
    CancelResult? cancelResult,
    ScheduleResult? compensationScheduleResult,
    CancelResult? compensationCancelResult,
  }) {
    return AlarmOccurrenceToggleResult._(
      status: status,
      occurrence: occurrence,
      warning: warning,
      databaseState: databaseState,
      persistenceError: persistenceError,
      scheduleResult: scheduleResult,
      cancelResult: cancelResult,
      compensationScheduleResult: compensationScheduleResult,
      compensationCancelResult: compensationCancelResult,
    );
  }

  final AlarmOccurrenceToggleStatus status;
  final AlarmOccurrence? occurrence;
  final String? warning;
  final WakePlanDatabaseState databaseState;
  final String? persistenceError;
  final ScheduleResult? scheduleResult;
  final CancelResult? cancelResult;
  final ScheduleResult? compensationScheduleResult;
  final CancelResult? compensationCancelResult;

  bool get isSuccess =>
      status == AlarmOccurrenceToggleStatus.enabled ||
      status == AlarmOccurrenceToggleStatus.disabled;
}

enum WakePlanSchedulingStatus {
  scheduled,
  scheduleFailed,
  cancelFailed,
  recoveryRequired,
  deleted,
}

enum WakePlanChangeState { pendingChange, committed, failed, recoveryRequired }

enum WakePlanDatabaseState { persisted, unknown }

class WakePlanSchedulingResult {
  WakePlanSchedulingResult({
    required this.wakePlanId,
    required this.status,
    required this.changeState,
    required this.scheduleResult,
    required List<AlarmOccurrence> occurrences,
    this.cancelResult,
    this.warning,
    this.compensationScheduleResult,
    this.compensationCancelResult,
    this.databaseState = WakePlanDatabaseState.persisted,
    this.persistenceError,
  }) : occurrences = List.unmodifiable(occurrences);

  final String wakePlanId;
  final WakePlanSchedulingStatus status;
  final WakePlanChangeState changeState;
  final ScheduleResult scheduleResult;
  final CancelResult? cancelResult;
  final List<AlarmOccurrence> occurrences;
  final WakePlanSchedulingWarning? warning;
  final ScheduleResult? compensationScheduleResult;
  final CancelResult? compensationCancelResult;
  final WakePlanDatabaseState databaseState;
  final String? persistenceError;

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

  factory WakePlanSchedulingWarning.emptySchedule() {
    return const WakePlanSchedulingWarning(
      kind: WakePlanSchedulingWarningKind.scheduleFailed,
      message: 'No future alarm occurrence could be scheduled.',
      scheduleStatus: ScheduleResultStatus.failure,
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

  factory WakePlanSchedulingWarning.recoveryRequired(String message) {
    return WakePlanSchedulingWarning(
      kind: WakePlanSchedulingWarningKind.recoveryRequired,
      message: message,
    );
  }

  final WakePlanSchedulingWarningKind kind;
  final String message;
  final ScheduleResultStatus? scheduleStatus;
  final CancelResultStatus? cancelStatus;
  final Set<ScheduleFailureReason> scheduleFailureReasons;
  final Set<CancelFailureReason> cancelFailureReasons;
}

enum WakePlanSchedulingWarningKind {
  scheduleFailed,
  cancelFailed,
  recoveryRequired,
}

class _OccurrenceBundle {
  const _OccurrenceBundle({required this.occurrences, required this.requests});

  final List<AlarmOccurrence> occurrences;
  final List<NativeAlarmScheduleRequest> requests;
}

class _CancelFutureResult {
  const _CancelFutureResult({
    required this.cancelResult,
    required this.persistedOccurrences,
    required this.successfullyCancelledOccurrences,
    this.databaseStateKnown = true,
    this.persistenceError,
  });

  final CancelResult cancelResult;
  final List<AlarmOccurrence> persistedOccurrences;
  final List<AlarmOccurrence> successfullyCancelledOccurrences;
  final bool databaseStateKnown;
  final String? persistenceError;

  bool get isSuccess => cancelResult.isSuccess && persistenceError == null;

  bool get nativeCancellationComplete => cancelResult.isSuccess;
}

class _RestorationResult {
  const _RestorationResult({
    required this.scheduleResult,
    required this.occurrences,
    this.databaseStateKnown = true,
    this.persistenceError,
  });

  final ScheduleResult? scheduleResult;
  final List<AlarmOccurrence> occurrences;
  final bool databaseStateKnown;
  final String? persistenceError;

  bool get isSuccess =>
      persistenceError == null &&
      (scheduleResult == null ||
          scheduleResult!.isSuccess &&
              occurrences.every(
                (occurrence) =>
                    occurrence.status == AlarmOccurrenceStatus.scheduled &&
                    occurrence.platformAlarmId != null,
              ));
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
