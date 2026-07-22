import 'dart:async';
import 'dart:io';

import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/alarm_ringing/application/alarm_ringing_controller.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

void main() {
  final monday = CalendarDay(year: 2026, month: 7, day: 6);

  test('loads ringing metadata for the current occurrence', () async {
    final store = _AlarmRingingStore(
      plans: [_plan(day: monday)],
      occurrences: [
        _occurrence(
          id: 'plan-1:20640:405',
          day: monday,
          minute: 405,
          status: AlarmOccurrenceStatus.dismissed,
          firedAt: DateTime(2026, 7, 6, 6, 45),
          dismissedAt: DateTime(2026, 7, 6, 6, 46),
        ),
        _occurrence(
          id: 'plan-1:20640:410',
          day: monday,
          minute: 410,
          status: AlarmOccurrenceStatus.ringing,
          firedAt: DateTime(2026, 7, 6, 6, 50),
        ),
        _occurrence(id: 'plan-1:20640:415', day: monday, minute: 415),
        _occurrence(id: 'plan-1:20640:420', day: monday, minute: 420),
      ],
    );

    final snapshot = await _controller(store).loadCurrentRinging();

    expect(snapshot, isNotNull);
    expect(snapshot!.wakePlan.targetTime.toString(), '07:00');
    expect(snapshot.currentOccurrence.id, 'plan-1:20640:410');
    expect(snapshot.occurrenceIndex, 2);
    expect(snapshot.occurrenceCount, 4);
    expect(snapshot.nextScheduledAt!.time.toString(), '06:55');
  });

  test(
    'loads the newest due scheduled occurrence when none is ringing',
    () async {
      final store = _AlarmRingingStore(
        plans: [_plan(day: monday)],
        occurrences: [
          _occurrence(id: 'plan-1:20640:405', day: monday, minute: 405),
          _occurrence(id: 'plan-1:20640:410', day: monday, minute: 410),
          _occurrence(id: 'plan-1:20640:415', day: monday, minute: 415),
        ],
      );

      final snapshot = await _controller(store).loadCurrentRinging();

      expect(snapshot, isNotNull);
      expect(snapshot!.currentOccurrence.id, 'plan-1:20640:410');
      expect(snapshot.occurrenceIndex, 2);
      expect(snapshot.nextScheduledAt!.time.toString(), '06:55');
    },
  );

  test(
    'ignores scheduled and ringing rows outside the bounded due window',
    () async {
      final store = _AlarmRingingStore(
        plans: [_plan(day: monday)],
        occurrences: [
          _occurrence(id: 'stale-scheduled', day: monday, minute: 390),
          _occurrence(
            id: 'stale-ringing',
            day: monday,
            minute: 394,
            status: AlarmOccurrenceStatus.ringing,
            firedAt: DateTime(2026, 7, 6, 6, 34),
          ),
          _occurrence(id: 'current', day: monday, minute: 410),
        ],
      );

      final snapshot = await _controller(store).loadCurrentRinging();

      expect(snapshot!.currentOccurrence.id, 'current');
    },
  );

  test('uses a recent delivery time for a delayed ringing alarm', () async {
    final store = _AlarmRingingStore(
      plans: [_plan(day: monday)],
      occurrences: [
        _occurrence(
          id: 'delayed-ringing',
          day: monday,
          minute: 390,
          status: AlarmOccurrenceStatus.ringing,
          firedAt: DateTime(2026, 7, 6, 6, 49),
        ),
        _occurrence(id: 'current-scheduled', day: monday, minute: 410),
      ],
    );

    final snapshot = await _controller(store).loadCurrentRinging();

    expect(snapshot!.currentOccurrence.id, 'delayed-ringing');
  });

  test(
    'uses occurrence id to deterministically break equal-time ties',
    () async {
      final store = _AlarmRingingStore(
        plans: [
          _plan(day: monday),
          _plan(id: 'plan-2', day: monday),
        ],
        occurrences: [
          _occurrence(id: 'z-current', day: monday, minute: 410),
          _occurrence(
            id: 'a-current',
            wakePlanId: 'plan-2',
            day: monday,
            minute: 410,
          ),
        ],
      );

      final snapshot = await _controller(store).loadCurrentRinging();

      expect(snapshot!.currentOccurrence.id, 'a-current');
    },
  );

  test(
    'prefers a ringing occurrence over an earlier due scheduled plan',
    () async {
      final store = _AlarmRingingStore(
        plans: [
          _plan(day: monday),
          _plan(id: 'plan-2', day: monday),
        ],
        occurrences: [
          _occurrence(
            id: 'plan-2:20640:405',
            wakePlanId: 'plan-2',
            day: monday,
            minute: 405,
          ),
          _occurrence(
            id: 'plan-1:20640:410',
            day: monday,
            minute: 410,
            status: AlarmOccurrenceStatus.ringing,
            firedAt: DateTime(2026, 7, 6, 6, 50),
          ),
        ],
      );

      final snapshot = await _controller(store).loadCurrentRinging();

      expect(snapshot, isNotNull);
      expect(snapshot!.wakePlan.id, 'plan-1');
      expect(snapshot.currentOccurrence.id, 'plan-1:20640:410');
      expect(snapshot.currentOccurrence.status, AlarmOccurrenceStatus.ringing);
    },
  );

  test(
    'dismisses only the current occurrence and keeps future alarms scheduled',
    () async {
      final gateway = FakeNativeAlarmGateway();
      final current = _occurrence(
        id: 'plan-1:20640:410',
        day: monday,
        minute: 410,
        status: AlarmOccurrenceStatus.ringing,
        platformAlarmId: 'native-current',
        firedAt: DateTime(2026, 7, 6, 6, 50),
      );
      final future = _occurrence(
        id: 'plan-1:20640:415',
        day: monday,
        minute: 415,
        platformAlarmId: 'native-future',
      );
      final store = _AlarmRingingStore(
        plans: [_plan(day: monday)],
        occurrences: [current, future],
      );

      final result = await _controller(
        store,
        gateway: gateway,
      ).dismissCurrent(current.id);

      expect(result, AlarmDismissResult.dismissed);
      expect(gateway.cancelledOccurrences.map((request) => request.idLabel), [
        'plan-1:20640:410/native-current',
      ]);
      expect(store.savedOccurrences, hasLength(1));
      expect(store.savedOccurrences.single.id, current.id);
      expect(
        store.savedOccurrences.single.status,
        AlarmOccurrenceStatus.dismissed,
      );
      expect(store.savedOccurrences.single.platformAlarmId, isNull);
      expect(
        store.occurrences[future.id]!.status,
        AlarmOccurrenceStatus.scheduled,
      );
      expect(store.occurrences[future.id]!.platformAlarmId, 'native-future');
    },
  );

  test('does not mark dismissed when native cancel fails', () async {
    final gateway = FakeNativeAlarmGateway()
      ..cancelFailurePlatformAlarmIds.add('native-current')
      ..inventoryRows.add(
        NativeAlarmInventoryRow(
          reservationId: 'plan-1:20640:410',
          occurrenceId: 'plan-1:20640:410',
          wakePlanId: 'plan-1',
          platformAlarmId: 'native-current',
          status: NativeAlarmReservationStatus.ringing,
        ),
      );
    final current = _occurrence(
      id: 'plan-1:20640:410',
      day: monday,
      minute: 410,
      status: AlarmOccurrenceStatus.ringing,
      platformAlarmId: 'native-current',
      firedAt: DateTime(2026, 7, 6, 6, 50),
    );
    final store = _AlarmRingingStore(
      plans: [_plan(day: monday)],
      occurrences: [current],
    );

    final result = await _controller(
      store,
      gateway: gateway,
    ).dismissCurrent(current.id);

    expect(result, AlarmDismissResult.nativeCancelFailed);
    expect(store.savedOccurrences, isEmpty);
    expect(
      store.occurrences[current.id]!.status,
      AlarmOccurrenceStatus.ringing,
    );

    gateway.cancelFailurePlatformAlarmIds.clear();
    expect(
      await _controller(store, gateway: gateway).dismissCurrent(current.id),
      AlarmDismissResult.dismissed,
    );
    expect(
      store.occurrences[current.id]!.status,
      AlarmOccurrenceStatus.dismissed,
    );
  });

  test('does not call native when intent persistence fails', () async {
    final gateway = FakeNativeAlarmGateway();
    final current = _occurrence(
      id: 'plan-1:20640:410',
      day: monday,
      minute: 410,
      status: AlarmOccurrenceStatus.ringing,
      platformAlarmId: 'native-current',
      firedAt: DateTime(2026, 7, 6, 6, 50),
    );
    final store = _AlarmRingingStore(
      plans: [_plan(day: monday)],
      occurrences: [current],
    )..failNextPrepareBeforeEffect = true;

    await expectLater(
      _controller(store, gateway: gateway).dismissCurrent(current.id),
      throwsStateError,
    );

    expect(gateway.cancelledOccurrences, isEmpty);
    expect(store.pendingDismissals, isEmpty);
    expect(
      store.occurrences[current.id]!.status,
      AlarmOccurrenceStatus.ringing,
    );
  });

  test(
    'retries an intent persisted before the preparation reply was lost',
    () async {
      final gateway = FakeNativeAlarmGateway();
      final current = _occurrence(
        id: 'plan-1:20640:410',
        day: monday,
        minute: 410,
        status: AlarmOccurrenceStatus.ringing,
        platformAlarmId: 'native-current',
        firedAt: DateTime(2026, 7, 6, 6, 50),
      );
      final store = _AlarmRingingStore(
        plans: [_plan(day: monday)],
        occurrences: [current],
      )..throwAfterNextPrepare = true;

      await expectLater(
        _controller(store, gateway: gateway).dismissCurrent(current.id),
        throwsStateError,
      );
      expect(gateway.cancelledOccurrences, isEmpty);
      expect(store.pendingDismissals, contains(current.id));

      final retry = AlarmRingingController(
        store: store,
        nativeAlarmGateway: gateway,
        coordinator: WakePlanMutationCoordinator(),
        clock: () => DateTime(2026, 7, 6, 7, 30),
      );
      expect(
        await retry.dismissCurrent(current.id),
        AlarmDismissResult.dismissed,
      );
      expect(
        store.occurrences[current.id]!.status,
        AlarmOccurrenceStatus.dismissed,
      );
    },
  );

  test('keeps a pre-effect native throw retryable', () async {
    final current = _occurrence(
      id: 'plan-1:20640:410',
      day: monday,
      minute: 410,
      status: AlarmOccurrenceStatus.ringing,
      platformAlarmId: 'native-current',
      firedAt: DateTime(2026, 7, 6, 6, 50),
    );
    final gateway = _ThrowingCancelGateway(throwBeforeEffect: true)
      ..inventoryRows.add(_inventoryRow(current));
    final store = _AlarmRingingStore(
      plans: [_plan(day: monday)],
      occurrences: [current],
    );

    expect(
      await _controller(store, gateway: gateway).dismissCurrent(current.id),
      AlarmDismissResult.nativeCancelFailed,
    );
    expect(store.pendingDismissals, contains(current.id));
    expect(
      store.occurrences[current.id]!.status,
      AlarmOccurrenceStatus.ringing,
    );

    expect(
      await _controller(store, gateway: gateway).dismissCurrent(current.id),
      AlarmDismissResult.dismissed,
    );
  });

  test(
    'finalizes when native cancellation side effect precedes a throw',
    () async {
      final current = _occurrence(
        id: 'plan-1:20640:410',
        day: monday,
        minute: 410,
        status: AlarmOccurrenceStatus.ringing,
        platformAlarmId: 'native-current',
        firedAt: DateTime(2026, 7, 6, 6, 50),
      );
      final gateway = _ThrowingCancelGateway(throwAfterEffect: true)
        ..inventoryRows.add(_inventoryRow(current));
      final store = _AlarmRingingStore(
        plans: [_plan(day: monday)],
        occurrences: [current],
      );

      expect(
        await _controller(store, gateway: gateway).dismissCurrent(current.id),
        AlarmDismissResult.dismissed,
      );
      expect(gateway.inventoryRows, isEmpty);
      expect(store.pendingDismissals, isEmpty);
      expect(
        store.occurrences[current.id]!.status,
        AlarmOccurrenceStatus.dismissed,
      );
    },
  );

  test(
    'retries after native success and pre-effect completion failure',
    () async {
      final current = _occurrence(
        id: 'plan-1:20640:410',
        day: monday,
        minute: 410,
        status: AlarmOccurrenceStatus.ringing,
        platformAlarmId: 'native-current',
        firedAt: DateTime(2026, 7, 6, 6, 50),
      );
      final gateway = FakeNativeAlarmGateway()
        ..inventoryRows.add(_inventoryRow(current));
      final store = _AlarmRingingStore(
        plans: [_plan(day: monday)],
        occurrences: [current],
      )..failNextCompleteBeforeEffect = true;

      await expectLater(
        _controller(store, gateway: gateway).dismissCurrent(current.id),
        throwsStateError,
      );
      expect(gateway.inventoryRows, isEmpty);
      expect(store.pendingDismissals, contains(current.id));

      expect(
        await _controller(store, gateway: gateway).dismissCurrent(current.id),
        AlarmDismissResult.dismissed,
      );
      expect(store.pendingDismissals, isEmpty);
    },
  );

  test('is idempotent when completion commits before throwing', () async {
    final current = _occurrence(
      id: 'plan-1:20640:410',
      day: monday,
      minute: 410,
      status: AlarmOccurrenceStatus.ringing,
      platformAlarmId: 'native-current',
      firedAt: DateTime(2026, 7, 6, 6, 50),
    );
    final store = _AlarmRingingStore(
      plans: [_plan(day: monday)],
      occurrences: [current],
    )..throwAfterNextComplete = true;

    await expectLater(
      _controller(store).dismissCurrent(current.id),
      throwsStateError,
    );
    expect(
      store.occurrences[current.id]!.status,
      AlarmOccurrenceStatus.dismissed,
    );
    expect(store.pendingDismissals, isEmpty);
    expect(
      await _controller(store).dismissCurrent(current.id),
      AlarmDismissResult.alreadyDismissed,
    );
  });

  test('replays an exact pending dismissal before bounded selection', () async {
    final current = _occurrence(
      id: 'plan-1:20640:410',
      day: monday,
      minute: 410,
      status: AlarmOccurrenceStatus.ringing,
      platformAlarmId: 'native-current',
      firedAt: DateTime(2026, 7, 6, 6, 50),
    );
    final gateway = FakeNativeAlarmGateway()
      ..inventoryRows.add(_inventoryRow(current));
    final store = _AlarmRingingStore(
      plans: [_plan(day: monday)],
      occurrences: [current],
    );
    store.pendingDismissals[current.id] = AlarmOccurrenceDismissalIntent(
      occurrence: current,
      requestedAt: DateTime(2026, 7, 6, 6, 50),
      platformAlarmId: current.platformAlarmId,
    );
    final controller = AlarmRingingController(
      store: store,
      nativeAlarmGateway: gateway,
      coordinator: WakePlanMutationCoordinator(),
      clock: () => DateTime(2026, 7, 6, 7, 30),
    );

    expect(await controller.loadCurrentRinging(), isNull);
    expect(
      store.occurrences[current.id]!.status,
      AlarmOccurrenceStatus.dismissed,
    );
    expect(store.pendingDismissals, isEmpty);
  });

  test(
    'reopen replays native success after Drift completion failure exactly once',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'calarm-ringing-reopen-',
      );
      final file = File('${directory.path}/wake-plan.sqlite');
      final current = _occurrence(
        id: 'plan-1:20640:410',
        day: monday,
        minute: 410,
        status: AlarmOccurrenceStatus.ringing,
        platformAlarmId: 'native-current',
        firedAt: DateTime(2026, 7, 6, 6, 50),
      );
      final future = _occurrence(
        id: 'plan-1:20640:415',
        day: monday,
        minute: 415,
        platformAlarmId: 'native-future',
      );
      final gateway = FakeNativeAlarmGateway()
        ..inventoryRows.add(_inventoryRow(current));

      var database = WakePlanDatabase(NativeDatabase(file));
      var repository = WakePlanRepository(database);
      await repository.saveWakePlan(_plan(day: monday));
      await repository.saveAlarmOccurrences([current, future]);
      final failingStore = _FailingCompleteRepositoryStore(repository);
      final controller = AlarmRingingController(
        store: failingStore,
        nativeAlarmGateway: gateway,
        coordinator: WakePlanMutationCoordinator(),
        clock: () => DateTime(2026, 7, 6, 6, 50),
      );

      await expectLater(
        controller.dismissCurrent(current.id),
        throwsStateError,
      );
      expect(gateway.inventoryRows, isEmpty);
      expect(
        await repository.fetchPendingAlarmOccurrenceDismissal(current.id),
        isNotNull,
      );
      await database.close();

      database = WakePlanDatabase(NativeDatabase(file));
      repository = WakePlanRepository(database);
      gateway.cancelFailurePlatformAlarmIds.add('native-current');
      final reopened = AlarmRingingController(
        store: AlarmRingingRepositoryStore(repository),
        nativeAlarmGateway: gateway,
        coordinator: WakePlanMutationCoordinator(),
        clock: () => DateTime(2026, 7, 6, 7, 30),
      );
      try {
        expect(await reopened.loadCurrentRinging(), isNull);
        final dismissed = await repository.fetchAlarmOccurrence(current.id);
        final untouchedFuture = await repository.fetchAlarmOccurrence(
          future.id,
        );
        expect(dismissed!.status, AlarmOccurrenceStatus.dismissed);
        expect(dismissed.platformAlarmId, isNull);
        expect(untouchedFuture!.status, AlarmOccurrenceStatus.scheduled);
        expect(untouchedFuture.platformAlarmId, 'native-future');
        expect(
          await repository.fetchPendingAlarmOccurrenceDismissals(),
          isEmpty,
        );
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('refuses to dismiss a future scheduled occurrence', () async {
    final gateway = FakeNativeAlarmGateway();
    final future = _occurrence(
      id: 'plan-1:20640:415',
      day: monday,
      minute: 415,
      platformAlarmId: 'native-future',
    );
    final store = _AlarmRingingStore(
      plans: [_plan(day: monday)],
      occurrences: [future],
    );

    final result = await _controller(
      store,
      gateway: gateway,
    ).dismissCurrent(future.id);

    expect(result, AlarmDismissResult.notRinging);
    expect(gateway.cancelledOccurrences, isEmpty);
    expect(store.savedOccurrences, isEmpty);
    expect(
      store.occurrences[future.id]!.status,
      AlarmOccurrenceStatus.scheduled,
    );
    expect(store.occurrences[future.id]!.platformAlarmId, 'native-future');
  });

  test('refuses to dismiss stale ringing outside the current window', () async {
    final gateway = FakeNativeAlarmGateway();
    final stale = _occurrence(
      id: 'stale-ringing',
      day: monday,
      minute: 390,
      status: AlarmOccurrenceStatus.ringing,
      platformAlarmId: 'native-stale',
      firedAt: DateTime(2026, 7, 6, 6, 34),
    );
    final store = _AlarmRingingStore(
      plans: [_plan(day: monday)],
      occurrences: [stale],
    );

    final result = await _controller(
      store,
      gateway: gateway,
    ).dismissCurrent(stale.id);

    expect(result, AlarmDismissResult.notRinging);
    expect(gateway.cancelledOccurrences, isEmpty);
    expect(store.savedOccurrences, isEmpty);
  });

  test(
    'dismissCurrent serializes with service mutations on the shared coordinator',
    () async {
      final coordinator = WakePlanMutationCoordinator();
      final gate = Completer<void>();
      final order = <String>[];
      final current = _occurrence(
        id: 'plan-1:20640:410',
        day: monday,
        minute: 410,
        status: AlarmOccurrenceStatus.ringing,
        platformAlarmId: 'native-current',
        firedAt: DateTime(2026, 7, 6, 6, 50),
      );
      final store = _AlarmRingingStore(
        plans: [_plan(day: monday)],
        occurrences: [current],
      );
      final controller = AlarmRingingController(
        store: store,
        nativeAlarmGateway: FakeNativeAlarmGateway(),
        clock: () => DateTime(2026, 7, 6, 6, 50),
        coordinator: coordinator,
      );

      final blockingMutation = coordinator.run(() async {
        order.add('mutation-start');
        await gate.future;
        order.add('mutation-end');
      });
      final dismissal = controller.dismissCurrent(current.id).then((result) {
        order.add('dismiss-end');
        return result;
      });

      await Future<void>.delayed(Duration.zero);
      expect(order, ['mutation-start']);

      gate.complete();
      await blockingMutation;
      final result = await dismissal;

      expect(order, ['mutation-start', 'mutation-end', 'dismiss-end']);
      expect(result, AlarmDismissResult.dismissed);
    },
  );
}

AlarmRingingController _controller(
  _AlarmRingingStore store, {
  FakeNativeAlarmGateway? gateway,
}) {
  return AlarmRingingController(
    store: store,
    nativeAlarmGateway: gateway ?? FakeNativeAlarmGateway(),
    coordinator: WakePlanMutationCoordinator(),
    clock: () => DateTime(2026, 7, 6, 6, 50),
  );
}

WakePlan _plan({String id = 'plan-1', required CalendarDay day}) {
  final createdAt = DateTime(2026, 7, 6, 5, 0);
  return WakePlan(
    id: id,
    title: 'Morning',
    targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0),
    startOffset: const Duration(minutes: 15),
    interval: const Duration(minutes: 5),
    repeatRule: RepeatRule.oneTime(day),
    isEnabled: true,
    status: WakePlanStatus.scheduled,
    soundId: defaultWakePlanSoundId,
    vibrationEnabled: true,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

AlarmOccurrence _occurrence({
  required String id,
  String wakePlanId = 'plan-1',
  required CalendarDay day,
  required int minute,
  AlarmOccurrenceStatus status = AlarmOccurrenceStatus.scheduled,
  String? platformAlarmId = 'native-alarm',
  DateTime? firedAt,
  DateTime? dismissedAt,
}) {
  final createdAt = DateTime(2026, 7, 6, 5, 0);
  return AlarmOccurrence(
    id: id,
    wakePlanId: wakePlanId,
    scheduledAt: DateMinute(
      day: day,
      time: TimeOfDayMinutes.fromMinutesSinceMidnight(minute),
    ),
    status: status,
    platformAlarmId: platformAlarmId,
    firedAt: firedAt,
    dismissedAt: dismissedAt,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

NativeAlarmInventoryRow _inventoryRow(AlarmOccurrence occurrence) {
  return NativeAlarmInventoryRow(
    reservationId: occurrence.id,
    occurrenceId: occurrence.id,
    wakePlanId: occurrence.wakePlanId,
    platformAlarmId: occurrence.platformAlarmId!,
    status: occurrence.status == AlarmOccurrenceStatus.ringing
        ? NativeAlarmReservationStatus.ringing
        : NativeAlarmReservationStatus.scheduled,
  );
}

class _ThrowingCancelGateway extends FakeNativeAlarmGateway {
  _ThrowingCancelGateway({
    this.throwBeforeEffect = false,
    this.throwAfterEffect = false,
  });

  bool throwBeforeEffect;
  bool throwAfterEffect;

  @override
  Future<CancelResult> cancelOccurrences(
    List<NativeAlarmCancelRequest> alarms,
  ) async {
    if (throwBeforeEffect) {
      throwBeforeEffect = false;
      throw StateError('native cancel failed before effect');
    }
    final result = await super.cancelOccurrences(alarms);
    if (throwAfterEffect) {
      throwAfterEffect = false;
      throw StateError('native cancel reply was lost');
    }
    return result;
  }
}

class _FailingCompleteRepositoryStore extends AlarmRingingRepositoryStore {
  _FailingCompleteRepositoryStore(super.repository);

  bool _shouldFail = true;

  @override
  Future<void> completeAlarmOccurrenceDismissal({
    required AlarmOccurrenceDismissalIntent intent,
    required DateTime dismissedAt,
  }) {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('Drift completion failed before effect');
    }
    return super.completeAlarmOccurrenceDismissal(
      intent: intent,
      dismissedAt: dismissedAt,
    );
  }
}

class _AlarmRingingStore implements AlarmRingingStore {
  _AlarmRingingStore({
    required this.plans,
    required Iterable<AlarmOccurrence> occurrences,
  }) : occurrences = {
         for (final occurrence in occurrences) occurrence.id: occurrence,
       };

  final List<WakePlan> plans;
  final Map<String, AlarmOccurrence> occurrences;
  final List<AlarmOccurrence> savedOccurrences = [];
  final Map<String, AlarmOccurrenceDismissalIntent> pendingDismissals = {};
  bool failNextPrepareBeforeEffect = false;
  bool throwAfterNextPrepare = false;
  bool failNextCompleteBeforeEffect = false;
  bool throwAfterNextComplete = false;

  @override
  Future<List<WakePlan>> fetchWakePlans({required DateTime now}) async {
    return plans;
  }

  @override
  Future<AlarmOccurrence?> fetchAlarmOccurrence(String id) async {
    return occurrences[id];
  }

  @override
  Future<List<AlarmOccurrenceDismissalIntent>>
  fetchPendingAlarmOccurrenceDismissals() async {
    return pendingDismissals.values.toList(growable: false);
  }

  @override
  Future<AlarmOccurrenceDismissalIntent?> fetchPendingAlarmOccurrenceDismissal(
    String occurrenceId,
  ) async {
    return pendingDismissals[occurrenceId];
  }

  @override
  Future<AlarmOccurrenceDismissalPreparation> prepareAlarmOccurrenceDismissal({
    required String occurrenceId,
    required String? expectedPlatformAlarmId,
    required DateTime requestedAt,
  }) async {
    if (failNextPrepareBeforeEffect) {
      failNextPrepareBeforeEffect = false;
      throw StateError('prepare failed before effect');
    }
    final pending = pendingDismissals[occurrenceId];
    if (pending != null) {
      return AlarmOccurrenceDismissalPreparation.ready(pending);
    }
    final occurrence = occurrences[occurrenceId];
    if (occurrence == null) {
      return const AlarmOccurrenceDismissalPreparation.notFound();
    }
    if (occurrence.status == AlarmOccurrenceStatus.dismissed) {
      return const AlarmOccurrenceDismissalPreparation.alreadyDismissed();
    }
    if (occurrence.platformAlarmId != expectedPlatformAlarmId ||
        (occurrence.status != AlarmOccurrenceStatus.scheduled &&
            occurrence.status != AlarmOccurrenceStatus.ringing)) {
      return const AlarmOccurrenceDismissalPreparation.noLongerEligible();
    }
    final intent = AlarmOccurrenceDismissalIntent(
      occurrence: occurrence,
      requestedAt: requestedAt,
      platformAlarmId: expectedPlatformAlarmId,
    );
    pendingDismissals[occurrenceId] = intent;
    if (throwAfterNextPrepare) {
      throwAfterNextPrepare = false;
      throw StateError('prepare threw after effect');
    }
    return AlarmOccurrenceDismissalPreparation.ready(intent);
  }

  @override
  Future<void> completeAlarmOccurrenceDismissal({
    required AlarmOccurrenceDismissalIntent intent,
    required DateTime dismissedAt,
  }) async {
    if (failNextCompleteBeforeEffect) {
      failNextCompleteBeforeEffect = false;
      throw StateError('complete failed before effect');
    }
    final occurrence = occurrences[intent.occurrence.id]!;
    final completed = occurrence.copyWith(
      status: AlarmOccurrenceStatus.dismissed,
      platformAlarmId: null,
      firedAt: occurrence.firedAt ?? intent.requestedAt,
      dismissedAt: dismissedAt,
      updatedAt: dismissedAt,
    );
    occurrences[completed.id] = completed;
    pendingDismissals.remove(completed.id);
    savedOccurrences.add(completed);
    if (throwAfterNextComplete) {
      throwAfterNextComplete = false;
      throw StateError('complete threw after effect');
    }
  }

  @override
  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(
    String wakePlanId,
  ) async {
    return occurrences.values
        .where((occurrence) => occurrence.wakePlanId == wakePlanId)
        .toList(growable: false);
  }
}

extension on NativeAlarmCancelRequest {
  String get idLabel => '$occurrenceId/$platformAlarmId';
}
