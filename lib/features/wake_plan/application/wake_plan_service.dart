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
         coordinator: _coordinatorFor(store.coordinationKey),
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
      final result = await _coordinator.run(() => _createPlan(plan));
      _createOperations.remove(plan.id);
      completer.complete(result);
    } catch (error, stackTrace) {
      _createOperations.remove(plan.id);
      completer.completeError(error, stackTrace);
    }
  }

  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(String wakePlanId) {
    return _coordinator.run(() async {
      final now = _clock();
      final plan = await _store.fetchWakePlan(wakePlanId);
      if (plan == null ||
          !plan.isEnabled ||
          plan.isDeleted ||
          plan.status == WakePlanStatus.finished) {
        return const [];
      }
      final canonicalIds = _canonicalFutureOccurrenceIds(plan: plan, now: now);
      final occurrences = await _store.fetchOccurrencesForPlan(wakePlanId);
      return occurrences
          .where((occurrence) => canonicalIds.contains(occurrence.id))
          .toList(growable: false);
    });
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
    final canonicalIds = _canonicalFutureOccurrenceIds(plan: plan, now: now);
    if (!canonicalIds.contains(occurrence.id) ||
        !occurrence.isUserToggleEligibleAt(now)) {
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.invalidState,
        occurrence: occurrence,
        warning: 'This alarm occurrence can no longer be changed.',
      );
    }

    if (enabled &&
        occurrence.status == AlarmOccurrenceStatus.scheduled &&
        occurrence.hasNativeReservation) {
      return AlarmOccurrenceToggleResult.success(
        status: AlarmOccurrenceToggleStatus.enabled,
        occurrence: occurrence,
      );
    }
    if (!enabled && occurrence.isUserDisabled) {
      return AlarmOccurrenceToggleResult.success(
        status: AlarmOccurrenceToggleStatus.disabled,
        occurrence: occurrence,
      );
    }

    return enabled
        ? _enableOccurrence(plan: plan, occurrence: occurrence, now: now)
        : _disableOccurrence(occurrence: occurrence, now: now);
  }

  Future<AlarmOccurrenceToggleResult> _disableOccurrence({
    required AlarmOccurrence occurrence,
    required DateTime now,
  }) async {
    final pending = occurrence.copyWith(
      status: AlarmOccurrenceStatus.userDisablePending,
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
            'The off intent could not be saved, so the native alarm was not changed.',
      );
    }

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
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: pending,
        databaseState: WakePlanDatabaseState.persisted,
        warning: 'The alarm is still being turned off and will be reconciled.',
      );
    }
    if (!cancelResult.isSuccess) {
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: pending,
        cancelResult: cancelResult,
        databaseState: WakePlanDatabaseState.persisted,
        warning: 'The alarm is still being turned off and will be reconciled.',
      );
    }

    final disabled = pending.copyWith(
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
    return AlarmOccurrenceToggleResult.failure(
      status: AlarmOccurrenceToggleStatus.recoveryRequired,
      occurrence: pending,
      cancelResult: cancelResult,
      databaseState: WakePlanDatabaseState.persisted,
      persistenceError: persistenceError,
      warning: 'The disabled state will be completed during reconciliation.',
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
      final uncertain = pending.copyWith(
        status: AlarmOccurrenceStatus.userEnablePending,
        updatedAt: now,
      );
      final persistenceError = await _trySaveAlarmOccurrences([uncertain]);
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: uncertain,
        databaseState: persistenceError == null
            ? WakePlanDatabaseState.persisted
            : WakePlanDatabaseState.unknown,
        persistenceError: persistenceError,
        warning:
            'The native scheduling state is unknown and will be reconciled.',
      );
    }
    final completed = _applyScheduleResult(
      occurrences: [pending],
      scheduleResult: scheduleResult,
      updatedAt: now,
    ).single;
    if (!scheduleResult.isSuccess && completed.platformAlarmId == null) {
      final retryableDisabled = occurrence.copyWith(updatedAt: now);
      final rollbackPersistenceError = await _trySaveAlarmOccurrences([
        retryableDisabled,
      ]);
      return AlarmOccurrenceToggleResult.failure(
        status: rollbackPersistenceError == null
            ? AlarmOccurrenceToggleStatus.scheduleFailed
            : AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: retryableDisabled,
        scheduleResult: scheduleResult,
        databaseState: rollbackPersistenceError == null
            ? WakePlanDatabaseState.persisted
            : WakePlanDatabaseState.unknown,
        persistenceError: rollbackPersistenceError,
        warning: rollbackPersistenceError == null
            ? 'The native alarm could not be turned on.'
            : 'The alarm remains off, but its retry state could not be saved.',
      );
    }
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
      final uncertain = completed.copyWith(
        status: AlarmOccurrenceStatus.userEnablePending,
        updatedAt: now,
      );
      final retryPersistenceError = await _trySaveAlarmOccurrences([uncertain]);
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: uncertain,
        scheduleResult: scheduleResult,
        databaseState: retryPersistenceError == null
            ? WakePlanDatabaseState.persisted
            : WakePlanDatabaseState.unknown,
        persistenceError: _firstPersistenceError([
          completionPersistenceError,
          retryPersistenceError,
        ]),
        warning: 'The enabled alarm state is unknown and will be reconciled.',
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

    final uncertain = completed.copyWith(
      status: AlarmOccurrenceStatus.userEnablePending,
      updatedAt: now,
    );
    final retryPersistenceError = await _trySaveAlarmOccurrences([uncertain]);
    if (retryPersistenceError == null) {
      return AlarmOccurrenceToggleResult.failure(
        status: AlarmOccurrenceToggleStatus.recoveryRequired,
        occurrence: uncertain,
        scheduleResult: scheduleResult,
        compensationCancelResult: compensationCancelResult,
        warning: 'The enabled alarm state is unknown and will be reconciled.',
      );
    }
    return AlarmOccurrenceToggleResult.failure(
      status: AlarmOccurrenceToggleStatus.recoveryRequired,
      occurrence: uncertain,
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

  Future<_NativeInventorySnapshot?> _loadNativeInventory() async {
    NativeAlarmInventoryResult inventory;
    try {
      inventory = await _nativeAlarmGateway.getInventory();
    } catch (_) {
      return null;
    }
    if (!inventory.isSuccess && inventory.rows.isEmpty) {
      return null;
    }
    return _NativeInventorySnapshot(
      rows: inventory.rows,
      isAuthoritative: inventory.isSuccess,
    );
  }

  _NativeReservationObservation _observeNativeReservationInInventory({
    required String occurrenceId,
    required String wakePlanId,
    required _NativeInventorySnapshot? inventory,
  }) {
    if (inventory == null) {
      return const _NativeReservationObservation.unavailable();
    }
    final exactRowsByPlatformId = <String, NativeAlarmInventoryRow>{};
    final activeRowsByPlatformId = <String, NativeAlarmInventoryRow>{};
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
      exactRowsByPlatformId[row.platformAlarmId] = row;
      if (row.status == NativeAlarmReservationStatus.scheduled ||
          row.status == NativeAlarmReservationStatus.ringing) {
        activeRowsByPlatformId[row.platformAlarmId] = row;
      }
    }
    if (hasConflictingIdentity || exactRowsByPlatformId.length > 1) {
      return const _NativeReservationObservation.ambiguous();
    }
    if (!inventory.isAuthoritative) {
      return const _NativeReservationObservation.unavailable();
    }
    return _NativeReservationObservation.authoritative(
      activeRow: activeRowsByPlatformId.values.firstOrNull,
    );
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
    final persistedSnapshot = await _store.fetchReconciliationSnapshot(
      now: now,
    );
    final plans = persistedSnapshot.plans;
    final inventoryPreparation = await _prepareWholeInventory(
      plans: plans,
      occurrences: persistedSnapshot.occurrences,
      corruptPlanIds: persistedSnapshot.corruptPlanIds,
      corruptOccurrenceIds: persistedSnapshot.corruptOccurrenceIds,
      corruptOccurrenceWakePlanIds:
          persistedSnapshot.corruptOccurrenceWakePlanIds,
      now: now,
    );
    final decodedPlanIds = plans.map((plan) => plan.id).toSet();
    final results = <WakePlanSchedulingResult>[
      for (final planId in inventoryPreparation.blockedPlanIds)
        if (!decodedPlanIds.contains(planId))
          _inventoryRecoveryResultForPlanId(
            wakePlanId: planId,
            occurrences:
                inventoryPreparation.occurrencesByPlan[planId] ?? const [],
            persistenceError:
                inventoryPreparation.persistenceErrorsByPlan[planId],
          ),
    ];

    for (final plan in plans) {
      final persistedOccurrences =
          inventoryPreparation.occurrencesByPlan[plan.id] ?? const [];
      if (!plan.isEnabled ||
          plan.isDeleted ||
          plan.status == WakePlanStatus.finished) {
        if (inventoryPreparation.blockedPlanIds.contains(plan.id)) {
          results.add(
            _inventoryRecoveryResult(
              plan: plan,
              occurrences: persistedOccurrences,
            ),
          );
        }
        continue;
      }
      if (inventoryPreparation.blockedPlanIds.contains(plan.id)) {
        results.add(
          _inventoryRecoveryResult(
            plan: plan,
            occurrences: persistedOccurrences,
            persistenceError:
                inventoryPreparation.persistenceErrorsByPlan[plan.id],
          ),
        );
        continue;
      }

      try {
        WakePlanSchedulingResult result;
        if (plan.repeatRule.type == RepeatType.weekly ||
            inventoryPreparation.scheduleCanonicalPlanIds.contains(plan.id)) {
          result = await _reconcilePlan(
            plan: plan,
            now: now,
            persistedOccurrences: persistedOccurrences,
            inventory: inventoryPreparation.inventory,
          );
        } else {
          final recoveryOccurrenceIds = persistedOccurrences
              .where((occurrence) => _isEligibleRecoveryMarker(occurrence, now))
              .map((occurrence) => occurrence.id)
              .toSet();
          if (recoveryOccurrenceIds.isEmpty) {
            if (inventoryPreparation.recoveryPlanIds.contains(plan.id)) {
              results.add(
                _inventoryRecoveryResult(
                  plan: plan,
                  occurrences: persistedOccurrences,
                  persistenceError:
                      inventoryPreparation.persistenceErrorsByPlan[plan.id],
                ),
              );
            } else if (inventoryPreparation.repairedPlanIds.contains(plan.id)) {
              results.add(
                _successfulReconciliationResult(
                  plan: plan,
                  occurrences: persistedOccurrences,
                ),
              );
            }
            continue;
          }
          result = await _reconcilePlan(
            plan: plan,
            now: now,
            persistedOccurrences: persistedOccurrences,
            scheduleCandidateIds: recoveryOccurrenceIds,
            inventory: inventoryPreparation.inventory,
          );
        }
        results.add(
          inventoryPreparation.recoveryPlanIds.contains(plan.id)
              ? _withInventoryRecovery(
                  result,
                  inventoryPreparation.persistenceErrorsByPlan[plan.id],
                )
              : result,
        );
      } catch (error) {
        results.add(
          _inventoryRecoveryResult(
            plan: plan,
            occurrences: persistedOccurrences,
            persistenceError: 'Wake plan reconciliation failed: $error',
          ),
        );
      }
    }

    return results;
  }

  Future<_WholeInventoryPreparation> _prepareWholeInventory({
    required List<WakePlan> plans,
    required List<AlarmOccurrence> occurrences,
    required Set<String> corruptPlanIds,
    required Set<String> corruptOccurrenceIds,
    required Set<String> corruptOccurrenceWakePlanIds,
    required DateTime now,
  }) async {
    final originalById = {
      for (final occurrence in occurrences) occurrence.id: occurrence,
    };
    final knownPlanIds = plans.map((plan) => plan.id).toSet();
    final activePlanIds = plans
        .where(
          (plan) =>
              plan.isEnabled &&
              !plan.isDeleted &&
              plan.status != WakePlanStatus.finished,
        )
        .map((plan) => plan.id)
        .toSet();
    final corruptInventoryPlanIds = <String>{
      ...corruptPlanIds,
      ...corruptOccurrenceWakePlanIds,
    };
    final desiredById = <String, AlarmOccurrence>{};
    final desiredPlanIdsById = <String, Set<String>>{};
    for (final plan in plans) {
      if (!activePlanIds.contains(plan.id)) {
        continue;
      }
      for (final occurrence in _buildOccurrenceBundle(
        plan: plan,
        now: now,
      ).occurrences) {
        desiredById[occurrence.id] = occurrence;
        (desiredPlanIdsById[occurrence.id] ??= {}).add(plan.id);
      }
    }
    for (final planIds in desiredPlanIdsById.values) {
      if (planIds.length > 1) {
        corruptInventoryPlanIds.addAll(planIds);
      }
    }
    for (final corruptOccurrenceId in corruptOccurrenceIds) {
      final decoded = originalById[corruptOccurrenceId];
      if (decoded != null) {
        corruptInventoryPlanIds.add(decoded.wakePlanId);
      }
      corruptInventoryPlanIds.addAll(
        desiredPlanIdsById[corruptOccurrenceId] ?? const {},
      );
    }
    final inventory = await _loadNativeInventory();

    Set<String> participantPlanIds(NativeAlarmInventoryRow row) {
      final participants = <String>{row.wakePlanId};
      for (final identity in {row.reservationId, row.occurrenceId}) {
        final decoded = originalById[identity];
        if (decoded != null) {
          participants.add(decoded.wakePlanId);
        }
        participants.addAll(desiredPlanIdsById[identity] ?? const {});
      }
      return participants;
    }

    bool hasOwnedParticipant(Set<String> participants) {
      return participants.any(
        (planId) =>
            knownPlanIds.contains(planId) || corruptPlanIds.contains(planId),
      );
    }

    bool hasTupleConflict(NativeAlarmInventoryRow row) {
      final byReservation = originalById[row.reservationId];
      final byOccurrence = originalById[row.occurrenceId];
      return row.reservationId != row.occurrenceId ||
          byReservation != byOccurrence ||
          participantPlanIds(row).length > 1 ||
          (byReservation != null && byReservation.wakePlanId != row.wakePlanId);
    }

    void propagateBlockedParticipants() {
      if (inventory == null) {
        return;
      }
      var expanded = true;
      while (expanded) {
        expanded = false;
        for (final row in inventory.rows) {
          final participants = participantPlanIds(row);
          if (!participants.any(corruptInventoryPlanIds.contains)) {
            continue;
          }
          final previousLength = corruptInventoryPlanIds.length;
          corruptInventoryPlanIds.addAll(participants);
          expanded =
              expanded || corruptInventoryPlanIds.length != previousLength;
        }
      }
    }

    if (inventory != null) {
      for (final row in inventory.rows) {
        final participants = participantPlanIds(row);
        if (corruptOccurrenceIds.contains(row.reservationId) ||
            corruptOccurrenceIds.contains(row.occurrenceId)) {
          corruptInventoryPlanIds.addAll(participants);
        }
        if (hasTupleConflict(row) && hasOwnedParticipant(participants)) {
          corruptInventoryPlanIds.addAll(participants);
        }
      }
    }
    propagateBlockedParticipants();
    if (inventory == null || !inventory.isAuthoritative) {
      return _WholeInventoryPreparation(
        inventory: inventory,
        occurrences: occurrences,
        recoveryPlanIds: {...activePlanIds, ...corruptInventoryPlanIds},
        blockedPlanIds: corruptInventoryPlanIds,
      );
    }

    var hasConflictingIdentity = false;
    for (final row in inventory.rows) {
      final participants = participantPlanIds(row);
      if (hasTupleConflict(row)) {
        hasConflictingIdentity = true;
        if (hasOwnedParticipant(participants)) {
          corruptInventoryPlanIds.addAll(participants);
        }
      }
    }
    propagateBlockedParticipants();
    if (hasConflictingIdentity) {
      return _WholeInventoryPreparation(
        inventory: _NativeInventorySnapshot(
          rows: inventory.rows,
          isAuthoritative: false,
        ),
        occurrences: occurrences,
        recoveryPlanIds: {...activePlanIds, ...corruptInventoryPlanIds},
        blockedPlanIds: corruptInventoryPlanIds,
      );
    }

    final activeRowsByOccurrence = <String, NativeAlarmInventoryRow>{};
    for (final row in inventory.rows) {
      final participants = participantPlanIds(row);
      final isActive =
          row.status == NativeAlarmReservationStatus.scheduled ||
          row.status == NativeAlarmReservationStatus.ringing;
      if (!isActive && hasOwnedParticipant(participants)) {
        corruptInventoryPlanIds.addAll(participants);
        continue;
      }
      final decoded = originalById[row.occurrenceId];
      final isNoncanonicalRinging =
          row.status == NativeAlarmReservationStatus.ringing &&
          decoded != null &&
          desiredById[decoded.id]?.wakePlanId != decoded.wakePlanId;
      if (isNoncanonicalRinging) {
        corruptInventoryPlanIds.addAll(participants);
        continue;
      }
      if (participants.any(corruptInventoryPlanIds.contains)) {
        corruptInventoryPlanIds.addAll(participants);
        continue;
      }
      if (isActive) {
        activeRowsByOccurrence[row.occurrenceId] = row;
      }
    }
    propagateBlockedParticipants();

    final reconciledById = Map<String, AlarmOccurrence>.of(originalById);
    final changed = <AlarmOccurrence>[];
    final ownedNativeOnly = <NativeAlarmInventoryRow>[];
    final decodedOrphanIds = <String>{};
    final scheduleCanonicalPlanIds = <String>{};
    final recoveryPlanIds = <String>{...corruptInventoryPlanIds};
    final repairedPlanIds = <String>{};
    final blockedPlanIds = <String>{...corruptInventoryPlanIds};
    final persistenceErrorsByPlan = <String, String>{};

    for (final occurrence in occurrences) {
      if (corruptInventoryPlanIds.contains(occurrence.wakePlanId)) {
        continue;
      }
      final row = activeRowsByOccurrence.remove(occurrence.id);
      final isFuture = occurrence.scheduledAt.toDateTime().isAfter(now);
      final isActivePlan = activePlanIds.contains(occurrence.wakePlanId);
      final isCanonicalDesired =
          desiredById[occurrence.id]?.wakePlanId == occurrence.wakePlanId;
      AlarmOccurrence reconciled = occurrence;
      if (!isFuture) {
        continue;
      }
      if (!isActivePlan) {
        if (row != null) {
          ownedNativeOnly.add(row);
        }
        continue;
      }
      if (!isCanonicalDesired) {
        if (row != null) {
          scheduleCanonicalPlanIds.add(occurrence.wakePlanId);
          ownedNativeOnly.add(row);
          decodedOrphanIds.add(occurrence.id);
          continue;
        }
        final needsCanonicalRecovery = switch (occurrence.status) {
          AlarmOccurrenceStatus.scheduled ||
          AlarmOccurrenceStatus.ringing ||
          AlarmOccurrenceStatus.userDisablePending ||
          AlarmOccurrenceStatus.userEnablePending ||
          AlarmOccurrenceStatus.unknownPersisted => true,
          _ => false,
        };
        if (!needsCanonicalRecovery) {
          continue;
        }
        scheduleCanonicalPlanIds.add(occurrence.wakePlanId);
        reconciled = occurrence.copyWith(
          status: AlarmOccurrenceStatus.cancelled,
          platformAlarmId: null,
          failureReason: null,
          updatedAt: now,
        );
        reconciledById[occurrence.id] = reconciled;
        changed.add(reconciled);
        repairedPlanIds.add(occurrence.wakePlanId);
        continue;
      }
      if (row != null) {
        final expectsReservation = switch (occurrence.status) {
          AlarmOccurrenceStatus.scheduled ||
          AlarmOccurrenceStatus.ringing ||
          AlarmOccurrenceStatus.userDisablePending ||
          AlarmOccurrenceStatus.userEnablePending ||
          AlarmOccurrenceStatus.unknownPersisted => true,
          AlarmOccurrenceStatus.cancelled ||
          AlarmOccurrenceStatus.failed => true,
          _ => false,
        };
        if (!expectsReservation) {
          ownedNativeOnly.add(row);
          continue;
        }
        reconciled = switch (occurrence.status) {
          AlarmOccurrenceStatus.userEnablePending => occurrence.copyWith(
            status: AlarmOccurrenceStatus.scheduled,
            platformAlarmId: row.platformAlarmId,
            failureReason: null,
            updatedAt: now,
          ),
          AlarmOccurrenceStatus.cancelled ||
          AlarmOccurrenceStatus.failed => occurrence.copyWith(
            status: AlarmOccurrenceStatus.scheduled,
            platformAlarmId: row.platformAlarmId,
            failureReason: null,
            updatedAt: now,
          ),
          _ => occurrence.copyWith(
            platformAlarmId: row.platformAlarmId,
            updatedAt: now,
          ),
        };
      } else {
        reconciled = switch (occurrence.status) {
          AlarmOccurrenceStatus.scheduled => occurrence.copyWith(
            platformAlarmId: null,
            failureReason: null,
            updatedAt: now,
          ),
          AlarmOccurrenceStatus.userEnablePending => occurrence.copyWith(
            status: AlarmOccurrenceStatus.scheduled,
            platformAlarmId: null,
            failureReason: null,
            updatedAt: now,
          ),
          AlarmOccurrenceStatus.userDisablePending => occurrence.copyWith(
            status: AlarmOccurrenceStatus.userDisabled,
            platformAlarmId: null,
            failureReason: null,
            updatedAt: now,
          ),
          AlarmOccurrenceStatus.unknownPersisted => occurrence.copyWith(
            platformAlarmId: null,
            updatedAt: now,
          ),
          AlarmOccurrenceStatus.ringing => occurrence,
          _ => occurrence,
        };
      }
      if (reconciled.status != occurrence.status ||
          reconciled.platformAlarmId != occurrence.platformAlarmId) {
        reconciledById[occurrence.id] = reconciled;
        changed.add(reconciled);
        repairedPlanIds.add(occurrence.wakePlanId);
      }
    }

    for (final row in activeRowsByOccurrence.values) {
      if (participantPlanIds(row).any(blockedPlanIds.contains)) {
        continue;
      }
      final desired = desiredById[row.occurrenceId];
      if (desired != null && desired.wakePlanId == row.wakePlanId) {
        final adopted = desired.copyWith(
          platformAlarmId: row.platformAlarmId,
          updatedAt: now,
        );
        reconciledById[adopted.id] = adopted;
        changed.add(adopted);
        repairedPlanIds.add(adopted.wakePlanId);
      } else if (knownPlanIds.contains(row.wakePlanId)) {
        ownedNativeOnly.add(row);
        if (activePlanIds.contains(row.wakePlanId)) {
          scheduleCanonicalPlanIds.add(row.wakePlanId);
        }
      }
    }

    if (changed.isNotEmpty) {
      final persistenceError = await _trySaveAlarmOccurrences(changed);
      if (persistenceError != null) {
        for (final occurrence in changed) {
          recoveryPlanIds.add(occurrence.wakePlanId);
          persistenceErrorsByPlan[occurrence.wakePlanId] = persistenceError;
        }
      }
    }

    if (ownedNativeOnly.isNotEmpty) {
      CancelResult cancellation;
      var cancellationThrew = false;
      try {
        cancellation = await _nativeAlarmGateway.cancelOccurrences([
          for (final row in ownedNativeOnly)
            NativeAlarmCancelRequest(
              occurrenceId: row.occurrenceId,
              reservationId: row.reservationId,
              platformAlarmId: row.platformAlarmId,
            ),
        ]);
      } catch (_) {
        cancellationThrew = true;
        for (final row in ownedNativeOnly) {
          recoveryPlanIds.add(row.wakePlanId);
          blockedPlanIds.add(row.wakePlanId);
        }
        cancellation = CancelResult.fromRequestResults(
          requests: const [],
          results: const [],
        );
      }
      final failedKeys = cancellation.alarms
          .where((result) => !result.isSuccess)
          .map(
            (result) =>
                '${result.reservationId}/${result.occurrenceId}/${result.platformAlarmId}',
          )
          .toSet();
      final cancelledDecodedOrphans = <AlarmOccurrence>[];
      for (final row in ownedNativeOnly) {
        final key =
            '${row.reservationId}/${row.occurrenceId}/${row.platformAlarmId}';
        if (failedKeys.contains(key)) {
          recoveryPlanIds.add(row.wakePlanId);
          blockedPlanIds.add(row.wakePlanId);
        } else if (!cancellationThrew &&
            decodedOrphanIds.contains(row.occurrenceId)) {
          final occurrence = reconciledById[row.occurrenceId];
          if (occurrence != null) {
            final cancelled = occurrence.copyWith(
              status: AlarmOccurrenceStatus.cancelled,
              platformAlarmId: null,
              failureReason: null,
              updatedAt: now,
            );
            reconciledById[cancelled.id] = cancelled;
            cancelledDecodedOrphans.add(cancelled);
            repairedPlanIds.add(cancelled.wakePlanId);
          }
        }
      }
      if (cancelledDecodedOrphans.isNotEmpty) {
        final persistenceError = await _trySaveAlarmOccurrences(
          cancelledDecodedOrphans,
        );
        if (persistenceError != null) {
          for (final occurrence in cancelledDecodedOrphans) {
            recoveryPlanIds.add(occurrence.wakePlanId);
            blockedPlanIds.add(occurrence.wakePlanId);
            persistenceErrorsByPlan[occurrence.wakePlanId] = persistenceError;
          }
        }
      }
    }

    return _WholeInventoryPreparation(
      inventory: inventory,
      occurrences: reconciledById.values.toList(growable: false),
      recoveryPlanIds: recoveryPlanIds,
      repairedPlanIds: repairedPlanIds,
      blockedPlanIds: blockedPlanIds,
      scheduleCanonicalPlanIds: scheduleCanonicalPlanIds,
      persistenceErrorsByPlan: persistenceErrorsByPlan,
    );
  }

  WakePlanSchedulingResult _withInventoryRecovery(
    WakePlanSchedulingResult result,
    String? persistenceError,
  ) {
    return WakePlanSchedulingResult(
      wakePlanId: result.wakePlanId,
      status: WakePlanSchedulingStatus.recoveryRequired,
      changeState: WakePlanChangeState.recoveryRequired,
      scheduleResult: result.scheduleResult,
      cancelResult: result.cancelResult,
      occurrences: result.occurrences,
      warning: WakePlanSchedulingWarning.recoveryRequired(
        'Native alarm inventory repair is still required.',
      ),
      compensationScheduleResult: result.compensationScheduleResult,
      compensationCancelResult: result.compensationCancelResult,
      databaseState: persistenceError == null
          ? result.databaseState
          : WakePlanDatabaseState.unknown,
      persistenceError: _firstPersistenceError([
        result.persistenceError,
        persistenceError,
      ]),
    );
  }

  WakePlanSchedulingResult _inventoryRecoveryResult({
    required WakePlan plan,
    required List<AlarmOccurrence> occurrences,
    String? persistenceError,
  }) => _inventoryRecoveryResultForPlanId(
    wakePlanId: plan.id,
    occurrences: occurrences,
    persistenceError: persistenceError,
  );

  WakePlanSchedulingResult _inventoryRecoveryResultForPlanId({
    required String wakePlanId,
    required List<AlarmOccurrence> occurrences,
    String? persistenceError,
  }) {
    return WakePlanSchedulingResult(
      wakePlanId: wakePlanId,
      status: WakePlanSchedulingStatus.recoveryRequired,
      changeState: WakePlanChangeState.recoveryRequired,
      scheduleResult: ScheduleResult.fromRequestResults(
        requests: const [],
        results: const [],
      ),
      occurrences: occurrences,
      databaseState: persistenceError == null
          ? WakePlanDatabaseState.persisted
          : WakePlanDatabaseState.unknown,
      persistenceError: persistenceError,
      warning: WakePlanSchedulingWarning.recoveryRequired(
        'Native alarm inventory repair is still required.',
      ),
    );
  }

  Future<List<WakePlanSchedulingResult>> reconcile() {
    return reconcileSchedules();
  }

  Future<WakePlanSchedulingResult> editPlan(WakePlan plan) async {
    return _coordinator.run(
      () => _editPlan(plan, skipNextDate: _preserveCurrentSkipDate),
    );
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
          cancelResult.hasUnresolvedNativeState ||
          persistenceError != null ||
          !restoration.isSuccess;
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
      existingOccurrences: await _store.fetchOccurrencesForPlan(pendingPlan.id),
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
          cancelResult.hasUnresolvedNativeState ||
          persistenceError != null ||
          !restoration.isSuccess;
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

  Future<WakePlanSchedulingResult> deletePlan(String wakePlanId) {
    return _coordinator.run(() => _deletePlan(wakePlanId));
  }

  Future<WakePlanSchedulingResult> _deletePlan(String wakePlanId) async {
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
          cancelResult.hasUnresolvedNativeState ||
          persistenceError != null ||
          !restoration.isSuccess;
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

  Future<WakePlanSchedulingResult> skipNextOccurrence(WakePlan wakePlan) {
    return _coordinator.run(() => _skipNextOccurrence(wakePlan));
  }

  Future<WakePlanSchedulingResult> _skipNextOccurrence(
    WakePlan wakePlan,
  ) async {
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

  Future<WakePlanSchedulingResult> undoSkipNextOccurrence(WakePlan wakePlan) {
    return _coordinator.run(() => _undoSkipNextOccurrence(wakePlan));
  }

  Future<WakePlanSchedulingResult> _undoSkipNextOccurrence(
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
        : occurrenceBundle.requests
              .where((request) => pendingIdSet.contains(request.occurrenceId))
              .toList(growable: false);
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
    required _NativeInventorySnapshot? inventory,
    List<AlarmOccurrence>? persistedOccurrences,
    Set<String>? scheduleCandidateIds,
  }) async {
    final pendingEnableReconciliation = await _reconcilePendingEnables(
      occurrences:
          persistedOccurrences ?? await _store.fetchOccurrencesForPlan(plan.id),
      now: now,
      inventory: inventory,
    );
    final pendingDisableReconciliation = await _reconcilePendingDisables(
      occurrences: pendingEnableReconciliation.occurrences,
      now: now,
      inventory: inventory,
    );
    final existingOccurrences = pendingDisableReconciliation.occurrences;
    final existingById = {
      for (final occurrence in existingOccurrences) occurrence.id: occurrence,
    };
    final desiredBundle = _buildOccurrenceBundle(plan: plan, now: now);
    if (desiredBundle.occurrences.isEmpty) {
      if (pendingEnableReconciliation.hasUnresolved ||
          pendingDisableReconciliation.hasUnresolved) {
        return _pendingDisableRecoveryResult(
          plan: plan,
          occurrences: existingOccurrences,
          persistenceError: _firstPersistenceError([
            pendingEnableReconciliation.persistenceError,
            pendingDisableReconciliation.persistenceError,
          ]),
        );
      }
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
          if (scheduleCandidateIds != null &&
              !scheduleCandidateIds.contains(desired.id)) {
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
    final pendingRequests = desiredBundle.requests
        .where((request) => pendingIdSet.contains(request.occurrenceId))
        .toList(growable: false);

    if (pendingOccurrences.isEmpty) {
      if (pendingEnableReconciliation.hasUnresolved ||
          pendingDisableReconciliation.hasUnresolved) {
        return _pendingDisableRecoveryResult(
          plan: plan,
          occurrences: desiredBundle.occurrences
              .map((desired) => existingById[desired.id] ?? desired)
              .toList(growable: false),
          persistenceError: _firstPersistenceError([
            pendingEnableReconciliation.persistenceError,
            pendingDisableReconciliation.persistenceError,
          ]),
        );
      }
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
    final schedulePersistenceError = await _trySaveAlarmOccurrences(
      completedOccurrences,
    );
    final persistenceError = _firstPersistenceError([
      pendingEnableReconciliation.persistenceError,
      pendingDisableReconciliation.persistenceError,
      schedulePersistenceError,
    ]);

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
    final needsRecovery =
        persistenceError != null ||
        pendingEnableReconciliation.hasUnresolved ||
        pendingDisableReconciliation.hasUnresolved;
    return WakePlanSchedulingResult(
      wakePlanId: plan.id,
      status: needsRecovery
          ? WakePlanSchedulingStatus.recoveryRequired
          : hasScheduleFailure
          ? WakePlanSchedulingStatus.scheduleFailed
          : WakePlanSchedulingStatus.scheduled,
      changeState: needsRecovery
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
      warning: needsRecovery
          ? WakePlanSchedulingWarning.recoveryRequired(
              persistenceError != null
                  ? 'Reconciled alarm results could not be persisted; recovery is required.'
                  : 'An alarm state is still being reconciled; recovery is required.',
            )
          : hasScheduleFailure
          ? WakePlanSchedulingWarning.scheduleFailed(scheduleResult)
          : null,
    );
  }

  bool _isEligibleRecoveryMarker(AlarmOccurrence occurrence, DateTime now) {
    if (!occurrence.scheduledAt.toDateTime().isAfter(now)) {
      return false;
    }
    return occurrence.status == AlarmOccurrenceStatus.userDisablePending ||
        occurrence.status == AlarmOccurrenceStatus.userEnablePending ||
        (occurrence.status == AlarmOccurrenceStatus.scheduled &&
            !occurrence.hasNativeReservation);
  }

  Set<String> _canonicalFutureOccurrenceIds({
    required WakePlan plan,
    required DateTime now,
  }) {
    return _buildOccurrenceBundle(plan: plan, now: now).occurrences
        .where((occurrence) => occurrence.scheduledAt.toDateTime().isAfter(now))
        .map((occurrence) => occurrence.id)
        .toSet();
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
      AlarmOccurrenceStatus.userDisablePending => true,
      AlarmOccurrenceStatus.userEnablePending => true,
      AlarmOccurrenceStatus.unknownPersisted => true,
      _ => false,
    };
    return preservesStatus &&
        existing.wakePlanId == desired.wakePlanId &&
        existing.scheduledAt == desired.scheduledAt &&
        !existing.scheduledAt.toDateTime().isBefore(now);
  }

  Future<_PendingEnableReconciliation> _reconcilePendingEnables({
    required List<AlarmOccurrence> occurrences,
    required DateTime now,
    required _NativeInventorySnapshot? inventory,
  }) async {
    final reconciled = <AlarmOccurrence>[];
    var hasUnresolved = false;
    for (final occurrence in occurrences) {
      if (occurrence.status != AlarmOccurrenceStatus.userEnablePending ||
          !occurrence.scheduledAt.toDateTime().isAfter(now)) {
        reconciled.add(occurrence);
        continue;
      }

      final observation = _observeNativeReservationInInventory(
        occurrenceId: occurrence.id,
        wakePlanId: occurrence.wakePlanId,
        inventory: inventory,
      );
      if (!observation.isAuthoritative) {
        hasUnresolved = true;
        reconciled.add(occurrence);
        continue;
      }

      reconciled.add(
        occurrence.copyWith(
          status: AlarmOccurrenceStatus.scheduled,
          platformAlarmId: observation.activeRow?.platformAlarmId,
          failureReason: null,
          updatedAt: now,
        ),
      );
    }

    final originalById = {
      for (final occurrence in occurrences) occurrence.id: occurrence,
    };
    final changed = reconciled
        .where((occurrence) {
          final original = originalById[occurrence.id]!;
          return original.status != occurrence.status ||
              original.platformAlarmId != occurrence.platformAlarmId ||
              original.updatedAt != occurrence.updatedAt;
        })
        .toList(growable: false);
    final persistenceError = changed.isEmpty
        ? null
        : await _trySaveAlarmOccurrences(changed);
    return _PendingEnableReconciliation(
      occurrences: persistenceError == null ? reconciled : occurrences,
      hasUnresolved: hasUnresolved || persistenceError != null,
      persistenceError: persistenceError,
    );
  }

  Future<_PendingDisableReconciliation> _reconcilePendingDisables({
    required List<AlarmOccurrence> occurrences,
    required DateTime now,
    required _NativeInventorySnapshot? inventory,
  }) async {
    final reconciled = <AlarmOccurrence>[];
    var hasUnresolved = false;
    for (final occurrence in occurrences) {
      if (occurrence.status != AlarmOccurrenceStatus.userDisablePending ||
          !occurrence.scheduledAt.toDateTime().isAfter(now)) {
        reconciled.add(occurrence);
        continue;
      }

      final observation = _observeNativeReservationInInventory(
        occurrenceId: occurrence.id,
        wakePlanId: occurrence.wakePlanId,
        inventory: inventory,
      );
      if (observation.hasAmbiguousActiveRows) {
        hasUnresolved = true;
        reconciled.add(occurrence);
        continue;
      }
      if (observation.isAuthoritative && observation.activeRow == null) {
        reconciled.add(
          occurrence.copyWith(
            status: AlarmOccurrenceStatus.userDisabled,
            platformAlarmId: null,
            updatedAt: now,
          ),
        );
        continue;
      }
      final platformAlarmId =
          observation.activeRow?.platformAlarmId ?? occurrence.platformAlarmId;
      if (platformAlarmId == null) {
        hasUnresolved = true;
        reconciled.add(occurrence);
        continue;
      }

      try {
        final result = await _nativeAlarmGateway.cancelOccurrences([
          NativeAlarmCancelRequest(
            occurrenceId: occurrence.id,
            platformAlarmId: platformAlarmId,
          ),
        ]);
        if (!result.isSuccess) {
          hasUnresolved = true;
          reconciled.add(
            occurrence.copyWith(
              platformAlarmId: occurrence.platformAlarmId,
              updatedAt: now,
            ),
          );
          continue;
        }
        reconciled.add(
          occurrence.copyWith(
            status: AlarmOccurrenceStatus.userDisabled,
            platformAlarmId: null,
            updatedAt: now,
          ),
        );
      } catch (_) {
        hasUnresolved = true;
        reconciled.add(
          occurrence.copyWith(
            platformAlarmId: occurrence.platformAlarmId,
            updatedAt: now,
          ),
        );
      }
    }
    final originalById = {
      for (final occurrence in occurrences) occurrence.id: occurrence,
    };
    final changed = reconciled
        .where((occurrence) {
          final original = originalById[occurrence.id]!;
          return original.status != occurrence.status ||
              original.platformAlarmId != occurrence.platformAlarmId ||
              original.updatedAt != occurrence.updatedAt;
        })
        .toList(growable: false);
    String? persistenceError;
    if (changed.isNotEmpty) {
      persistenceError = await _trySaveAlarmOccurrences(changed);
      if (persistenceError != null) {
        hasUnresolved = true;
      }
    }
    return _PendingDisableReconciliation(
      occurrences: persistenceError == null ? reconciled : occurrences,
      hasUnresolved: hasUnresolved,
      persistenceError: persistenceError,
    );
  }

  WakePlanSchedulingResult _pendingDisableRecoveryResult({
    required WakePlan plan,
    required List<AlarmOccurrence> occurrences,
    String? persistenceError,
  }) {
    return WakePlanSchedulingResult(
      wakePlanId: plan.id,
      status: WakePlanSchedulingStatus.recoveryRequired,
      changeState: WakePlanChangeState.recoveryRequired,
      scheduleResult: ScheduleResult.fromRequestResults(
        requests: const [],
        results: const [],
      ),
      occurrences: occurrences,
      databaseState: persistenceError == null
          ? WakePlanDatabaseState.persisted
          : WakePlanDatabaseState.unknown,
      persistenceError: persistenceError,
      warning: WakePlanSchedulingWarning.recoveryRequired(
        persistenceError == null
            ? 'An alarm state is still being reconciled; recovery is required.'
            : 'The completed alarm cancellation could not be persisted; recovery is required.',
      ),
    );
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
      // Native alarms must always be strictly future. Advancing the planner's
      // boundary by the smallest DateTime unit also lets its weekly fallback
      // search run when the only occurrence in the current horizon is due now.
      now: now.add(const Duration(microseconds: 1)),
    );
    final createdOccurrences = <AlarmOccurrence>[];
    final requests = <NativeAlarmScheduleRequest>[];
    final seenScheduleTimes = <DateMinute>{};
    final createdAt = now;

    for (final instance in occurrencePlan.wakeInstances) {
      final uniqueDrafts = instance.occurrences
          .where((draft) {
            if (!draft.scheduledAt.toDateTime().isAfter(now)) {
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
    final inventory = futureReserved.isEmpty
        ? const _NativeInventorySnapshot(
            rows: <NativeAlarmInventoryRow>[],
            isAuthoritative: true,
          )
        : await _loadNativeInventory();
    final cancellableFutureReserved = <AlarmOccurrence>[];
    final cancellableIds = <String>{};
    final unresolvedWithoutId = <AlarmOccurrence>[];
    final resolvedWithoutId = <AlarmOccurrence>[];
    final discoveredPlatformIds = <String>{};
    for (final occurrence in futureReserved) {
      final observation = _observeNativeReservationInInventory(
        occurrenceId: occurrence.id,
        wakePlanId: occurrence.wakePlanId,
        inventory: inventory,
      );
      if (observation.hasAmbiguousActiveRows) {
        unresolvedWithoutId.add(occurrence);
        continue;
      }
      if (observation.isAuthoritative && observation.activeRow == null) {
        resolvedWithoutId.add(
          _resolveAuthoritativeCancellationAbsence(
            occurrence: occurrence,
            now: now,
          ),
        );
        continue;
      }
      if (occurrence.platformAlarmId != null) {
        final observedPlatformAlarmId = observation.activeRow?.platformAlarmId;
        cancellableFutureReserved.add(
          observedPlatformAlarmId == null ||
                  observedPlatformAlarmId == occurrence.platformAlarmId
              ? occurrence
              : occurrence.copyWith(
                  platformAlarmId: observedPlatformAlarmId,
                  updatedAt: now,
                ),
        );
        cancellableIds.add(occurrence.id);
        if (observedPlatformAlarmId != null &&
            observedPlatformAlarmId != occurrence.platformAlarmId) {
          discoveredPlatformIds.add(occurrence.id);
        }
        continue;
      }
      final needsConservativeCancellation =
          (occurrence.status == AlarmOccurrenceStatus.unknownPersisted ||
              occurrence.status == AlarmOccurrenceStatus.userDisablePending ||
              occurrence.status == AlarmOccurrenceStatus.userEnablePending) &&
          !occurrence.scheduledAt.toDateTime().isBefore(now) &&
          !cancellableIds.contains(occurrence.id);
      if (!needsConservativeCancellation) {
        continue;
      }
      if (occurrence.platformAlarmId != null) {
        cancellableFutureReserved.add(occurrence);
        cancellableIds.add(occurrence.id);
        continue;
      }
      final discoveredId = observation.activeRow?.platformAlarmId;
      if (discoveredId == null) {
        if (!observation.isAuthoritative) {
          unresolvedWithoutId.add(occurrence);
          continue;
        }
        resolvedWithoutId.add(
          _resolveAuthoritativeCancellationAbsence(
            occurrence: occurrence,
            now: now,
          ),
        );
        continue;
      }
      cancellableFutureReserved.add(
        occurrence.copyWith(platformAlarmId: discoveredId, updatedAt: now),
      );
      cancellableIds.add(occurrence.id);
      discoveredPlatformIds.add(occurrence.id);
    }
    final cancellation = await _cancelOccurrences(
      occurrences: List.unmodifiable(cancellableFutureReserved),
      now: now,
      usePlanCancel: usePlanCancel,
      clearPlatformIdOnFailureFor: discoveredPlatformIds,
    );
    final resolvedPersistenceError = resolvedWithoutId.isEmpty
        ? null
        : await _trySaveAlarmOccurrences(resolvedWithoutId);
    if (unresolvedWithoutId.isEmpty && resolvedWithoutId.isEmpty) {
      return cancellation;
    }
    return _CancelFutureResult(
      cancelResult: cancellation.cancelResult,
      persistedOccurrences: _mergeOccurrenceStates(
        cancellation.persistedOccurrences,
        [...resolvedWithoutId, ...unresolvedWithoutId],
      ),
      successfullyCancelledOccurrences: _mergeOccurrenceStates(
        cancellation.successfullyCancelledOccurrences,
        resolvedWithoutId
            .where(
              (occurrence) =>
                  occurrence.status == AlarmOccurrenceStatus.cancelled,
            )
            .toList(growable: false),
      ),
      databaseStateKnown:
          cancellation.databaseStateKnown && resolvedPersistenceError == null,
      hasUnresolvedNativeState:
          cancellation.hasUnresolvedNativeState ||
          unresolvedWithoutId.isNotEmpty,
      persistenceError: _firstPersistenceError([
        cancellation.persistenceError,
        resolvedPersistenceError,
      ]),
    );
  }

  AlarmOccurrence _resolveAuthoritativeCancellationAbsence({
    required AlarmOccurrence occurrence,
    required DateTime now,
  }) {
    final status = switch (occurrence.status) {
      AlarmOccurrenceStatus.userDisablePending =>
        AlarmOccurrenceStatus.userDisabled,
      AlarmOccurrenceStatus.unknownPersisted =>
        AlarmOccurrenceStatus.unknownPersisted,
      _ => AlarmOccurrenceStatus.cancelled,
    };
    return occurrence.copyWith(
      status: status,
      platformAlarmId: null,
      failureReason: null,
      updatedAt: now,
    );
  }

  Future<_CancelFutureResult> _cancelOccurrences({
    required List<AlarmOccurrence> occurrences,
    required DateTime now,
    required bool usePlanCancel,
    Set<String> clearPlatformIdOnFailureFor = const {},
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

    CancelResult cancelResult;
    var cancellationResponseUncertain = false;
    try {
      cancelResult = usePlanCancel
          ? await _nativeAlarmGateway.cancelPlan(requests)
          : await _nativeAlarmGateway.cancelOccurrences(requests);
    } catch (error) {
      cancellationResponseUncertain = true;
      cancelResult = CancelResult.fromRequestResults(
        requests: requests,
        results: [
          for (final request in requests)
            CancelAlarmResult.failure(
              occurrenceId: request.occurrenceId,
              platformAlarmId: request.platformAlarmId,
              reservationId: request.reservationId,
              reason: CancelFailureReason.nativeError,
              message: 'Native cancellation response failed: $error',
            ),
        ],
      );
    }
    final successKeys = cancelResult.alarms
        .where((alarm) => alarm.isSuccess)
        .map(_cancelKey)
        .toSet();
    final failureKeys = cancelResult.alarms
        .where((alarm) => !alarm.isSuccess)
        .map(_cancelKey)
        .toSet();
    final failedDiscoveredPlatformIds = cancellableOccurrences
        .where((occurrence) {
          if (!clearPlatformIdOnFailureFor.contains(occurrence.id)) {
            return false;
          }
          return failureKeys.contains(
            _cancelRequestKey(
              occurrenceId: occurrence.id,
              platformAlarmId: occurrence.platformAlarmId!,
            ),
          );
        })
        .map((occurrence) => occurrence.id)
        .toSet();
    final persistedOccurrences = cancellableOccurrences
        .map((occurrence) {
          final key = _cancelRequestKey(
            occurrenceId: occurrence.id,
            platformAlarmId: occurrence.platformAlarmId!,
          );
          if (successKeys.contains(key)) {
            final status = switch (occurrence.status) {
              AlarmOccurrenceStatus.unknownPersisted =>
                AlarmOccurrenceStatus.unknownPersisted,
              AlarmOccurrenceStatus.userDisablePending =>
                AlarmOccurrenceStatus.userDisabled,
              _ => AlarmOccurrenceStatus.cancelled,
            };
            return occurrence.copyWith(
              status: status,
              platformAlarmId: null,
              updatedAt: now,
            );
          }
          if (failureKeys.contains(key)) {
            final requiresInventoryRecovery =
                cancellationResponseUncertain ||
                failedDiscoveredPlatformIds.contains(occurrence.id);
            final uncertainStatus = switch (occurrence.status) {
              AlarmOccurrenceStatus.unknownPersisted =>
                AlarmOccurrenceStatus.unknownPersisted,
              AlarmOccurrenceStatus.userDisablePending =>
                AlarmOccurrenceStatus.userDisablePending,
              AlarmOccurrenceStatus.userEnablePending ||
              AlarmOccurrenceStatus.scheduled =>
                AlarmOccurrenceStatus.userEnablePending,
              _ => occurrence.status,
            };
            return occurrence.copyWith(
              status: requiresInventoryRecovery
                  ? uncertainStatus
                  : occurrence.status,
              platformAlarmId:
                  !cancellationResponseUncertain &&
                      failedDiscoveredPlatformIds.contains(occurrence.id)
                  ? null
                  : occurrence.platformAlarmId,
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
      hasUnresolvedNativeState:
          cancellationResponseUncertain ||
          failedDiscoveredPlatformIds.isNotEmpty,
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
      hasUnresolvedNativeState: cancellation.hasUnresolvedNativeState,
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

    final preservedSuppressions = occurrences
        .where(
          (occurrence) =>
              occurrence.status == AlarmOccurrenceStatus.unknownPersisted ||
              occurrence.status == AlarmOccurrenceStatus.userDisablePending ||
              occurrence.status == AlarmOccurrenceStatus.userDisabled,
        )
        .map(
          (occurrence) => occurrence.copyWith(
            status:
                occurrence.status == AlarmOccurrenceStatus.userDisablePending
                ? AlarmOccurrenceStatus.userDisabled
                : occurrence.status,
            platformAlarmId: null,
            updatedAt: now,
          ),
        )
        .toList(growable: false);
    final restorableOccurrences = occurrences
        .where(
          (occurrence) =>
              occurrence.status != AlarmOccurrenceStatus.unknownPersisted &&
              occurrence.status != AlarmOccurrenceStatus.userDisablePending &&
              occurrence.status != AlarmOccurrenceStatus.userDisabled,
        )
        .toList(growable: false);
    if (restorableOccurrences.isEmpty) {
      final persistenceError = await _trySaveAlarmOccurrences(
        preservedSuppressions,
      );
      return _RestorationResult(
        scheduleResult: null,
        occurrences: preservedSuppressions,
        databaseStateKnown: persistenceError == null,
        persistenceError: persistenceError,
      );
    }

    final pendingOccurrences = restorableOccurrences
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
      occurrences: restorableOccurrences,
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
      final mergedOccurrences = _mergeOccurrenceStates(
        preservedSuppressions,
        restoredOccurrences,
      );
      final persistenceError = await _trySaveAlarmOccurrences(
        mergedOccurrences,
      );
      return _RestorationResult(
        scheduleResult: scheduleResult,
        occurrences: mergedOccurrences,
        databaseStateKnown: persistenceError == null,
        persistenceError: persistenceError,
      );
    }
    ScheduleResult scheduleResult;
    try {
      scheduleResult = await _nativeAlarmGateway.scheduleOccurrences(
        restorationRequests,
      );
    } catch (error) {
      scheduleResult = ScheduleResult.fromOccurrences([
        for (final occurrence in pendingOccurrences)
          ScheduleOccurrenceResult.failure(
            occurrenceId: occurrence.id,
            wakePlanId: occurrence.wakePlanId,
            reason: ScheduleFailureReason.nativeError,
            message: 'Native alarm restoration response was uncertain: $error',
          ),
      ]);
      final mergedOccurrences = _mergeOccurrenceStates(
        preservedSuppressions,
        pendingOccurrences,
      );
      final persistenceError = await _trySaveAlarmOccurrences(
        mergedOccurrences,
      );
      return _RestorationResult(
        scheduleResult: scheduleResult,
        occurrences: mergedOccurrences,
        databaseStateKnown: persistenceError == null,
        persistenceError: persistenceError,
      );
    }
    final restoredOccurrences = _applyScheduleResult(
      occurrences: pendingOccurrences,
      scheduleResult: scheduleResult,
      updatedAt: now,
    );
    final mergedOccurrences = _mergeOccurrenceStates(
      preservedSuppressions,
      restoredOccurrences,
    );
    final persistenceError = await _trySaveAlarmOccurrences(mergedOccurrences);
    return _RestorationResult(
      scheduleResult: scheduleResult,
      occurrences: mergedOccurrences,
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
  Object get coordinationKey;

  Future<WakePlan?> fetchWakePlan(String id);

  Future<WakePlanReconciliationSnapshot> fetchReconciliationSnapshot({
    required DateTime now,
  });

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
  Object get coordinationKey => _repository;

  @override
  Future<WakePlan?> fetchWakePlan(String id) {
    return _repository.fetchWakePlan(id);
  }

  @override
  Future<WakePlanReconciliationSnapshot> fetchReconciliationSnapshot({
    required DateTime now,
  }) {
    return _repository.fetchReconciliationSnapshot();
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
    : isAuthoritative = true,
      hasAmbiguousActiveRows = false;

  const _NativeReservationObservation.unavailable()
    : isAuthoritative = false,
      hasAmbiguousActiveRows = false,
      activeRow = null;

  const _NativeReservationObservation.ambiguous()
    : isAuthoritative = false,
      hasAmbiguousActiveRows = true,
      activeRow = null;

  final bool isAuthoritative;
  final bool hasAmbiguousActiveRows;
  final NativeAlarmInventoryRow? activeRow;
}

class _NativeInventorySnapshot {
  const _NativeInventorySnapshot({
    required this.rows,
    required this.isAuthoritative,
  });

  final List<NativeAlarmInventoryRow> rows;
  final bool isAuthoritative;
}

class _PendingDisableReconciliation {
  const _PendingDisableReconciliation({
    required this.occurrences,
    required this.hasUnresolved,
    this.persistenceError,
  });

  final List<AlarmOccurrence> occurrences;
  final bool hasUnresolved;
  final String? persistenceError;
}

class _PendingEnableReconciliation {
  const _PendingEnableReconciliation({
    required this.occurrences,
    required this.hasUnresolved,
    this.persistenceError,
  });

  final List<AlarmOccurrence> occurrences;
  final bool hasUnresolved;
  final String? persistenceError;
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

class _WholeInventoryPreparation {
  _WholeInventoryPreparation({
    required this.inventory,
    required List<AlarmOccurrence> occurrences,
    Set<String> recoveryPlanIds = const {},
    Set<String> repairedPlanIds = const {},
    Set<String> blockedPlanIds = const {},
    Set<String> scheduleCanonicalPlanIds = const {},
    Map<String, String> persistenceErrorsByPlan = const {},
  }) : occurrencesByPlan = _groupOccurrencesByPlan(occurrences),
       recoveryPlanIds = Set.unmodifiable(recoveryPlanIds),
       repairedPlanIds = Set.unmodifiable(repairedPlanIds),
       blockedPlanIds = Set.unmodifiable(blockedPlanIds),
       scheduleCanonicalPlanIds = Set.unmodifiable(scheduleCanonicalPlanIds),
       persistenceErrorsByPlan = Map.unmodifiable(persistenceErrorsByPlan);

  final _NativeInventorySnapshot? inventory;
  final Map<String, List<AlarmOccurrence>> occurrencesByPlan;
  final Set<String> recoveryPlanIds;
  final Set<String> repairedPlanIds;
  final Set<String> blockedPlanIds;
  final Set<String> scheduleCanonicalPlanIds;
  final Map<String, String> persistenceErrorsByPlan;
}

Map<String, List<AlarmOccurrence>> _groupOccurrencesByPlan(
  List<AlarmOccurrence> occurrences,
) {
  final grouped = <String, List<AlarmOccurrence>>{};
  for (final occurrence in occurrences) {
    (grouped[occurrence.wakePlanId] ??= []).add(occurrence);
  }
  return {
    for (final entry in grouped.entries)
      entry.key: List.unmodifiable(entry.value),
  };
}

class _CancelFutureResult {
  const _CancelFutureResult({
    required this.cancelResult,
    required this.persistedOccurrences,
    required this.successfullyCancelledOccurrences,
    this.databaseStateKnown = true,
    this.hasUnresolvedNativeState = false,
    this.persistenceError,
  });

  final CancelResult cancelResult;
  final List<AlarmOccurrence> persistedOccurrences;
  final List<AlarmOccurrence> successfullyCancelledOccurrences;
  final bool databaseStateKnown;
  final bool hasUnresolvedNativeState;
  final String? persistenceError;

  bool get isSuccess =>
      cancelResult.isSuccess &&
      !hasUnresolvedNativeState &&
      persistenceError == null;

  bool get nativeCancellationComplete =>
      cancelResult.isSuccess && !hasUnresolvedNativeState;
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
                        occurrence.platformAlarmId != null ||
                    occurrence.status ==
                            AlarmOccurrenceStatus.unknownPersisted &&
                        occurrence.platformAlarmId == null ||
                    occurrence.status == AlarmOccurrenceStatus.userDisabled &&
                        occurrence.platformAlarmId == null,
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
