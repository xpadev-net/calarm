import '../../../core/platform/native_alarm_gateway.dart';
import '../domain/wake_plan_domain.dart';

class WakePlanNativeReservationObservation {
  const WakePlanNativeReservationObservation.authoritative({this.activeRow})
    : isAuthoritative = true,
      hasAmbiguousActiveRows = false;

  const WakePlanNativeReservationObservation.unavailable()
    : isAuthoritative = false,
      hasAmbiguousActiveRows = false,
      activeRow = null;

  const WakePlanNativeReservationObservation.ambiguous()
    : isAuthoritative = false,
      hasAmbiguousActiveRows = true,
      activeRow = null;

  final bool isAuthoritative;
  final bool hasAmbiguousActiveRows;
  final NativeAlarmInventoryRow? activeRow;
}

class WakePlanNativeInventorySnapshot {
  const WakePlanNativeInventorySnapshot({
    required this.rows,
    required this.isAuthoritative,
  });

  final List<NativeAlarmInventoryRow> rows;
  final bool isAuthoritative;
}

class WakePlanPendingDisableReconciliation {
  const WakePlanPendingDisableReconciliation({
    required this.occurrences,
    required this.hasUnresolved,
    this.persistenceError,
  });

  final List<AlarmOccurrence> occurrences;
  final bool hasUnresolved;
  final String? persistenceError;
}

class WakePlanPendingEnableReconciliation {
  const WakePlanPendingEnableReconciliation({
    required this.occurrences,
    required this.hasUnresolved,
    this.persistenceError,
  });

  final List<AlarmOccurrence> occurrences;
  final bool hasUnresolved;
  final String? persistenceError;
}

class WakePlanOccurrenceBundle {
  const WakePlanOccurrenceBundle({
    required this.occurrences,
    required this.requests,
  });

  final List<AlarmOccurrence> occurrences;
  final List<NativeAlarmScheduleRequest> requests;
}

class WakePlanWholeInventoryPreparation {
  WakePlanWholeInventoryPreparation({
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

  final WakePlanNativeInventorySnapshot? inventory;
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

class WakePlanCancelFutureResult {
  const WakePlanCancelFutureResult({
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

class WakePlanRestorationResult {
  const WakePlanRestorationResult({
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
