import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final monday = CalendarDay(year: 2026, month: 7, day: 6);
  final tuesday = CalendarDay(year: 2026, month: 7, day: 7);
  final now = DateTime(2026, 7, 6, 5, 55);
  final targetTime = TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 0);

  WakePlan buildPlan({
    String id = 'plan-1',
    TimeOfDayMinutes? targetTimeOverride,
    Duration startOffset = const Duration(minutes: 15),
    Duration interval = const Duration(minutes: 5),
    RepeatRule? repeatRule,
    String soundId = 'default',
    bool vibrationEnabled = true,
  }) {
    return WakePlan(
      id: id,
      title: 'Morning',
      targetTime: targetTimeOverride ?? targetTime,
      startOffset: startOffset,
      interval: interval,
      repeatRule: repeatRule ?? RepeatRule.oneTime(monday),
      isEnabled: true,
      status: WakePlanStatus.scheduled,
      soundId: soundId,
      vibrationEnabled: vibrationEnabled,
      createdAt: now,
      updatedAt: now,
    );
  }

  AlarmOccurrence buildOccurrence({
    required String id,
    CalendarDay? day,
    TimeOfDayMinutes? time,
    String platformAlarmId = 'native-old',
    AlarmOccurrenceStatus status = AlarmOccurrenceStatus.scheduled,
  }) {
    return AlarmOccurrence(
      id: id,
      wakePlanId: 'plan-1',
      scheduledAt: DateMinute(day: day ?? monday, time: time ?? targetTime),
      status: status,
      platformAlarmId: platformAlarmId,
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );
  }

  WakePlanService service({
    required _LoggingWakePlanServiceStore store,
    required FakeNativeAlarmGateway gateway,
    int rollingScheduleDays = 7,
  }) {
    return WakePlanService.withStore(
      store: store,
      nativeAlarmGateway: gateway,
      clock: () => now,
      rollingScheduleDays: rollingScheduleDays,
    );
  }

  group('WakePlanService createPlan', () {
    test(
      'saves plan, generates occurrences, schedules them, and persists ids',
      () async {
        final store = _LoggingWakePlanServiceStore();
        final gateway = FakeNativeAlarmGateway(
          platformAlarmIdFactory: (request) => 'native-${request.occurrenceId}',
        );

        final result = await service(
          store: store,
          gateway: gateway,
        ).createPlan(buildPlan());

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(result.changeState, WakePlanChangeState.committed);
        expect(result.warning, isNull);
        expect(store.operations, [
          'saveWakePlan:plan-1',
          'saveAlarmOccurrences:4',
          'saveAlarmOccurrences:4',
        ]);
        expect(
          gateway.scheduledRequests.map((request) => request.scheduledAt),
          [
            DateTime(2026, 7, 6, 6, 45),
            DateTime(2026, 7, 6, 6, 50),
            DateTime(2026, 7, 6, 6, 55),
            DateTime(2026, 7, 6, 7),
          ],
        );
        expect(
          store.savedOccurrences.last.map((occurrence) {
            return '${occurrence.id}:${occurrence.platformAlarmId}';
          }),
          [
            'plan-1:20640:405:native-plan-1:20640:405',
            'plan-1:20640:410:native-plan-1:20640:410',
            'plan-1:20640:415:native-plan-1:20640:415',
            'plan-1:20640:420:native-plan-1:20640:420',
          ],
        );
      },
    );

    test(
      'keeps the WakePlan and returns an inline warning when permission is missing',
      () async {
        final store = _LoggingWakePlanServiceStore();
        final gateway = FakeNativeAlarmGateway(
          capability: const NativeAlarmCapability(
            permissionStatus: NativeAlarmPermissionStatus.denied,
            canScheduleAlarms: false,
            canRequestPermission: true,
          ),
        );

        final result = await service(
          store: store,
          gateway: gateway,
        ).createPlan(buildPlan());

        expect(store.savedPlans.single.id, 'plan-1');
        expect(result.status, WakePlanSchedulingStatus.scheduleFailed);
        expect(result.changeState, WakePlanChangeState.failed);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.scheduleFailed,
        );
        expect(
          result.warning!.scheduleStatus,
          ScheduleResultStatus.permissionMissing,
        );
        expect(
          store.savedOccurrences.last.map((occurrence) => occurrence.status),
          everyElement(AlarmOccurrenceStatus.failed),
        );
      },
    );

    test(
      'does not pretend success when native schedule rows are missing',
      () async {
        final store = _LoggingWakePlanServiceStore();
        final gateway = _MissingScheduleRowsGateway();

        final result = await WakePlanService.withStore(
          store: store,
          nativeAlarmGateway: gateway,
          clock: () => now,
        ).createPlan(buildPlan());

        expect(result.status, WakePlanSchedulingStatus.scheduleFailed);
        expect(result.changeState, WakePlanChangeState.failed);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.scheduleFailed,
        );
        expect(
          store.savedOccurrences.last.map((occurrence) => occurrence.status),
          everyElement(AlarmOccurrenceStatus.failed),
        );
        expect(
          store.savedOccurrences.last.map(
            (occurrence) => occurrence.failureReason,
          ),
          everyElement(ScheduleFailureReason.nativeError.name),
        );
      },
    );

    test(
      'keeps platform-backed partial schedule failures cancellable',
      () async {
        final store = _LoggingWakePlanServiceStore();
        final gateway = FakeNativeAlarmGateway()
          ..scheduleFailureOccurrenceIds.add('plan-1:20640:410')
          ..scheduleFailureOccurrenceIdsWithPlatformAlarmIds.add(
            'plan-1:20640:410',
          );

        final result = await service(
          store: store,
          gateway: gateway,
        ).createPlan(buildPlan());

        final failedWithPlatform = result.occurrences.singleWhere(
          (occurrence) => occurrence.id == 'plan-1:20640:410',
        );

        expect(result.status, WakePlanSchedulingStatus.scheduleFailed);
        expect(failedWithPlatform.status, AlarmOccurrenceStatus.scheduled);
        expect(failedWithPlatform.platformAlarmId, 'platform-plan-1:20640:410');
        expect(failedWithPlatform.failureReason, isNull);
      },
    );

    test('does not create duplicate occurrences within a WakePlan', () async {
      final store = _LoggingWakePlanServiceStore();
      final gateway = FakeNativeAlarmGateway();
      final dailyPlan = buildPlan(
        targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
          hour: 0,
          minute: 10,
        ),
        startOffset: const Duration(minutes: 20),
        interval: const Duration(minutes: 20),
        repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
      );

      final result = await service(
        store: store,
        gateway: gateway,
        rollingScheduleDays: 2,
      ).createPlan(dailyPlan);

      expect(result.status, WakePlanSchedulingStatus.scheduled);
      final ids = result.occurrences.map((occurrence) => occurrence.id).toSet();
      expect(ids, hasLength(result.occurrences.length));
      expect(
        result.occurrences.map((occurrence) => occurrence.scheduledAt).toSet(),
        hasLength(result.occurrences.length),
      );
    });
  });

  group('WakePlanService editPlan', () {
    test(
      'persists pending plan, cancels old future alarms, then schedules new occurrences',
      () async {
        final store = _LoggingWakePlanServiceStore(currentPlan: buildPlan())
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 30),
              platformAlarmId: 'old-native-1',
            ),
            buildOccurrence(
              id: 'old-past',
              time: TimeOfDayMinutes.fromHourMinute(hour: 5, minute: 30),
              platformAlarmId: 'old-native-past',
            ),
          ];
        final gateway = FakeNativeAlarmGateway();
        final edited = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 7,
            minute: 30,
          ),
        );

        final result = await service(
          store: store,
          gateway: gateway,
        ).editPlan(edited);

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(store.operations, [
          'fetchWakePlan:plan-1',
          'saveWakePlan:plan-1',
          'fetchReservedOccurrencesForPlan:plan-1',
          'saveAlarmOccurrences:1',
          'saveAlarmOccurrences:4',
          'saveAlarmOccurrences:4',
        ]);
        expect(gateway.cancelledOccurrences.map((request) => request.idLabel), [
          'old-future-1/old-native-1',
        ]);
        expect(gateway.scheduledRequests, hasLength(4));
        expect(
          store.savedOccurrences[0].single.status,
          AlarmOccurrenceStatus.cancelled,
        );
        expect(store.savedOccurrences[0].single.platformAlarmId, isNull);
      },
    );

    test(
      'does not schedule replacements when old future alarm cancellation fails',
      () async {
        final originalPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 6,
            minute: 45,
          ),
        );
        final editedPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 7,
            minute: 30,
          ),
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = FakeNativeAlarmGateway()
          ..cancelFailurePlatformAlarmIds.add('old-native-1');

        final result = await service(
          store: store,
          gateway: gateway,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.cancelFailed);
        expect(result.changeState, WakePlanChangeState.failed);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.cancelFailed,
        );
        expect(gateway.scheduledRequests, isEmpty);
        expect(store.operations, [
          'fetchWakePlan:plan-1',
          'saveWakePlan:plan-1',
          'fetchReservedOccurrencesForPlan:plan-1',
          'saveAlarmOccurrences:1',
          'saveWakePlan:plan-1',
        ]);
        expect(store.savedPlans[0].targetTime, editedPlan.targetTime);
        expect(store.savedPlans[1].targetTime, originalPlan.targetTime);
        expect(
          store.savedOccurrences.single.single.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(
          store.savedOccurrences.single.single.platformAlarmId,
          'old-native-1',
        );
      },
    );

    test(
      'restores previous plan when replacement scheduling fails after old alarms cancel',
      () async {
        final originalPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 6,
            minute: 45,
          ),
        );
        final editedPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 7,
            minute: 30,
          ),
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = FakeNativeAlarmGateway(
          capability: const NativeAlarmCapability(
            permissionStatus: NativeAlarmPermissionStatus.denied,
            canScheduleAlarms: false,
            canRequestPermission: true,
          ),
        );

        final result = await service(
          store: store,
          gateway: gateway,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.scheduleFailed);
        expect(result.changeState, WakePlanChangeState.failed);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.scheduleFailed,
        );
        expect(gateway.cancelledOccurrences.map((request) => request.idLabel), [
          'old-future-1/old-native-1',
        ]);
        expect(gateway.scheduledRequests, hasLength(4));
        expect(store.operations, [
          'fetchWakePlan:plan-1',
          'saveWakePlan:plan-1',
          'fetchReservedOccurrencesForPlan:plan-1',
          'saveAlarmOccurrences:1',
          'saveAlarmOccurrences:4',
          'saveAlarmOccurrences:4',
          'saveWakePlan:plan-1',
        ]);
        expect(store.savedPlans[0].targetTime, editedPlan.targetTime);
        expect(store.savedPlans[1].targetTime, originalPlan.targetTime);
        expect(store.currentPlan!.targetTime, originalPlan.targetTime);
        expect(
          store.savedOccurrences[0].single.status,
          AlarmOccurrenceStatus.cancelled,
        );
        expect(store.savedOccurrences[0].single.platformAlarmId, isNull);
        expect(
          store.savedOccurrences.last.map((occurrence) => occurrence.status),
          everyElement(AlarmOccurrenceStatus.failed),
        );
      },
    );
  });

  group('WakePlanService deletePlan', () {
    test('cancels future occurrences and marks the WakePlan deleted', () async {
      final store = _LoggingWakePlanServiceStore()
        ..reservedOccurrences = [
          buildOccurrence(id: 'future-1', platformAlarmId: 'native-1'),
          buildOccurrence(
            id: 'past-1',
            time: TimeOfDayMinutes.fromHourMinute(hour: 5, minute: 30),
            platformAlarmId: 'native-past',
          ),
          buildOccurrence(
            id: 'tomorrow-1',
            day: tuesday,
            platformAlarmId: 'native-tomorrow',
          ),
        ];
      final gateway = FakeNativeAlarmGateway();

      final result = await service(
        store: store,
        gateway: gateway,
      ).deletePlan('plan-1');

      expect(result.status, WakePlanSchedulingStatus.deleted);
      expect(store.operations, [
        'fetchReservedOccurrencesForPlan:plan-1',
        'saveAlarmOccurrences:2',
        'softDeleteWakePlan:plan-1',
      ]);
      expect(gateway.cancelledPlans.map((request) => request.idLabel), [
        'future-1/native-1',
        'tomorrow-1/native-tomorrow',
      ]);
      expect(store.deletedPlanIds, ['plan-1']);
      expect(
        store.savedOccurrences.single.map((occurrence) => occurrence.status),
        everyElement(AlarmOccurrenceStatus.cancelled),
      );
    });

    test('keeps the WakePlan when delete cancellation fails', () async {
      final store = _LoggingWakePlanServiceStore()
        ..reservedOccurrences = [
          buildOccurrence(id: 'future-1', platformAlarmId: 'native-1'),
        ];
      final gateway = FakeNativeAlarmGateway()
        ..cancelFailurePlatformAlarmIds.add('native-1');

      final result = await service(
        store: store,
        gateway: gateway,
      ).deletePlan('plan-1');

      expect(result.status, WakePlanSchedulingStatus.cancelFailed);
      expect(result.changeState, WakePlanChangeState.failed);
      expect(store.operations, [
        'fetchReservedOccurrencesForPlan:plan-1',
        'saveAlarmOccurrences:1',
      ]);
      expect(store.deletedPlanIds, isEmpty);
      expect(
        store.savedOccurrences.single.single.status,
        AlarmOccurrenceStatus.scheduled,
      );
      expect(store.savedOccurrences.single.single.platformAlarmId, 'native-1');
    });
  });
}

