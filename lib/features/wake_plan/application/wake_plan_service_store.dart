import '../data/wake_plan_data.dart';
import '../domain/wake_plan_domain.dart';

abstract class WakePlanServiceStore {
  Future<WakePlan?> fetchWakePlan(String id);

  Future<WakePlanReconciliationSnapshot> fetchReconciliationSnapshot({
    required DateTime now,
  });

  Future<AlarmOccurrencePlatformMatchSnapshot>
  fetchAlarmOccurrencesByPlatformAlarmIds(Set<String> platformAlarmIds);

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
  Future<WakePlanReconciliationSnapshot> fetchReconciliationSnapshot({
    required DateTime now,
  }) {
    return _repository.fetchReconciliationSnapshot(now: now);
  }

  @override
  Future<AlarmOccurrencePlatformMatchSnapshot>
  fetchAlarmOccurrencesByPlatformAlarmIds(Set<String> platformAlarmIds) {
    return _repository.fetchAlarmOccurrencesByPlatformAlarmIds(
      platformAlarmIds,
    );
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
