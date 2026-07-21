import 'dart:async';

import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/alarm_ringing/application/alarm_ringing_controller.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter_test/flutter_test.dart';

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
    'loads the earliest past-due scheduled occurrence when none is ringing',
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
      expect(snapshot!.currentOccurrence.id, 'plan-1:20640:405');
      expect(snapshot.occurrenceIndex, 1);
      expect(snapshot.nextScheduledAt!.time.toString(), '06:50');
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
      ..cancelFailurePlatformAlarmIds.add('native-current');
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
  });

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

  @override
  Future<List<WakePlan>> fetchWakePlans({required DateTime now}) async {
    return plans;
  }

  @override
  Future<AlarmOccurrence?> fetchAlarmOccurrence(String id) async {
    return occurrences[id];
  }

  @override
  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(
    String wakePlanId,
  ) async {
    return occurrences.values
        .where((occurrence) => occurrence.wakePlanId == wakePlanId)
        .toList(growable: false);
  }

  @override
  Future<void> saveAlarmOccurrences(
    Iterable<AlarmOccurrence> occurrences,
  ) async {
    for (final occurrence in occurrences) {
      savedOccurrences.add(occurrence);
      this.occurrences[occurrence.id] = occurrence;
    }
  }
}

extension on NativeAlarmCancelRequest {
  String get idLabel => '$occurrenceId/$platformAlarmId';
}