class _LoggingWakePlanServiceStore implements WakePlanServiceStore {
  _LoggingWakePlanServiceStore({this.currentPlan});

  final operations = <String>[];
  final savedPlans = <WakePlan>[];
  final savedOccurrences = <List<AlarmOccurrence>>[];
  final deletedPlanIds = <String>[];
  WakePlan? currentPlan;
  List<AlarmOccurrence> reservedOccurrences = [];

  @override
  Future<WakePlan?> fetchWakePlan(String id) async {
    operations.add('fetchWakePlan:$id');
    return currentPlan?.id == id ? currentPlan : null;
  }

  @override
  Future<void> saveWakePlan(WakePlan plan) async {
    operations.add('saveWakePlan:${plan.id}');
    savedPlans.add(plan);
    currentPlan = plan;
  }

  @override
  Future<void> softDeleteWakePlan({
    required String id,
    required DateTime updatedAt,
  }) async {
    operations.add('softDeleteWakePlan:$id');
    deletedPlanIds.add(id);
  }

  @override
  Future<void> saveAlarmOccurrences(
    Iterable<AlarmOccurrence> occurrences,
  ) async {
    final snapshot = occurrences.toList(growable: false);
    operations.add('saveAlarmOccurrences:${snapshot.length}');
    savedOccurrences.add(snapshot);
  }

  @override
  Future<List<AlarmOccurrence>> fetchReservedOccurrencesForPlan(
    String wakePlanId,
  ) async {
    operations.add('fetchReservedOccurrencesForPlan:$wakePlanId');
    return reservedOccurrences
        .where((occurrence) => occurrence.wakePlanId == wakePlanId)
        .toList(growable: false);
  }
}

extension on NativeAlarmCancelRequest {
  String get idLabel => '$occurrenceId/$platformAlarmId';
}

class _MissingScheduleRowsGateway extends FakeNativeAlarmGateway {
  @override
  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  ) async {
    scheduledRequests.addAll(occurrences);
    return ScheduleResult.fromOccurrences(const []);
  }
}
