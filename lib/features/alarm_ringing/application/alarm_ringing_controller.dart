import '../../../core/platform/native_alarm_gateway.dart';
import '../../../core/time/time.dart';
import '../../wake_plan/application/wake_plan_service.dart';
import '../../wake_plan/data/wake_plan_data.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';

typedef AlarmRingingClock = DateTime Function();

class AlarmRingingController {
  AlarmRingingController({
    required this.store,
    required this.nativeAlarmGateway,
    required this.coordinator,
    AlarmRingingClock? clock,
  }) : _clock = clock ?? DateTime.now;

  final AlarmRingingStore store;
  final NativeAlarmGateway nativeAlarmGateway;
  final WakePlanMutationCoordinator coordinator;
  final AlarmRingingClock _clock;

  Future<AlarmRingingSnapshot?> loadCurrentRinging() async {
    final now = _clock();
    final plans = await store.fetchWakePlans(now: now);
    final snapshots = <AlarmRingingSnapshot>[];

    for (final plan in plans) {
      final occurrences = await store.fetchOccurrencesForPlan(plan.id);
      final active = _selectActiveOccurrence(occurrences, now);
      if (active == null) {
        continue;
      }
      snapshots.add(
        _snapshotFor(plan: plan, current: active, occurrences: occurrences),
      );
    }

    snapshots.sort((left, right) {
      final priorityComparison = _activePriority(
        left.currentOccurrence,
      ).compareTo(_activePriority(right.currentOccurrence));
      if (priorityComparison != 0) {
        return priorityComparison;
      }
      return left.currentOccurrence.scheduledAt.compareTo(
        right.currentOccurrence.scheduledAt,
      );
    });
    return snapshots.firstOrNull;
  }

  Future<AlarmDismissResult> dismissCurrent(String occurrenceId) {
    return coordinator.run(() => _dismissCurrent(occurrenceId));
  }

  Future<AlarmDismissResult> _dismissCurrent(String occurrenceId) async {
    final occurrence = await store.fetchAlarmOccurrence(occurrenceId);
    if (occurrence == null) {
      return AlarmDismissResult.notFound;
    }
    if (occurrence.status == AlarmOccurrenceStatus.dismissed) {
      return AlarmDismissResult.alreadyDismissed;
    }

    final now = _clock();
    if (!_isDismissibleCurrentOccurrence(occurrence, now)) {
      return AlarmDismissResult.notRinging;
    }

    final platformAlarmId = occurrence.platformAlarmId;
    if (platformAlarmId != null) {
      final cancelResult = await nativeAlarmGateway.cancelOccurrences([
        NativeAlarmCancelRequest(
          occurrenceId: occurrence.id,
          platformAlarmId: platformAlarmId,
        ),
      ]);
      if (!cancelResult.isSuccess) {
        return AlarmDismissResult.nativeCancelFailed;
      }
    }

    await store.saveAlarmOccurrences([
      occurrence.copyWith(
        status: AlarmOccurrenceStatus.dismissed,
        platformAlarmId: null,
        firedAt: occurrence.firedAt ?? now,
        dismissedAt: now,
        updatedAt: now,
      ),
    ]);
    return AlarmDismissResult.dismissed;
  }

  bool _isDismissibleCurrentOccurrence(
    AlarmOccurrence occurrence,
    DateTime now,
  ) {
    if (occurrence.status == AlarmOccurrenceStatus.ringing) {
      return true;
    }
    return occurrence.status == AlarmOccurrenceStatus.scheduled &&
        !occurrence.scheduledAt.toDateTime().isAfter(now);
  }

  AlarmOccurrence? _selectActiveOccurrence(
    List<AlarmOccurrence> occurrences,
    DateTime now,
  ) {
    final ringing = occurrences
        .where(
          (occurrence) => occurrence.status == AlarmOccurrenceStatus.ringing,
        )
        .toList(growable: false);
    if (ringing.isNotEmpty) {
      ringing.sort(
        (left, right) => left.scheduledAt.compareTo(right.scheduledAt),
      );
      return ringing.first;
    }

    final dueScheduled = occurrences
        .where(
          (occurrence) =>
              occurrence.status == AlarmOccurrenceStatus.scheduled &&
              !occurrence.scheduledAt.toDateTime().isAfter(now),
        )
        .toList(growable: false);
    if (dueScheduled.isEmpty) {
      return null;
    }
    dueScheduled.sort(
      (left, right) => left.scheduledAt.compareTo(right.scheduledAt),
    );
    return dueScheduled.first;
  }

  int _activePriority(AlarmOccurrence occurrence) {
    return occurrence.status == AlarmOccurrenceStatus.ringing ? 0 : 1;
  }

  AlarmRingingSnapshot _snapshotFor({
    required WakePlan plan,
    required AlarmOccurrence current,
    required List<AlarmOccurrence> occurrences,
  }) {
    final sorted = [...occurrences]
      ..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));
    final currentIndex = sorted.indexWhere(
      (occurrence) => occurrence.id == current.id,
    );
    final nextScheduled = sorted
        .where(
          (occurrence) =>
              occurrence.status == AlarmOccurrenceStatus.scheduled &&
              occurrence.scheduledAt.compareTo(current.scheduledAt) > 0,
        )
        .firstOrNull;

    return AlarmRingingSnapshot(
      wakePlan: plan,
      currentOccurrence: current,
      occurrenceIndex: currentIndex < 0 ? 1 : currentIndex + 1,
      occurrenceCount: sorted.length,
      nextScheduledAt: nextScheduled?.scheduledAt,
    );
  }
}

abstract class AlarmRingingStore {
  Future<List<WakePlan>> fetchWakePlans({required DateTime now});

  Future<AlarmOccurrence?> fetchAlarmOccurrence(String id);

  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(String wakePlanId);

  Future<void> saveAlarmOccurrences(Iterable<AlarmOccurrence> occurrences);
}

class AlarmRingingRepositoryStore implements AlarmRingingStore {
  AlarmRingingRepositoryStore(this._repository);

  final WakePlanRepository _repository;

  @override
  Future<List<WakePlan>> fetchWakePlans({required DateTime now}) {
    return _repository.fetchWakePlans(now: now);
  }

  @override
  Future<AlarmOccurrence?> fetchAlarmOccurrence(String id) {
    return _repository.fetchAlarmOccurrence(id);
  }

  @override
  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(String wakePlanId) {
    return _repository.fetchOccurrencesForPlan(wakePlanId);
  }

  @override
  Future<void> saveAlarmOccurrences(Iterable<AlarmOccurrence> occurrences) {
    return _repository.saveAlarmOccurrences(occurrences);
  }
}

class AlarmRingingSnapshot {
  const AlarmRingingSnapshot({
    required this.wakePlan,
    required this.currentOccurrence,
    required this.occurrenceIndex,
    required this.occurrenceCount,
    required this.nextScheduledAt,
  });

  final WakePlan wakePlan;
  final AlarmOccurrence currentOccurrence;
  final int occurrenceIndex;
  final int occurrenceCount;
  final DateMinute? nextScheduledAt;
}

enum AlarmDismissResult {
  dismissed,
  alreadyDismissed,
  notFound,
  notRinging,
  nativeCancelFailed,
}
