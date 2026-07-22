import '../../../core/platform/native_alarm_gateway.dart';
import '../../../core/time/time.dart';
import '../../wake_plan/application/wake_plan_service.dart';
import '../../wake_plan/data/wake_plan_data.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';

typedef AlarmRingingClock = DateTime Function();

class AlarmRingingController {
  /// Only alarms due during this recent window can be surfaced or dismissed.
  /// The newest due occurrence wins ties before the stable occurrence id.
  static const Duration currentAlarmDueWindow = Duration(minutes: 15);

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
    await coordinator.run(_replayPendingDismissals);
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
      return _compareCurrentOccurrences(
        left.currentOccurrence,
        right.currentOccurrence,
      );
    });
    return snapshots.firstOrNull;
  }

  Future<AlarmDismissResult> dismissCurrent(String occurrenceId) {
    return coordinator.run(() => _dismissCurrent(occurrenceId));
  }

  Future<AlarmDismissResult> _dismissCurrent(String occurrenceId) async {
    final pending = await store.fetchPendingAlarmOccurrenceDismissal(
      occurrenceId,
    );
    if (pending != null) {
      if (pending.occurrence.platformAlarmId == pending.platformAlarmId) {
        return _completePendingDismissal(pending);
      }
      return _completePreparation(
        await store.prepareAlarmOccurrenceDismissal(
          occurrenceId: pending.occurrence.id,
          expectedPlatformAlarmId: pending.occurrence.platformAlarmId,
          requestedAt: _clock(),
        ),
      );
    }

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

    final preparation = await store.prepareAlarmOccurrenceDismissal(
      occurrenceId: occurrence.id,
      expectedPlatformAlarmId: occurrence.platformAlarmId,
      requestedAt: now,
    );
    return _completePreparation(preparation);
  }

  Future<AlarmDismissResult> _completePreparation(
    AlarmOccurrenceDismissalPreparation preparation,
  ) async {
    switch (preparation.status) {
      case AlarmOccurrenceDismissalPreparationStatus.ready:
        return _completePendingDismissal(preparation.intent!);
      case AlarmOccurrenceDismissalPreparationStatus.notFound:
        return AlarmDismissResult.notFound;
      case AlarmOccurrenceDismissalPreparationStatus.alreadyDismissed:
        return AlarmDismissResult.alreadyDismissed;
      case AlarmOccurrenceDismissalPreparationStatus.noLongerEligible:
        return AlarmDismissResult.notRinging;
    }
  }

  Future<void> _replayPendingDismissals() async {
    final pending = await store.fetchPendingAlarmOccurrenceDismissals();
    for (final intent in pending) {
      try {
        await _completePendingDismissal(intent);
      } catch (_) {
        // Keep a failed intent durable without preventing later exact intents
        // from being replayed during the same load.
      }
    }
  }

  Future<AlarmDismissResult> _completePendingDismissal(
    AlarmOccurrenceDismissalIntent intent,
  ) async {
    if (!await _cancelledOrAuthoritativelyAbsent(intent)) {
      return AlarmDismissResult.nativeCancelFailed;
    }
    await store.completeAlarmOccurrenceDismissal(
      intent: intent,
      dismissedAt: _clock(),
    );
    return AlarmDismissResult.dismissed;
  }

  Future<bool> _cancelledOrAuthoritativelyAbsent(
    AlarmOccurrenceDismissalIntent intent,
  ) async {
    final platformAlarmId = intent.platformAlarmId;
    if (platformAlarmId == null) {
      return true;
    }
    final request = NativeAlarmCancelRequest(
      occurrenceId: intent.occurrence.id,
      platformAlarmId: platformAlarmId,
    );
    try {
      final cancelResult = await nativeAlarmGateway.cancelOccurrences([
        request,
      ]);
      if (cancelResult.isSuccess) {
        return true;
      }
    } catch (_) {
      // A lost reply can follow a completed native cancellation. Authoritative
      // inventory below distinguishes that case from a pre-effect failure.
    }

    try {
      final inventory = await nativeAlarmGateway.getInventory();
      if (!inventory.isSuccess) {
        return false;
      }
      return !inventory.rows.any(
        (row) =>
            row.reservationId == request.reservationId ||
            row.occurrenceId == request.occurrenceId ||
            row.platformAlarmId == request.platformAlarmId,
      );
    } catch (_) {
      return false;
    }
  }

  bool _isDismissibleCurrentOccurrence(
    AlarmOccurrence occurrence,
    DateTime now,
  ) {
    if (occurrence.status == AlarmOccurrenceStatus.ringing) {
      return _isWithinCurrentDueWindow(occurrence, now);
    }
    return occurrence.status == AlarmOccurrenceStatus.scheduled &&
        _isWithinCurrentDueWindow(occurrence, now);
  }

  AlarmOccurrence? _selectActiveOccurrence(
    List<AlarmOccurrence> occurrences,
    DateTime now,
  ) {
    final ringing = occurrences
        .where(
          (occurrence) =>
              occurrence.status == AlarmOccurrenceStatus.ringing &&
              _isWithinCurrentDueWindow(occurrence, now),
        )
        .toList(growable: false);
    if (ringing.isNotEmpty) {
      ringing.sort(_compareCurrentOccurrences);
      return ringing.first;
    }

    final dueScheduled = occurrences
        .where(
          (occurrence) =>
              occurrence.status == AlarmOccurrenceStatus.scheduled &&
              _isWithinCurrentDueWindow(occurrence, now),
        )
        .toList(growable: false);
    if (dueScheduled.isEmpty) {
      return null;
    }
    dueScheduled.sort(_compareCurrentOccurrences);
    return dueScheduled.first;
  }

  int _activePriority(AlarmOccurrence occurrence) {
    return occurrence.status == AlarmOccurrenceStatus.ringing ? 0 : 1;
  }

  bool _isWithinCurrentDueWindow(AlarmOccurrence occurrence, DateTime now) {
    final activeAt = occurrence.status == AlarmOccurrenceStatus.ringing
        ? occurrence.firedAt!
        : occurrence.scheduledAt.toDateTime();
    return !activeAt.isAfter(now) &&
        !activeAt.isBefore(now.subtract(currentAlarmDueWindow));
  }

  int _compareCurrentOccurrences(AlarmOccurrence left, AlarmOccurrence right) {
    final leftActiveAt = left.status == AlarmOccurrenceStatus.ringing
        ? left.firedAt!
        : left.scheduledAt.toDateTime();
    final rightActiveAt = right.status == AlarmOccurrenceStatus.ringing
        ? right.firedAt!
        : right.scheduledAt.toDateTime();
    final activeComparison = rightActiveAt.compareTo(leftActiveAt);
    return activeComparison != 0
        ? activeComparison
        : left.id.compareTo(right.id);
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

  Future<List<AlarmOccurrenceDismissalIntent>>
  fetchPendingAlarmOccurrenceDismissals();

  Future<AlarmOccurrenceDismissalIntent?> fetchPendingAlarmOccurrenceDismissal(
    String occurrenceId,
  );

  Future<AlarmOccurrenceDismissalPreparation> prepareAlarmOccurrenceDismissal({
    required String occurrenceId,
    required String? expectedPlatformAlarmId,
    required DateTime requestedAt,
  });

  Future<void> completeAlarmOccurrenceDismissal({
    required AlarmOccurrenceDismissalIntent intent,
    required DateTime dismissedAt,
  });

  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(String wakePlanId);
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
  Future<List<AlarmOccurrenceDismissalIntent>>
  fetchPendingAlarmOccurrenceDismissals() {
    return _repository.fetchPendingAlarmOccurrenceDismissals();
  }

  @override
  Future<AlarmOccurrenceDismissalIntent?> fetchPendingAlarmOccurrenceDismissal(
    String occurrenceId,
  ) {
    return _repository.fetchPendingAlarmOccurrenceDismissal(occurrenceId);
  }

  @override
  Future<AlarmOccurrenceDismissalPreparation> prepareAlarmOccurrenceDismissal({
    required String occurrenceId,
    required String? expectedPlatformAlarmId,
    required DateTime requestedAt,
  }) {
    return _repository.prepareAlarmOccurrenceDismissal(
      occurrenceId: occurrenceId,
      expectedPlatformAlarmId: expectedPlatformAlarmId,
      requestedAt: requestedAt,
    );
  }

  @override
  Future<void> completeAlarmOccurrenceDismissal({
    required AlarmOccurrenceDismissalIntent intent,
    required DateTime dismissedAt,
  }) {
    return _repository.completeAlarmOccurrenceDismissal(
      intent: intent,
      dismissedAt: dismissedAt,
    );
  }

  @override
  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(String wakePlanId) {
    return _repository.fetchOccurrencesForPlan(wakePlanId);
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
