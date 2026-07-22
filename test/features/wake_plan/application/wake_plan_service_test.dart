import 'dart:async';
import 'dart:io';

import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/application/occurrence_planner.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final monday = CalendarDay(year: 2026, month: 7, day: 6);
  final tuesday = CalendarDay(year: 2026, month: 7, day: 7);
  final wednesday = CalendarDay(year: 2026, month: 7, day: 8);
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
    bool isEnabled = true,
    WakePlanStatus status = WakePlanStatus.scheduled,
    CalendarDay? skipNextDate,
  }) {
    return WakePlan(
      id: id,
      title: 'Morning',
      targetTime: targetTimeOverride ?? targetTime,
      startOffset: startOffset,
      interval: interval,
      repeatRule: repeatRule ?? RepeatRule.oneTime(monday),
      isEnabled: isEnabled,
      status: status,
      skipNextDate: skipNextDate,
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
    String? platformAlarmId = 'native-old',
    AlarmOccurrenceStatus status = AlarmOccurrenceStatus.scheduled,
    DateTime? firedAt,
    DateTime? dismissedAt,
    String? failureReason,
    String? reservationId,
    int reservationGeneration = 0,
  }) {
    return AlarmOccurrence(
      id: id,
      wakePlanId: 'plan-1',
      scheduledAt: DateMinute(day: day ?? monday, time: time ?? targetTime),
      status: status,
      platformAlarmId: platformAlarmId,
      firedAt: firedAt,
      dismissedAt: dismissedAt,
      failureReason: failureReason,
      reservationId: reservationId,
      reservationGeneration: reservationGeneration,
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );
  }

  NativeAlarmInventoryRow inventoryRow(
    AlarmOccurrence occurrence, {
    required String platformAlarmId,
  }) {
    return NativeAlarmInventoryRow(
      reservationId: occurrence.reservationId,
      occurrenceId: occurrence.id,
      wakePlanId: occurrence.wakePlanId,
      platformAlarmId: platformAlarmId,
      status: NativeAlarmReservationStatus.scheduled,
      reservationGeneration: occurrence.reservationGeneration,
    );
  }

  T withUnavailableInventory<T extends FakeNativeAlarmGateway>(T gateway) {
    gateway.capability = const NativeAlarmCapability(
      permissionStatus: NativeAlarmPermissionStatus.authorized,
      canScheduleAlarms: true,
      canRequestPermission: true,
      supportsInventory: false,
    );
    return gateway;
  }

  WakePlanService service({
    required _LoggingWakePlanServiceStore store,
    required FakeNativeAlarmGateway gateway,
    int rollingScheduleDays = 7,
    DateTime? clockNow,
    OccurrencePlanner occurrencePlanner = const OccurrencePlanner(),
    WakePlanMutationCoordinator? coordinator,
  }) {
    return WakePlanService.withStore(
      store: store,
      nativeAlarmGateway: gateway,
      occurrencePlanner: occurrencePlanner,
      clock: () => clockNow ?? now,
      rollingScheduleDays: rollingScheduleDays,
      coordinator: coordinator ?? WakePlanMutationCoordinator(),
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
          'fetchOccurrencesForPlan:plan-1',
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
          coordinator: WakePlanMutationCoordinator(),
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

    test('retries a full failure without creating a second plan', () async {
      final store = _LoggingWakePlanServiceStore();
      final gateway = FakeNativeAlarmGateway(
        capability: const NativeAlarmCapability(
          permissionStatus: NativeAlarmPermissionStatus.denied,
          canScheduleAlarms: false,
          canRequestPermission: true,
        ),
      );
      final serviceUnderTest = service(store: store, gateway: gateway);

      final first = await serviceUnderTest.createPlan(buildPlan());
      gateway.capability = const NativeAlarmCapability(
        permissionStatus: NativeAlarmPermissionStatus.authorized,
        canScheduleAlarms: true,
        canRequestPermission: true,
      );
      final retry = await serviceUnderTest.createPlan(buildPlan());

      expect(first.status, WakePlanSchedulingStatus.scheduleFailed);
      expect(retry.status, WakePlanSchedulingStatus.scheduled);
      expect(store.savedPlans.map((plan) => plan.id).toSet(), {'plan-1'});
      expect(store.storedOccurrences, hasLength(4));
      expect(
        store.storedOccurrences.every(
          (occurrence) => occurrence.status == AlarmOccurrenceStatus.scheduled,
        ),
        isTrue,
      );
      expect(gateway.scheduledRequests, hasLength(8));
    });

    test(
      'retries only missing occurrences after a partial native failure',
      () async {
        final store = _LoggingWakePlanServiceStore();
        final gateway = FakeNativeAlarmGateway()
          ..scheduleFailureOccurrenceIds.add('plan-1:20640:410');
        final serviceUnderTest = service(store: store, gateway: gateway);

        final first = await serviceUnderTest.createPlan(buildPlan());
        expect(
          store.storedOccurrences
              .singleWhere((occurrence) => occurrence.id == 'plan-1:20640:410')
              .platformAlarmId,
          isNull,
        );
        gateway.scheduleFailureOccurrenceIds.clear();
        gateway.scheduleFailureOccurrenceIdsWithPlatformAlarmIds.clear();
        final retry = await serviceUnderTest.createPlan(buildPlan());

        expect(first.status, WakePlanSchedulingStatus.scheduleFailed);
        expect(retry.status, WakePlanSchedulingStatus.scheduled);
        expect(gateway.scheduledRequests, hasLength(5));
        expect(
          gateway.scheduledRequests
              .skip(4)
              .map((request) => request.occurrenceId),
          ['plan-1:20640:410'],
        );
        expect(store.storedOccurrences, hasLength(4));
        expect(
          store.storedOccurrences.every(
            (occurrence) => occurrence.platformAlarmId != null,
          ),
          isTrue,
        );
      },
    );

    test(
      'does not trust inactive persisted occurrence reservations on retry',
      () async {
        for (final status in [
          AlarmOccurrenceStatus.failed,
          AlarmOccurrenceStatus.cancelled,
          AlarmOccurrenceStatus.expired,
        ]) {
          final store = _LoggingWakePlanServiceStore();
          final plan = buildPlan();
          await service(
            store: store,
            gateway: FakeNativeAlarmGateway(),
          ).createPlan(plan);
          store.storedOccurrences = store.storedOccurrences
              .map(
                (occurrence) => occurrence.copyWith(
                  status: status,
                  failureReason: status == AlarmOccurrenceStatus.failed
                      ? ScheduleFailureReason.nativeError.name
                      : null,
                ),
              )
              .toList(growable: false);
          final retryGateway = FakeNativeAlarmGateway();

          final result = await service(
            store: store,
            gateway: retryGateway,
          ).createPlan(plan);

          expect(result.status, WakePlanSchedulingStatus.scheduled);
          expect(
            retryGateway.scheduledRequests,
            hasLength(4),
            reason: status.name,
          );
          expect(
            result.occurrences,
            everyElement(
              predicate<AlarmOccurrence>(
                (occurrence) =>
                    occurrence.status == AlarmOccurrenceStatus.scheduled &&
                    occurrence.platformAlarmId != null,
              ),
            ),
          );
        }
      },
    );

    test(
      'preserves a ringing reservation without coercing its state',
      () async {
        final store = _LoggingWakePlanServiceStore();
        final plan = buildPlan();
        await service(
          store: store,
          gateway: FakeNativeAlarmGateway(),
        ).createPlan(plan);
        final ringingId = 'plan-1:20640:405';
        final firedAt = now;
        store.storedOccurrences = store.storedOccurrences
            .map(
              (occurrence) => occurrence.id == ringingId
                  ? occurrence.copyWith(
                      status: AlarmOccurrenceStatus.ringing,
                      firedAt: firedAt,
                    )
                  : occurrence,
            )
            .toList(growable: false);
        final retryGateway = FakeNativeAlarmGateway();

        final result = await service(
          store: store,
          gateway: retryGateway,
        ).createPlan(plan);

        final ringing = result.occurrences.singleWhere(
          (occurrence) => occurrence.id == ringingId,
        );
        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(retryGateway.scheduledRequests, isEmpty);
        expect(ringing.status, AlarmOccurrenceStatus.ringing);
        expect(ringing.firedAt, firedAt);
      },
    );

    test(
      'does not reuse a reservation for a skipped target on retry',
      () async {
        final store = _LoggingWakePlanServiceStore();
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        await service(
          store: store,
          gateway: FakeNativeAlarmGateway(),
          rollingScheduleDays: 7,
        ).createPlan(plan);
        final retryGateway = FakeNativeAlarmGateway();

        final result = await service(
          store: store,
          gateway: retryGateway,
          rollingScheduleDays: 8,
        ).createPlan(plan.copyWith(skipNextDate: monday));

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(retryGateway.scheduledRequests, hasLength(4));
        expect(
          retryGateway.scheduledRequests.every(
            (request) =>
                request.scheduledAt == DateTime(2026, 7, 13, 6, 45) ||
                request.scheduledAt == DateTime(2026, 7, 13, 6, 50) ||
                request.scheduledAt == DateTime(2026, 7, 13, 6, 55) ||
                request.scheduledAt == DateTime(2026, 7, 13, 7),
          ),
          isTrue,
        );
      },
    );

    test('coalesces concurrent creates for the same plan identity', () async {
      final store = _LoggingWakePlanServiceStore();
      final gateway = _BlockingScheduleGateway();
      final serviceUnderTest = service(store: store, gateway: gateway);

      final first = serviceUnderTest.createPlan(buildPlan());
      await gateway.firstScheduleStarted.future;
      final duplicate = serviceUnderTest.createPlan(buildPlan());

      expect(identical(first, duplicate), isTrue);
      gateway.releaseFirstSchedule.complete();
      await Future.wait([first, duplicate]);

      expect(gateway.scheduleCallCount, 1);
      expect(store.savedPlans, hasLength(1));
      expect(store.storedOccurrences, hasLength(4));
    });

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

    test(
      'schedules the next valid week when today has already passed',
      () async {
        final store = _LoggingWakePlanServiceStore();
        final gateway = FakeNativeAlarmGateway();
        final plan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 5,
            minute: 0,
          ),
          repeatRule: RepeatRule.weekly({Weekday.monday}),
        );

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 7,
        ).createPlan(plan);

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(
          gateway.scheduledRequests.map((request) => request.scheduledAt),
          [
            DateTime(2026, 7, 13, 4, 45),
            DateTime(2026, 7, 13, 4, 50),
            DateTime(2026, 7, 13, 4, 55),
            DateTime(2026, 7, 13, 5),
          ],
        );
      },
    );
  });

  group('WakePlanService reconcileSchedules', () {
    test('persists an exact native dismissal before acknowledgement', () async {
      final eventNow = DateTime(2026, 7, 6, 6, 52);
      final plan = buildPlan();
      final occurrence = buildOccurrence(
        id: 'plan-1:20640:410',
        time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
        platformAlarmId: 'native-current',
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..wakePlans = [plan]
        ..storedOccurrences = [occurrence];
      late _ObservingAckGateway gateway;
      gateway =
          _ObservingAckGateway(
              onAcknowledge: () {
                expect(
                  store.storedOccurrences
                      .singleWhere((candidate) => candidate.id == occurrence.id)
                      .status,
                  AlarmOccurrenceStatus.dismissed,
                );
              },
            )
            ..pendingAlarmEvents.add(
              NativeAlarmEvent(
                eventId: 'dismiss-current',
                platformAlarmId: 'native-current',
                type: NativeAlarmEventType.dismissed,
                timestamp: eventNow.subtract(const Duration(minutes: 1)),
              ),
            );

      await service(
        store: store,
        gateway: gateway,
        clockNow: eventNow,
      ).reconcileSchedules();

      final persisted = store.storedOccurrences.singleWhere(
        (candidate) => candidate.id == occurrence.id,
      );
      expect(persisted.status, AlarmOccurrenceStatus.dismissed);
      expect(persisted.platformAlarmId, 'native-current');
      expect(gateway.acknowledgedAlarmEventIds, ['dismiss-current']);
      expect(gateway.pendingAlarmEvents, isEmpty);
    });

    test('native dismissal survives a real Drift close and reopen', () async {
      final eventNow = DateTime(2026, 7, 6, 6, 52);
      final directory = await Directory.systemTemp.createTemp('calarm-task21-');
      final file = File('${directory.path}/wake-plan.sqlite');
      final plan = buildPlan();
      final occurrence = buildOccurrence(
        id: 'plan-1:20640:410',
        time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
        platformAlarmId: 'native-current',
      );
      final gateway = FakeNativeAlarmGateway()
        ..pendingAlarmEvents.add(
          NativeAlarmEvent(
            eventId: 'dismiss-current',
            platformAlarmId: 'native-current',
            type: NativeAlarmEventType.dismissed,
            timestamp: eventNow,
          ),
        );
      try {
        var database = WakePlanDatabase(NativeDatabase(file));
        var repository = WakePlanRepository(database);
        await repository.saveWakePlan(plan);
        await repository.saveAlarmOccurrences([occurrence]);
        await WakePlanService(
          repository: repository,
          nativeAlarmGateway: gateway,
          coordinator: WakePlanMutationCoordinator(),
          clock: () => eventNow,
        ).reconcileSchedules();
        await database.close();

        database = WakePlanDatabase(NativeDatabase(file));
        repository = WakePlanRepository(database);
        final persisted = await repository.fetchAlarmOccurrence(occurrence.id);
        expect(persisted!.status, AlarmOccurrenceStatus.dismissed);
        expect(persisted.platformAlarmId, 'native-current');
        expect(gateway.pendingAlarmEvents, isEmpty);

        await WakePlanService(
          repository: repository,
          nativeAlarmGateway: gateway,
          coordinator: WakePlanMutationCoordinator(),
          clock: () => eventNow.add(const Duration(minutes: 1)),
        ).reconcileSchedules();
        expect(
          (await repository.fetchAlarmOccurrence(occurrence.id))!.status,
          AlarmOccurrenceStatus.dismissed,
        );
        await database.close();
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('does not acknowledge when native-event persistence fails', () async {
      final eventNow = DateTime(2026, 7, 6, 6, 52);
      final plan = buildPlan();
      final occurrence = buildOccurrence(
        id: 'plan-1:20640:410',
        time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
        platformAlarmId: 'native-current',
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..wakePlans = [plan]
        ..storedOccurrences = [occurrence]
        ..failSaveAlarmOccurrencesAtCalls.add(1);
      final gateway = FakeNativeAlarmGateway()
        ..pendingAlarmEvents.add(
          NativeAlarmEvent(
            eventId: 'dismiss-current',
            platformAlarmId: 'native-current',
            type: NativeAlarmEventType.dismissed,
            timestamp: eventNow,
          ),
        );

      await expectLater(
        service(
          store: store,
          gateway: gateway,
          clockNow: eventNow,
        ).reconcileSchedules(),
        throwsA(isA<StateError>()),
      );

      expect(
        store.storedOccurrences.single.status,
        AlarmOccurrenceStatus.scheduled,
      );
      expect(gateway.acknowledgedAlarmEventIds, isEmpty);
      expect(gateway.pendingAlarmEvents, hasLength(1));
    });

    test(
      'replay converges after a save side effect throws before ack',
      () async {
        final eventNow = DateTime(2026, 7, 6, 6, 52);
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:410',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
          platformAlarmId: 'native-current',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence]
          ..failSaveAlarmOccurrencesAfterMutationAtCalls.add(1);
        final gateway = FakeNativeAlarmGateway()
          ..pendingAlarmEvents.add(
            NativeAlarmEvent(
              eventId: 'dismiss-current',
              platformAlarmId: 'native-current',
              type: NativeAlarmEventType.dismissed,
              timestamp: eventNow,
            ),
          );
        final serviceUnderTest = service(
          store: store,
          gateway: gateway,
          clockNow: eventNow,
        );

        await expectLater(
          serviceUnderTest.reconcileSchedules(),
          throwsA(isA<StateError>()),
        );
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.dismissed,
        );
        expect(gateway.pendingAlarmEvents, hasLength(1));

        store.failSaveAlarmOccurrencesAfterMutationAtCalls.clear();
        await serviceUnderTest.reconcileSchedules();
        expect(gateway.pendingAlarmEvents, isEmpty);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.dismissed,
        );
      },
    );

    test(
      'ack failure replays idempotently without losing exact identity',
      () async {
        final eventNow = DateTime(2026, 7, 6, 6, 52);
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:410',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
          platformAlarmId: 'native-current',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = _FailingAckGateway()
          ..pendingAlarmEvents.add(
            NativeAlarmEvent(
              eventId: 'dismiss-current',
              platformAlarmId: 'native-current',
              type: NativeAlarmEventType.dismissed,
              timestamp: eventNow,
            ),
          );

        await service(
          store: store,
          gateway: gateway,
          clockNow: eventNow,
        ).reconcileSchedules();
        expect(gateway.pendingAlarmEvents, hasLength(1));
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.dismissed,
        );

        gateway.failAcknowledgement = false;
        await service(
          store: store,
          gateway: gateway,
          clockNow: eventNow,
        ).reconcileSchedules();

        expect(gateway.pendingAlarmEvents, isEmpty);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.dismissed,
        );
        expect(
          store.storedOccurrences.single.platformAlarmId,
          'native-current',
        );
      },
    );

    test(
      'delivered-only events become ringing or missed at the policy boundary',
      () async {
        final eventNow = DateTime(2026, 7, 6, 7);
        final plan = buildPlan();
        final current = buildOccurrence(
          id: 'current',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
          platformAlarmId: 'native-current',
        );
        final stale = buildOccurrence(
          id: 'stale',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 40),
          platformAlarmId: 'native-stale',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [current, stale];
        final gateway = FakeNativeAlarmGateway()
          ..pendingAlarmEvents.addAll([
            NativeAlarmEvent(
              eventId: 'delivered-current',
              platformAlarmId: 'native-current',
              type: NativeAlarmEventType.delivered,
              timestamp: eventNow.subtract(const Duration(minutes: 15)),
            ),
            NativeAlarmEvent(
              eventId: 'delivered-stale',
              platformAlarmId: 'native-stale',
              type: NativeAlarmEventType.delivered,
              timestamp: eventNow.subtract(const Duration(minutes: 16)),
            ),
          ]);

        await service(
          store: store,
          gateway: gateway,
          clockNow: eventNow,
        ).reconcileSchedules();

        final byId = {for (final row in store.storedOccurrences) row.id: row};
        expect(byId['current']!.status, AlarmOccurrenceStatus.ringing);
        expect(byId['stale']!.status, AlarmOccurrenceStatus.missed);
        expect(gateway.acknowledgedAlarmEventIds, [
          'delivered-stale',
          'delivered-current',
        ]);
      },
    );

    test(
      'leaves unmatched and corrupt native events durable and unapplied',
      () async {
        final eventNow = DateTime(2026, 7, 6, 6, 52);
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:410',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
          platformAlarmId: 'native-current',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence]
          ..corruptOccurrenceWakePlanIds = {plan.id};
        final gateway = FakeNativeAlarmGateway()
          ..pendingAlarmEvents.addAll([
            NativeAlarmEvent(
              eventId: 'corrupt-match',
              platformAlarmId: 'native-current',
              type: NativeAlarmEventType.dismissed,
              timestamp: eventNow,
            ),
            NativeAlarmEvent(
              eventId: 'unmatched',
              platformAlarmId: 'native-unknown',
              type: NativeAlarmEventType.dismissed,
              timestamp: eventNow,
            ),
          ]);

        await service(
          store: store,
          gateway: gateway,
          clockNow: eventNow,
        ).reconcileSchedules();

        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(gateway.acknowledgedAlarmEventIds, isEmpty);
        expect(gateway.pendingAlarmEvents, hasLength(2));
      },
    );

    test(
      'rejects duplicate event batches and conflicting inventory tuples',
      () async {
        final eventNow = DateTime(2026, 7, 6, 6, 52);
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:410',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
          platformAlarmId: 'native-current',
        );
        final duplicateStore = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final duplicateGateway = _DuplicateEventGateway(
          event: NativeAlarmEvent(
            eventId: 'duplicate',
            platformAlarmId: 'native-current',
            type: NativeAlarmEventType.dismissed,
            timestamp: eventNow,
          ),
        );

        await service(
          store: duplicateStore,
          gateway: duplicateGateway,
          clockNow: eventNow,
        ).reconcileSchedules();
        expect(
          duplicateStore.storedOccurrences.single.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(duplicateGateway.acknowledgedAlarmEventIds, isEmpty);

        final conflictStore = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final conflictGateway = FakeNativeAlarmGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: 'other-occurrence',
              wakePlanId: plan.id,
              platformAlarmId: 'native-current',
              status: NativeAlarmReservationStatus.stopped,
            ),
          )
          ..pendingAlarmEvents.add(
            NativeAlarmEvent(
              eventId: 'conflicted',
              platformAlarmId: 'native-current',
              type: NativeAlarmEventType.dismissed,
              timestamp: eventNow,
            ),
          );

        await service(
          store: conflictStore,
          gateway: conflictGateway,
          clockNow: eventNow,
        ).reconcileSchedules();
        expect(
          conflictStore.storedOccurrences.single.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(conflictGateway.acknowledgedAlarmEventIds, isEmpty);
        expect(conflictGateway.pendingAlarmEvents, hasLength(1));
      },
    );

    test(
      'does not settle a valid row sharing an id with corrupt persistence',
      () async {
        final eventNow = DateTime(2026, 7, 6, 6, 52);
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:410',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
          platformAlarmId: 'native-current',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence]
          ..corruptPlatformAlarmIds = {'native-current'};
        final gateway = withUnavailableInventory(FakeNativeAlarmGateway())
          ..pendingAlarmEvents.add(
            NativeAlarmEvent(
              eventId: 'ambiguous-dismissal',
              platformAlarmId: 'native-current',
              type: NativeAlarmEventType.dismissed,
              timestamp: eventNow,
            ),
          );

        await service(
          store: store,
          gateway: gateway,
          clockNow: eventNow,
        ).reconcileSchedules();

        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(gateway.acknowledgedAlarmEventIds, isEmpty);
        expect(gateway.pendingAlarmEvents, hasLength(1));
      },
    );

    test(
      'waits for authoritative inventory before applying an event',
      () async {
        final eventNow = DateTime(2026, 7, 6, 6, 52);
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:410',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
          platformAlarmId: 'native-current',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = withUnavailableInventory(FakeNativeAlarmGateway())
          ..pendingAlarmEvents.add(
            NativeAlarmEvent(
              eventId: 'pending-dismissal',
              platformAlarmId: 'native-current',
              type: NativeAlarmEventType.dismissed,
              timestamp: eventNow,
            ),
          );

        await service(
          store: store,
          gateway: gateway,
          clockNow: eventNow,
        ).reconcileSchedules();
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(gateway.acknowledgedAlarmEventIds, isEmpty);

        gateway.capability = const NativeAlarmCapability(
          permissionStatus: NativeAlarmPermissionStatus.authorized,
          canScheduleAlarms: true,
          canRequestPermission: true,
          supportsInventory: true,
        );
        await service(
          store: store,
          gateway: gateway,
          clockNow: eventNow,
        ).reconcileSchedules();
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.dismissed,
        );
        expect(gateway.pendingAlarmEvents, isEmpty);
      },
    );

    test(
      'keeps past and exact-now weekly recovery markers terminal while replenishing the future horizon',
      () async {
        final exactNow = DateTime(2026, 7, 6, 7);
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        for (final boundary in [
          (
            name: 'past',
            time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
            id: 'plan-1:20640:415',
          ),
          (name: 'exact-now', time: targetTime, id: 'plan-1:20640:420'),
        ]) {
          for (final marker in [
            buildOccurrence(
              id: boundary.id,
              time: boundary.time,
              status: AlarmOccurrenceStatus.userDisablePending,
              platformAlarmId: 'native-${boundary.name}-off',
            ),
            buildOccurrence(
              id: boundary.id,
              time: boundary.time,
              status: AlarmOccurrenceStatus.userEnablePending,
              platformAlarmId: null,
            ),
            buildOccurrence(
              id: boundary.id,
              time: boundary.time,
              status: AlarmOccurrenceStatus.scheduled,
              platformAlarmId: null,
            ),
          ]) {
            final store = _LoggingWakePlanServiceStore(currentPlan: plan)
              ..wakePlans = [plan]
              ..storedOccurrences = [marker];
            final gateway = FakeNativeAlarmGateway();
            if (marker.platformAlarmId != null) {
              gateway.inventoryRows.add(
                NativeAlarmInventoryRow(
                  reservationId: marker.id,
                  occurrenceId: marker.id,
                  wakePlanId: plan.id,
                  platformAlarmId: marker.platformAlarmId!,
                  status: NativeAlarmReservationStatus.scheduled,
                ),
              );
            }

            final results = await service(
              store: store,
              gateway: gateway,
              rollingScheduleDays: 1,
              clockNow: exactNow,
            ).reconcileSchedules();

            expect(results, hasLength(1), reason: boundary.name);
            expect(
              gateway.cancelledOccurrences.where(
                (request) => request.occurrenceId == marker.id,
              ),
              isEmpty,
              reason: '${boundary.name}:${marker.status.name}',
            );
            expect(
              gateway.scheduledRequests.where(
                (request) => request.occurrenceId == marker.id,
              ),
              isEmpty,
              reason: '${boundary.name}:${marker.status.name}',
            );
            final persistedMarker = store.storedOccurrences.singleWhere(
              (occurrence) => occurrence.id == marker.id,
            );
            expect(
              persistedMarker.status,
              marker.status,
              reason: '${boundary.name}:${marker.status.name}',
            );
            expect(
              persistedMarker.platformAlarmId,
              marker.platformAlarmId,
              reason: '${boundary.name}:${marker.status.name}',
            );
            expect(
              gateway.scheduledRequests,
              hasLength(4),
              reason: 'weekly replenishment:${boundary.name}',
            );
            expect(
              gateway.scheduledRequests.every(
                (request) => request.scheduledAt.isAfter(exactNow),
              ),
              isTrue,
            );
          }
        }
      },
    );

    test(
      'recovers strictly-future weekly markers without duplicates',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final futureDay = monday.addDays(7);
        for (final marker in [
          buildOccurrence(
            id: 'plan-1:20647:420',
            day: futureDay,
            status: AlarmOccurrenceStatus.userDisablePending,
            platformAlarmId: 'native-future-off',
          ),
          buildOccurrence(
            id: 'plan-1:20647:420',
            day: futureDay,
            status: AlarmOccurrenceStatus.userEnablePending,
            platformAlarmId: null,
          ),
          buildOccurrence(
            id: 'plan-1:20647:420',
            day: futureDay,
            status: AlarmOccurrenceStatus.scheduled,
            platformAlarmId: null,
          ),
        ]) {
          final store = _LoggingWakePlanServiceStore(currentPlan: plan)
            ..wakePlans = [plan]
            ..storedOccurrences = [marker];
          final gateway = FakeNativeAlarmGateway();
          if (marker.platformAlarmId != null) {
            gateway.inventoryRows.add(
              NativeAlarmInventoryRow(
                reservationId: marker.id,
                occurrenceId: marker.id,
                wakePlanId: plan.id,
                platformAlarmId: marker.platformAlarmId!,
                status: NativeAlarmReservationStatus.scheduled,
              ),
            );
          }

          await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
            clockNow: DateTime(2026, 7, 6, 7),
          ).reconcileSchedules();

          final persisted = store.storedOccurrences.singleWhere(
            (occurrence) => occurrence.id == marker.id,
          );
          if (marker.status == AlarmOccurrenceStatus.userDisablePending) {
            expect(persisted.status, AlarmOccurrenceStatus.userDisabled);
            expect(
              gateway.cancelledOccurrences.where(
                (request) => request.occurrenceId == marker.id,
              ),
              hasLength(1),
            );
            expect(
              gateway.scheduledRequests.where(
                (request) => request.occurrenceId == marker.id,
              ),
              isEmpty,
            );
          } else {
            expect(persisted.status, AlarmOccurrenceStatus.scheduled);
            expect(persisted.platformAlarmId, isNotNull);
            expect(
              gateway.scheduledRequests.where(
                (request) => request.occurrenceId == marker.id,
              ),
              hasLength(1),
            );
          }
          expect(
            gateway.inventoryRows
                .where((row) => row.occurrenceId == marker.id)
                .length,
            lessThanOrEqualTo(1),
          );
        }
      },
    );

    test(
      'replenishes a horizon and is idempotent across repeated runs',
      () async {
        final plan = buildPlan(
          repeatRule: RepeatRule.weekly({
            Weekday.monday,
            Weekday.tuesday,
            Weekday.wednesday,
          }),
        );
        final store = _LoggingWakePlanServiceStore()..wakePlans = [plan];
        final firstGateway = FakeNativeAlarmGateway();
        final serviceUnderTest = service(
          store: store,
          gateway: firstGateway,
          rollingScheduleDays: 2,
        );

        final concurrent = await Future.wait([
          serviceUnderTest.reconcileSchedules(),
          serviceUnderTest.reconcileSchedules(),
        ]);
        final first = concurrent.first;
        expect(concurrent.last.single.occurrences, hasLength(8));
        final secondGateway = FakeNativeAlarmGateway()
          ..inventoryRows.addAll(firstGateway.inventoryRows);
        final second = await service(
          store: store,
          gateway: secondGateway,
          rollingScheduleDays: 2,
        ).reconcileSchedules();

        expect(first.single.status, WakePlanSchedulingStatus.scheduled);
        expect(first.single.occurrences, hasLength(8));
        expect(second.single.status, WakePlanSchedulingStatus.scheduled);
        expect(second.single.occurrences, hasLength(8));
        expect(firstGateway.scheduledRequests, hasLength(8));
        expect(secondGateway.scheduledRequests, isEmpty);
        expect(store.storedOccurrences, hasLength(8));
      },
    );

    test(
      'runs one fresh non-overlapping follow-up when a request arrives in flight',
      () async {
        final plan = buildPlan(
          repeatRule: RepeatRule.weekly({
            Weekday.monday,
            Weekday.tuesday,
            Weekday.wednesday,
          }),
        );
        final store = _LoggingWakePlanServiceStore()..wakePlans = [plan];
        final gateway = _BlockingScheduleGateway();
        var currentNow = now;
        final serviceUnderTest = WakePlanService.withStore(
          store: store,
          nativeAlarmGateway: gateway,
          coordinator: WakePlanMutationCoordinator(),
          clock: () => currentNow,
          rollingScheduleDays: 2,
        );

        final first = serviceUnderTest.reconcileSchedules();
        await gateway.firstScheduleStarted.future;

        currentNow = DateTime(2026, 7, 7, 5, 55);
        final followUp = serviceUnderTest.reconcileSchedules();
        gateway.releaseFirstSchedule.complete();

        final results = await Future.wait([first, followUp]);

        expect(store.fetchPlanNows, [now, currentNow]);
        expect(results, everyElement(hasLength(1)));
        expect(gateway.scheduleCallCount, 2);
        expect(gateway.maxConcurrentScheduleCalls, 1);
        expect(gateway.scheduledBatches, hasLength(2));
        expect(gateway.scheduledBatches.first, hasLength(8));
        expect(gateway.scheduledBatches.last, hasLength(4));
        expect(
          gateway.scheduledBatches.last.every(
            (request) => request.scheduledAt.weekday == DateTime.wednesday,
          ),
          isTrue,
        );
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          hasLength(
            gateway.scheduledRequests
                .map((request) => request.occurrenceId)
                .toSet()
                .length,
          ),
        );
      },
    );

    test(
      'replenishes only the newly entered day after time advances',
      () async {
        final plan = buildPlan(
          repeatRule: RepeatRule.weekly({
            Weekday.monday,
            Weekday.tuesday,
            Weekday.wednesday,
          }),
        );
        final store = _LoggingWakePlanServiceStore()..wakePlans = [plan];
        final firstGateway = FakeNativeAlarmGateway();
        await service(
          store: store,
          gateway: firstGateway,
          rollingScheduleDays: 2,
        ).reconcileSchedules();

        final nextGateway = FakeNativeAlarmGateway()
          ..inventoryRows.addAll(firstGateway.inventoryRows);
        final result = await service(
          store: store,
          gateway: nextGateway,
          rollingScheduleDays: 2,
          clockNow: DateTime(2026, 7, 7, 5, 55),
        ).reconcileSchedules();

        expect(result.single.status, WakePlanSchedulingStatus.scheduled);
        expect(
          result.single.occurrences.map(
            (occurrence) => occurrence.scheduledAt.day,
          ),
          [
            tuesday,
            tuesday,
            tuesday,
            tuesday,
            wednesday,
            wednesday,
            wednesday,
            wednesday,
          ],
        );
        expect(nextGateway.scheduledRequests, hasLength(4));
        expect(
          nextGateway.scheduledRequests.every(
            (request) => request.scheduledAt.weekday == DateTime.wednesday,
          ),
          isTrue,
        );
      },
    );

    test('retries occurrences with stale native reservation state', () async {
      final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
      final store = _LoggingWakePlanServiceStore()..wakePlans = [plan];
      await service(
        store: store,
        gateway: FakeNativeAlarmGateway(),
        rollingScheduleDays: 1,
      ).reconcileSchedules();

      store.storedOccurrences = store.storedOccurrences
          .map(
            (occurrence) => occurrence.copyWith(
              status: AlarmOccurrenceStatus.failed,
              platformAlarmId: 'stale-${occurrence.id}',
              failureReason: ScheduleFailureReason.nativeError.name,
            ),
          )
          .toList(growable: false);
      final retryGateway = FakeNativeAlarmGateway();

      final result = await service(
        store: store,
        gateway: retryGateway,
        rollingScheduleDays: 1,
      ).reconcileSchedules();

      expect(result.single.status, WakePlanSchedulingStatus.scheduled);
      expect(retryGateway.scheduledRequests, hasLength(4));
      expect(
        store.storedOccurrences.every(
          (occurrence) =>
              occurrence.status == AlarmOccurrenceStatus.scheduled &&
              occurrence.platformAlarmId != null,
        ),
        isTrue,
      );
    });

    test(
      'reconciliation preserves ringing reservations without rescheduling',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final store = _LoggingWakePlanServiceStore()..wakePlans = [plan];
        final initialGateway = FakeNativeAlarmGateway();
        await service(
          store: store,
          gateway: initialGateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        final ringingId = store.storedOccurrences.first.id;
        final firedAt = now;
        store.storedOccurrences = store.storedOccurrences
            .map(
              (occurrence) => occurrence.id == ringingId
                  ? occurrence.copyWith(
                      status: AlarmOccurrenceStatus.ringing,
                      firedAt: firedAt,
                    )
                  : occurrence,
            )
            .toList(growable: false);
        final retryGateway = FakeNativeAlarmGateway()
          ..inventoryRows.addAll(initialGateway.inventoryRows);

        final result = await service(
          store: store,
          gateway: retryGateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        final ringing = result.single.occurrences.singleWhere(
          (occurrence) => occurrence.id == ringingId,
        );
        expect(retryGateway.scheduledRequests, isEmpty);
        expect(ringing.status, AlarmOccurrenceStatus.ringing);
        expect(ringing.firedAt, firedAt);
      },
    );

    test(
      'does not replenish disabled, deleted, or skipped plans incorrectly',
      () async {
        final skipped = buildPlan(
          id: 'skipped',
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
          skipNextDate: monday,
        );
        final disabled = buildPlan(
          id: 'disabled',
          isEnabled: false,
          repeatRule: RepeatRule.weekly({Weekday.monday}),
        );
        final deleted = buildPlan(
          id: 'deleted',
          isEnabled: false,
          status: WakePlanStatus.deleted,
          repeatRule: RepeatRule.weekly({Weekday.monday}),
        );
        final store = _LoggingWakePlanServiceStore()
          ..wakePlans = [skipped, disabled, deleted];
        final gateway = FakeNativeAlarmGateway();

        final results = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 2,
        ).reconcileSchedules();

        expect(results.map((result) => result.wakePlanId), ['skipped']);
        expect(
          results.single.occurrences.every(
            (occurrence) => occurrence.scheduledAt.day == tuesday,
          ),
          isTrue,
        );
        expect(gateway.scheduledRequests, hasLength(4));
      },
    );

    test('reports an empty enabled repeating schedule as a failure', () async {
      final store = _LoggingWakePlanServiceStore()
        ..wakePlans = [
          buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday})),
        ];
      final gateway = FakeNativeAlarmGateway();

      final result = await service(
        store: store,
        gateway: gateway,
        occurrencePlanner: _EmptyOccurrencePlanner(),
      ).reconcileSchedules();

      expect(result.single.status, WakePlanSchedulingStatus.scheduleFailed);
      expect(result.single.isSuccess, isFalse);
      expect(
        result.single.warning!.message,
        'No future alarm occurrence could be scheduled.',
      );
      expect(gateway.scheduledRequests, isEmpty);
    });
  });

  group('WakePlanService whole-inventory reconciliation', () {
    final plan = buildPlan(
      startOffset: Duration.zero,
      repeatRule: RepeatRule.weekly({Weekday.monday}),
    );
    final occurrenceId = 'plan-1:20640:420';

    for (final scenario in [
      (
        name: 'exact match',
        storedId: 'native-authoritative',
        includeStored: true,
        includeNative: true,
        expectedScheduledCalls: 0,
      ),
      (
        name: 'stale platform id',
        storedId: 'native-stale',
        includeStored: true,
        includeNative: true,
        expectedScheduledCalls: 0,
      ),
      (
        name: 'matching native-only',
        storedId: null,
        includeStored: false,
        includeNative: true,
        expectedScheduledCalls: 0,
      ),
      (
        name: 'DB-only',
        storedId: 'native-missing',
        includeStored: true,
        includeNative: false,
        expectedScheduledCalls: 1,
      ),
    ]) {
      test('${scenario.name} converges from one snapshot', () async {
        final stored = buildOccurrence(
          id: occurrenceId,
          platformAlarmId: scenario.storedId,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = scenario.includeStored ? [stored] : [];
        final gateway = _CountingInventoryGateway();
        if (scenario.includeNative) {
          gateway.inventoryRows.add(
            inventoryRow(stored, platformAlarmId: 'native-authoritative'),
          );
        }

        final serviceUnderTest = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );
        final result = await serviceUnderTest.reconcileSchedules();

        expect(result.single.status, WakePlanSchedulingStatus.scheduled);
        expect(gateway.inventoryCalls, 1);
        expect(
          gateway.scheduledRequests,
          hasLength(scenario.expectedScheduledCalls),
        );
        expect(store.storedOccurrences.single.platformAlarmId, isNotNull);
        expect(
          store.storedOccurrences.single.platformAlarmId,
          scenario.includeNative
              ? 'native-authoritative'
              : 'platform-$occurrenceId',
        );
        final sideEffectCount =
            gateway.scheduledRequests.length +
            gateway.cancelledOccurrences.length;
        await Future.wait([
          serviceUnderTest.reconcileSchedules(),
          serviceUnderTest.reconcileSchedules(),
        ]);
        expect(
          gateway.scheduledRequests.length +
              gateway.cancelledOccurrences.length,
          sideEffectCount,
        );
      });
    }

    test('cancels owned native-only rows and retains unrelated rows', () async {
      final disabledPlan = buildPlan(
        id: 'disabled-plan',
        startOffset: Duration.zero,
        repeatRule: RepeatRule.weekly({Weekday.monday}),
        isEnabled: false,
      );
      final disabledOccurrence = AlarmOccurrence(
        id: 'disabled-plan:20640:420',
        wakePlanId: disabledPlan.id,
        scheduledAt: DateMinute(day: monday, time: targetTime),
        status: AlarmOccurrenceStatus.scheduled,
        platformAlarmId: 'native-disabled',
        createdAt: now,
        updatedAt: now,
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..wakePlans = [plan, disabledPlan]
        ..storedOccurrences = [disabledOccurrence];
      final gateway = _CountingInventoryGateway()
        ..inventoryRows.addAll([
          NativeAlarmInventoryRow(
            reservationId: 'owned-extra',
            occurrenceId: 'owned-extra',
            wakePlanId: 'plan-1',
            platformAlarmId: 'native-owned-extra',
            status: NativeAlarmReservationStatus.scheduled,
          ),
          inventoryRow(disabledOccurrence, platformAlarmId: 'native-disabled'),
          NativeAlarmInventoryRow(
            reservationId: 'other-extra',
            occurrenceId: 'other-extra',
            wakePlanId: 'other-plan',
            platformAlarmId: 'native-other-extra',
            status: NativeAlarmReservationStatus.scheduled,
          ),
        ]);

      final serviceUnderTest = service(
        store: store,
        gateway: gateway,
        rollingScheduleDays: 1,
      );
      await serviceUnderTest.reconcileSchedules();

      expect(
        gateway.cancelledOccurrences.map((request) => request.occurrenceId),
        containsAll(['owned-extra', disabledOccurrence.id]),
      );
      expect(
        gateway.inventoryRows.map((row) => row.occurrenceId),
        contains('other-extra'),
      );
      await Future.wait([
        serviceUnderTest.reconcileSchedules(),
        serviceUnderTest.reconcileSchedules(),
      ]);
      expect(gateway.cancelledOccurrences, hasLength(2));
    });

    for (final failureMode in ['reported', 'lost reply']) {
      test('owned orphan cancel $failureMode converges on retry', () async {
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan];
        final gateway =
            failureMode == 'lost reply'
                  ? _PostSideEffectThrowingGateway(throwAfterCancel: true)
                  : FakeNativeAlarmGateway()
              ..inventoryRows.add(
                NativeAlarmInventoryRow(
                  reservationId: 'owned-extra',
                  occurrenceId: 'owned-extra',
                  wakePlanId: plan.id,
                  platformAlarmId: 'native-owned-extra',
                  status: NativeAlarmReservationStatus.scheduled,
                ),
              );
        if (failureMode == 'reported') {
          gateway.cancelFailurePlatformAlarmIds.add('native-owned-extra');
        }
        final serviceUnderTest = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );

        final first = await serviceUnderTest.reconcileSchedules();
        expect(first.single.status, WakePlanSchedulingStatus.recoveryRequired);
        gateway.cancelFailurePlatformAlarmIds.clear();
        final retried = await serviceUnderTest.reconcileSchedules();

        expect(retried.single.status, WakePlanSchedulingStatus.scheduled);
        expect(gateway.inventoryRows, hasLength(1));
        expect(gateway.inventoryRows.single.occurrenceId, occurrenceId);
      });
    }

    test(
      'adoption persistence failure converges without rescheduling',
      () async {
        final stored = buildOccurrence(id: occurrenceId, platformAlarmId: null);
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..failSaveAlarmOccurrencesAtCalls.add(1);
        final gateway = FakeNativeAlarmGateway()
          ..inventoryRows.add(
            inventoryRow(stored, platformAlarmId: 'native-authoritative'),
          );
        final serviceUnderTest = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );

        final first = await serviceUnderTest.reconcileSchedules();
        final retried = await serviceUnderTest.reconcileSchedules();

        expect(first.single.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(retried.single.status, WakePlanSchedulingStatus.scheduled);
        expect(gateway.scheduledRequests, isEmpty);
        expect(
          store.storedOccurrences.single.platformAlarmId,
          'native-authoritative',
        );
      },
    );

    test(
      'same-plan recreated occurrence adopts its stable reservation after restart',
      () async {
        final pending = buildOccurrence(
          id: occurrenceId,
          status: AlarmOccurrenceStatus.userEnablePending,
          platformAlarmId: null,
          reservationId: 'stable-recreation-slot',
          reservationGeneration: 3,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [pending];
        final gateway = _CountingInventoryGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: 'stable-recreation-slot',
              occurrenceId: pending.id,
              wakePlanId: pending.wakePlanId,
              platformAlarmId: 'native-recreated',
              status: NativeAlarmReservationStatus.scheduled,
              reservationGeneration: 3,
            ),
          );

        final firstService = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );
        final first = await firstService.reconcileSchedules();
        final reopenedService = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );
        final reopened = await reopenedService.reconcileSchedules();
        expect(first.single.status, WakePlanSchedulingStatus.scheduled);
        expect(reopened.single.status, WakePlanSchedulingStatus.scheduled);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(
          store.storedOccurrences.single.platformAlarmId,
          'native-recreated',
        );
        expect(
          store.storedOccurrences.single.reservationId,
          'stable-recreation-slot',
        );
        expect(store.storedOccurrences.single.reservationGeneration, 3);
        expect(gateway.scheduledRequests, isEmpty);
        final disabled = await reopenedService.setOccurrenceEnabled(
          wakePlanId: pending.wakePlanId,
          occurrenceId: pending.id,
          enabled: false,
        );
        expect(disabled.status, AlarmOccurrenceToggleStatus.disabled);
        expect(
          gateway.cancelledOccurrences.single.reservationId,
          'stable-recreation-slot',
        );
        expect(gateway.cancelledOccurrences.single.occurrenceId, pending.id);
        expect(gateway.cancelledOccurrences.single.reservationGeneration, 3);
        expect(gateway.inventoryRows, isEmpty);
      },
    );

    test(
      'stale native reservation generation cannot roll back persisted identity',
      () async {
        final pending = buildOccurrence(
          id: occurrenceId,
          status: AlarmOccurrenceStatus.userEnablePending,
          platformAlarmId: null,
          reservationId: 'stable-recreation-slot',
          reservationGeneration: 4,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [pending];
        final gateway = _CountingInventoryGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: pending.reservationId,
              reservationGeneration: 3,
              occurrenceId: pending.id,
              wakePlanId: pending.wakePlanId,
              platformAlarmId: 'native-stale',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(result.single.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(store.storedOccurrences.single.reservationGeneration, 4);
        expect(store.storedOccurrences.single.platformAlarmId, isNull);
        expect(gateway.scheduledRequests, isEmpty);
        expect(gateway.cancelledOccurrences, isEmpty);
      },
    );

    for (final failure in [
      NativeAlarmInventoryFailureReason.unavailable,
      NativeAlarmInventoryFailureReason.corrupt,
      NativeAlarmInventoryFailureReason.unknown,
    ]) {
      test('$failure is non-destructive and observable', () async {
        final pending = buildOccurrence(
          id: occurrenceId,
          status: AlarmOccurrenceStatus.userEnablePending,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [pending];
        final gateway = _CountingInventoryGateway()
          ..inventoryFailureReason = failure;

        final serviceUnderTest = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );
        final result = await serviceUnderTest.reconcileSchedules();

        expect(result.single.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(gateway.inventoryCalls, 1);
        expect(gateway.scheduledRequests, isEmpty);
        expect(gateway.cancelledOccurrences, isEmpty);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.userEnablePending,
        );
        await Future.wait([
          serviceUnderTest.reconcileSchedules(),
          serviceUnderTest.reconcileSchedules(),
        ]);
        expect(gateway.scheduledRequests, isEmpty);
        expect(gateway.cancelledOccurrences, isEmpty);
      });
    }

    test('duplicate and conflicting snapshots perform no repair', () async {
      for (final kind in ['duplicate', 'conflicting']) {
        final pending = buildOccurrence(
          id: occurrenceId,
          status: AlarmOccurrenceStatus.userEnablePending,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [pending];
        final gateway = _CountingInventoryGateway();
        gateway.inventoryRows.add(
          inventoryRow(pending, platformAlarmId: 'native-one'),
        );
        gateway.inventoryRows.add(
          kind == 'duplicate'
              ? inventoryRow(pending, platformAlarmId: 'native-two')
              : NativeAlarmInventoryRow(
                  reservationId: pending.id,
                  occurrenceId: 'plan-1:20640:420',
                  wakePlanId: 'other-plan',
                  platformAlarmId: 'native-conflict',
                  status: NativeAlarmReservationStatus.scheduled,
                ),
        );

        final serviceUnderTest = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );
        final result = await serviceUnderTest.reconcileSchedules();

        expect(
          result
              .singleWhere((candidate) => candidate.wakePlanId == plan.id)
              .status,
          WakePlanSchedulingStatus.recoveryRequired,
          reason: kind,
        );
        expect(gateway.scheduledRequests, isEmpty, reason: kind);
        expect(gateway.cancelledOccurrences, isEmpty, reason: kind);
        expect(store.savedOccurrences, isEmpty, reason: kind);
        await Future.wait([
          serviceUnderTest.reconcileSchedules(),
          serviceUnderTest.reconcileSchedules(),
        ]);
        expect(gateway.scheduledRequests, isEmpty, reason: kind);
        expect(gateway.cancelledOccurrences, isEmpty, reason: kind);
      }
    });

    test(
      'cross-plan corrupt identity blocks every participant but not a safe plan',
      () async {
        final conflictedPlan = buildPlan(
          id: 'conflicted-plan',
          startOffset: Duration.zero,
          repeatRule: RepeatRule.weekly({Weekday.monday}),
        );
        final safePlan = buildPlan(
          id: 'safe-plan',
          startOffset: Duration.zero,
          repeatRule: RepeatRule.weekly({Weekday.monday}),
        );
        final decoded = buildOccurrence(
          id: occurrenceId,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan, conflictedPlan, safePlan]
          ..storedOccurrences = [decoded]
          ..corruptOccurrenceIds = {occurrenceId}
          ..corruptOccurrenceWakePlanIds = {conflictedPlan.id};
        final gateway = _CountingInventoryGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrenceId,
              occurrenceId: occurrenceId,
              wakePlanId: conflictedPlan.id,
              platformAlarmId: 'native-conflicted',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );
        final serviceUnderTest = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );

        final first = await serviceUnderTest.reconcileSchedules();
        await Future.wait([
          serviceUnderTest.reconcileSchedules(),
          serviceUnderTest.reconcileSchedules(),
        ]);

        expect(
          first
              .where((result) => result.wakePlanId != safePlan.id)
              .map((result) => result.status),
          everyElement(WakePlanSchedulingStatus.recoveryRequired),
        );
        expect(gateway.scheduledRequests.map((request) => request.wakePlanId), [
          safePlan.id,
        ]);
        expect(gateway.cancelledOccurrences, isEmpty);
        expect(
          store.storedOccurrences
              .singleWhere((occurrence) => occurrence.id == occurrenceId)
              .platformAlarmId,
          isNull,
        );
        expect(
          gateway.inventoryRows
              .where((row) => row.occurrenceId == occurrenceId)
              .single
              .platformAlarmId,
          'native-conflicted',
        );
      },
    );

    test(
      'inactive exact row blocks reschedule and preserves unrelated safe work',
      () async {
        final safePlan = buildPlan(
          id: 'safe-plan',
          startOffset: Duration.zero,
          repeatRule: RepeatRule.weekly({Weekday.monday}),
        );
        final stored = buildOccurrence(
          id: occurrenceId,
          platformAlarmId: 'native-stopped',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan, safePlan]
          ..storedOccurrences = [stored];
        final gateway = _CountingInventoryGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrenceId,
              occurrenceId: occurrenceId,
              wakePlanId: plan.id,
              platformAlarmId: 'native-stopped',
              status: NativeAlarmReservationStatus.stopped,
            ),
          );
        final serviceUnderTest = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );

        final first = await serviceUnderTest.reconcileSchedules();
        await Future.wait([
          serviceUnderTest.reconcileSchedules(),
          serviceUnderTest.reconcileSchedules(),
        ]);

        expect(
          first.singleWhere((result) => result.wakePlanId == plan.id).status,
          WakePlanSchedulingStatus.recoveryRequired,
        );
        expect(
          first
              .singleWhere((result) => result.wakePlanId == safePlan.id)
              .status,
          WakePlanSchedulingStatus.scheduled,
        );
        expect(gateway.scheduledRequests.map((request) => request.wakePlanId), [
          safePlan.id,
        ]);
        expect(gateway.cancelledOccurrences, isEmpty);
        expect(
          store.storedOccurrences
              .singleWhere((occurrence) => occurrence.id == occurrenceId)
              .platformAlarmId,
          'native-stopped',
        );
        expect(
          gateway.inventoryRows
              .singleWhere((row) => row.occurrenceId == occurrenceId)
              .status,
          NativeAlarmReservationStatus.stopped,
        );
      },
    );

    test(
      'cancels decoded noncanonical alarm before scheduling edited bundle',
      () async {
        final editedPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 7,
            minute: 30,
          ),
          startOffset: Duration.zero,
          repeatRule: RepeatRule.weekly({Weekday.monday}),
        );
        final stale = buildOccurrence(
          id: occurrenceId,
          platformAlarmId: 'native-stale',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: editedPlan)
          ..wakePlans = [editedPlan]
          ..storedOccurrences = [stale];
        final gateway = _CountingInventoryGateway()
          ..inventoryRows.add(
            inventoryRow(stale, platformAlarmId: 'native-stale'),
          );
        final serviceUnderTest = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );

        final first = await serviceUnderTest.reconcileSchedules();
        final sideEffectCount =
            gateway.cancelledOccurrences.length +
            gateway.scheduledRequests.length;
        await Future.wait([
          serviceUnderTest.reconcileSchedules(),
          serviceUnderTest.reconcileSchedules(),
        ]);

        expect(first.single.status, WakePlanSchedulingStatus.scheduled);
        expect(
          gateway.cancelledOccurrences.map((request) => request.occurrenceId),
          [occurrenceId],
        );
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          ['plan-1:20640:450'],
        );
        expect(gateway.inventoryRows, hasLength(1));
        expect(gateway.inventoryRows.single.occurrenceId, 'plan-1:20640:450');
        expect(
          gateway.cancelledOccurrences.length +
              gateway.scheduledRequests.length,
          sideEffectCount,
        );
      },
    );

    test(
      'edit crash waits for authoritative inventory before replacing old identity',
      () async {
        for (final inventoryCase in [
          'unavailable',
          'corrupt',
          'read-failure',
        ]) {
          final originalPlan = buildPlan(
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final editedPlan = buildPlan(
            targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
              hour: 7,
              minute: 30,
            ),
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final safePlan = buildPlan(
            id: 'safe-$inventoryCase',
            startOffset: Duration.zero,
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final oldOccurrence = buildOccurrence(
            id: occurrenceId,
            platformAlarmId: 'native-old-$inventoryCase',
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
            ..wakePlans = [originalPlan, safePlan]
            ..reservedOccurrences = [oldOccurrence]
            ..storedOccurrences = [oldOccurrence]
            ..failSaveWakePlanAfterMutationAtCalls.add(1);
          final gateway = _CountingInventoryGateway(
            throwOnRead: inventoryCase == 'read-failure',
          );
          if (inventoryCase == 'unavailable') {
            withUnavailableInventory(gateway);
          } else if (inventoryCase == 'corrupt') {
            gateway.inventoryFailureReason =
                NativeAlarmInventoryFailureReason.corrupt;
          }

          await expectLater(
            service(
              store: store,
              gateway: gateway,
              rollingScheduleDays: 1,
            ).editPlan(editedPlan),
            throwsA(isA<StateError>()),
            reason: inventoryCase,
          );
          expect(store.currentPlan!.targetTime, editedPlan.targetTime);
          expect(gateway.cancelledOccurrences, isEmpty);

          store
            ..wakePlans = [store.currentPlan!, safePlan]
            ..failSaveWakePlanAfterMutationAtCalls.clear();
          final restarted = service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          );
          final unavailablePasses = await Future.wait([
            restarted.reconcileSchedules(),
            restarted.reconcileSchedules(),
          ]);

          for (final results in unavailablePasses) {
            expect(
              results
                  .singleWhere((result) => result.wakePlanId == originalPlan.id)
                  .status,
              WakePlanSchedulingStatus.recoveryRequired,
              reason: inventoryCase,
            );
          }
          expect(
            gateway.scheduledRequests.map((request) => request.wakePlanId),
            [safePlan.id],
            reason: inventoryCase,
          );
          expect(gateway.cancelledOccurrences, isEmpty, reason: inventoryCase);
          expect(
            store.storedOccurrences.singleWhere(
              (occurrence) => occurrence.id == oldOccurrence.id,
            ),
            oldOccurrence,
            reason: inventoryCase,
          );

          gateway
            ..throwOnRead = false
            ..inventoryFailureReason = null
            ..capability = const NativeAlarmCapability(
              permissionStatus: NativeAlarmPermissionStatus.authorized,
              canScheduleAlarms: true,
              canRequestPermission: true,
              supportsInventory: true,
            )
            ..inventoryRows.add(
              inventoryRow(
                oldOccurrence,
                platformAlarmId: oldOccurrence.platformAlarmId!,
              ),
            );

          final authoritative = await restarted.reconcileSchedules();
          expect(
            authoritative
                .singleWhere((result) => result.wakePlanId == originalPlan.id)
                .status,
            WakePlanSchedulingStatus.scheduled,
            reason: inventoryCase,
          );
          expect(
            gateway.cancelledOccurrences.map(
              (request) => request.platformAlarmId,
            ),
            [oldOccurrence.platformAlarmId],
            reason: inventoryCase,
          );
          expect(
            gateway.scheduledRequests
                .where((request) => request.wakePlanId == originalPlan.id)
                .map((request) => request.occurrenceId),
            [
              'plan-1:20640:435',
              'plan-1:20640:440',
              'plan-1:20640:445',
              'plan-1:20640:450',
            ],
            reason: inventoryCase,
          );
          expect(
            gateway.inventoryRows
                .where((row) => row.wakePlanId == originalPlan.id)
                .map((row) => row.occurrenceId),
            [
              'plan-1:20640:435',
              'plan-1:20640:440',
              'plan-1:20640:445',
              'plan-1:20640:450',
            ],
            reason: inventoryCase,
          );

          final sideEffectCount =
              gateway.cancelledOccurrences.length +
              gateway.scheduledRequests.length;
          await Future.wait([
            restarted.reconcileSchedules(),
            restarted.reconcileSchedules(),
          ]);
          expect(
            gateway.cancelledOccurrences.length +
                gateway.scheduledRequests.length,
            sideEffectCount,
            reason: inventoryCase,
          );
        }
      },
    );

    test(
      'edit crash retirement survives due time and old native events',
      () async {
        for (final scenario in [
          (
            name: 'exact-due',
            restartNow: DateTime(2026, 7, 6, 7),
            nativeStatus: NativeAlarmReservationStatus.scheduled,
            deliveredAt: null,
            expectedCanonicalIds: [
              'plan-1:20640:435',
              'plan-1:20640:440',
              'plan-1:20640:445',
              'plan-1:20640:450',
            ],
          ),
          (
            name: 'ringing-after-due',
            restartNow: DateTime(2026, 7, 6, 7, 5),
            nativeStatus: NativeAlarmReservationStatus.ringing,
            deliveredAt: DateTime(2026, 7, 6, 7),
            expectedCanonicalIds: [
              'plan-1:20640:435',
              'plan-1:20640:440',
              'plan-1:20640:445',
              'plan-1:20640:450',
            ],
          ),
          (
            name: 'missed-after-window',
            restartNow: DateTime(2026, 7, 6, 7, 20),
            nativeStatus: NativeAlarmReservationStatus.ringing,
            deliveredAt: DateTime(2026, 7, 6, 7),
            expectedCanonicalIds: ['plan-1:20640:445', 'plan-1:20640:450'],
          ),
        ]) {
          final originalPlan = buildPlan(
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final editedPlan = buildPlan(
            targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
              hour: 7,
              minute: 30,
            ),
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final oldOccurrence = buildOccurrence(
            id: occurrenceId,
            platformAlarmId: 'native-old-${scenario.name}',
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
            ..wakePlans = [originalPlan]
            ..reservedOccurrences = [oldOccurrence]
            ..storedOccurrences = [oldOccurrence]
            ..failSaveWakePlanAfterMutationAtCalls.add(1);
          final gateway = withUnavailableInventory(_CountingInventoryGateway());
          if (scenario.deliveredAt != null) {
            gateway.pendingAlarmEvents.add(
              NativeAlarmEvent(
                eventId: 'delivered-${scenario.name}',
                platformAlarmId: oldOccurrence.platformAlarmId!,
                type: NativeAlarmEventType.delivered,
                timestamp: scenario.deliveredAt!,
              ),
            );
          }

          await expectLater(
            service(store: store, gateway: gateway).editPlan(editedPlan),
            throwsA(isA<StateError>()),
            reason: scenario.name,
          );
          store
            ..wakePlans = [store.currentPlan!]
            ..failSaveWakePlanAfterMutationAtCalls.clear();
          final restarted = service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
            clockNow: scenario.restartNow,
          );

          final unavailable = await Future.wait([
            restarted.reconcileSchedules(),
            restarted.reconcileSchedules(),
          ]);
          expect(
            unavailable.first.single.status,
            WakePlanSchedulingStatus.recoveryRequired,
            reason: scenario.name,
          );
          expect(gateway.scheduledRequests, isEmpty, reason: scenario.name);
          expect(gateway.cancelledOccurrences, isEmpty, reason: scenario.name);
          expect(store.storedOccurrences.single, oldOccurrence);

          gateway
            ..capability = const NativeAlarmCapability(
              permissionStatus: NativeAlarmPermissionStatus.authorized,
              canScheduleAlarms: true,
              canRequestPermission: true,
              supportsInventory: true,
            )
            ..inventoryRows.add(
              NativeAlarmInventoryRow(
                reservationId: oldOccurrence.id,
                occurrenceId: oldOccurrence.id,
                wakePlanId: oldOccurrence.wakePlanId,
                platformAlarmId: oldOccurrence.platformAlarmId!,
                status: scenario.nativeStatus,
              ),
            );

          final authoritative = await restarted.reconcileSchedules();
          expect(
            authoritative.single.status,
            WakePlanSchedulingStatus.scheduled,
            reason: scenario.name,
          );
          expect(
            gateway.cancelledOccurrences.map(
              (request) => request.platformAlarmId,
            ),
            [oldOccurrence.platformAlarmId],
            reason: scenario.name,
          );
          expect(
            gateway.inventoryRows.map((row) => row.occurrenceId),
            scenario.expectedCanonicalIds,
            reason: scenario.name,
          );
          expect(
            store.storedOccurrences.singleWhere(
              (occurrence) => occurrence.id == oldOccurrence.id,
            ),
            isA<AlarmOccurrence>()
                .having(
                  (occurrence) => occurrence.status,
                  'status',
                  scenario.name == 'missed-after-window'
                      ? AlarmOccurrenceStatus.missed
                      : AlarmOccurrenceStatus.cancelled,
                )
                .having(
                  (occurrence) => occurrence.platformAlarmId,
                  'platformAlarmId',
                  isNull,
                )
                .having(
                  (occurrence) => occurrence.firedAt,
                  'firedAt',
                  scenario.name == 'missed-after-window'
                      ? scenario.deliveredAt
                      : null,
                ),
            reason: scenario.name,
          );

          final sideEffectCount =
              gateway.cancelledOccurrences.length +
              gateway.scheduledRequests.length;
          await Future.wait([
            restarted.reconcileSchedules(),
            restarted.reconcileSchedules(),
          ]);
          expect(
            gateway.cancelledOccurrences.length +
                gateway.scheduledRequests.length,
            sideEffectCount,
            reason: scenario.name,
          );
        }
      },
    );

    test(
      'one-time edit converges after terminal old identity persistence retry',
      () async {
        for (final terminalStatus in [
          AlarmOccurrenceStatus.missed,
          AlarmOccurrenceStatus.dismissed,
        ]) {
          final editedPlan = buildPlan(
            targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
              hour: 7,
              minute: 30,
            ),
          );
          final oldOccurrence = buildOccurrence(
            id: occurrenceId,
            status: terminalStatus,
            platformAlarmId: 'native-old-${terminalStatus.name}',
            firedAt: DateTime(2026, 7, 6, 7),
            dismissedAt: terminalStatus == AlarmOccurrenceStatus.dismissed
                ? DateTime(2026, 7, 6, 7, 1)
                : null,
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: editedPlan)
            ..wakePlans = [editedPlan]
            ..storedOccurrences = [oldOccurrence]
            ..failSaveAlarmOccurrencesAtCalls.add(1);
          final gateway = _CountingInventoryGateway()
            ..inventoryRows.add(
              NativeAlarmInventoryRow(
                reservationId: oldOccurrence.id,
                occurrenceId: oldOccurrence.id,
                wakePlanId: oldOccurrence.wakePlanId,
                platformAlarmId: oldOccurrence.platformAlarmId!,
                status: NativeAlarmReservationStatus.ringing,
              ),
            );
          final restarted = service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
            clockNow: DateTime(2026, 7, 6, 7, 20),
          );

          final failedPersistence = await restarted.reconcileSchedules();
          expect(
            failedPersistence.single.status,
            WakePlanSchedulingStatus.recoveryRequired,
            reason: terminalStatus.name,
          );
          expect(gateway.inventoryRows, isEmpty, reason: terminalStatus.name);
          expect(
            gateway.scheduledRequests,
            isEmpty,
            reason: terminalStatus.name,
          );
          expect(
            store.storedOccurrences.single.status,
            terminalStatus,
            reason: terminalStatus.name,
          );

          store.failSaveAlarmOccurrencesAtCalls.clear();
          final recovered = await restarted.reconcileSchedules();
          expect(
            recovered.single.status,
            WakePlanSchedulingStatus.scheduled,
            reason: terminalStatus.name,
          );
          expect(
            gateway.scheduledRequests.map((request) => request.occurrenceId),
            ['plan-1:20640:445', 'plan-1:20640:450'],
            reason: terminalStatus.name,
          );
          expect(
            store.storedOccurrences.singleWhere(
              (occurrence) => occurrence.id == oldOccurrence.id,
            ),
            isA<AlarmOccurrence>()
                .having(
                  (occurrence) => occurrence.status,
                  'status',
                  terminalStatus,
                )
                .having(
                  (occurrence) => occurrence.platformAlarmId,
                  'platformAlarmId',
                  isNull,
                )
                .having(
                  (occurrence) => occurrence.firedAt,
                  'firedAt',
                  oldOccurrence.firedAt,
                )
                .having(
                  (occurrence) => occurrence.dismissedAt,
                  'dismissedAt',
                  oldOccurrence.dismissedAt,
                ),
            reason: terminalStatus.name,
          );

          final sideEffectCount =
              gateway.cancelledOccurrences.length +
              gateway.scheduledRequests.length;
          await Future.wait([
            restarted.reconcileSchedules(),
            restarted.reconcileSchedules(),
          ]);
          expect(
            gateway.cancelledOccurrences.length +
                gateway.scheduledRequests.length,
            sideEffectCount,
            reason: terminalStatus.name,
          );
        }
      },
    );

    test(
      'edit retirement preserves terminal identity until event ack replays',
      () async {
        final eventAt = DateTime(2026, 7, 6, 7, 1);
        final editedPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 7,
            minute: 30,
          ),
        );
        final oldOccurrence = buildOccurrence(
          id: occurrenceId,
          platformAlarmId: 'native-old-event',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: editedPlan)
          ..wakePlans = [editedPlan]
          ..storedOccurrences = [oldOccurrence];
        final gateway = _FailingAckGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: oldOccurrence.id,
              occurrenceId: oldOccurrence.id,
              wakePlanId: oldOccurrence.wakePlanId,
              platformAlarmId: oldOccurrence.platformAlarmId!,
              status: NativeAlarmReservationStatus.ringing,
            ),
          )
          ..pendingAlarmEvents.add(
            NativeAlarmEvent(
              eventId: 'dismiss-old-edit',
              platformAlarmId: oldOccurrence.platformAlarmId!,
              type: NativeAlarmEventType.dismissed,
              timestamp: eventAt,
            ),
          );
        final restarted = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
          clockNow: eventAt,
        );

        final first = await restarted.reconcileSchedules();
        expect(first.single.status, WakePlanSchedulingStatus.scheduled);
        expect(gateway.pendingAlarmEvents, hasLength(1));
        expect(gateway.inventoryRows, hasLength(4));
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          [
            'plan-1:20640:435',
            'plan-1:20640:440',
            'plan-1:20640:445',
            'plan-1:20640:450',
          ],
        );
        expect(
          store.storedOccurrences.singleWhere(
            (occurrence) => occurrence.id == oldOccurrence.id,
          ),
          isA<AlarmOccurrence>()
              .having(
                (occurrence) => occurrence.status,
                'status',
                AlarmOccurrenceStatus.dismissed,
              )
              .having(
                (occurrence) => occurrence.platformAlarmId,
                'platformAlarmId',
                oldOccurrence.platformAlarmId,
              )
              .having((occurrence) => occurrence.firedAt, 'firedAt', eventAt)
              .having(
                (occurrence) => occurrence.dismissedAt,
                'dismissedAt',
                eventAt,
              ),
        );

        gateway.failAcknowledgement = false;
        final sideEffectCount =
            gateway.cancelledOccurrences.length +
            gateway.scheduledRequests.length;
        await restarted.reconcileSchedules();
        expect(gateway.pendingAlarmEvents, isEmpty);
        expect(
          gateway.cancelledOccurrences.length +
              gateway.scheduledRequests.length,
          sideEffectCount,
        );
        expect(
          store.storedOccurrences.singleWhere(
            (occurrence) => occurrence.id == oldOccurrence.id,
          ),
          isA<AlarmOccurrence>()
              .having(
                (occurrence) => occurrence.status,
                'status',
                AlarmOccurrenceStatus.dismissed,
              )
              .having(
                (occurrence) => occurrence.platformAlarmId,
                'platformAlarmId',
                isNull,
              )
              .having((occurrence) => occurrence.firedAt, 'firedAt', eventAt)
              .having(
                (occurrence) => occurrence.dismissedAt,
                'dismissedAt',
                eventAt,
              ),
        );

        await Future.wait([
          restarted.reconcileSchedules(),
          restarted.reconcileSchedules(),
        ]);
        expect(
          gateway.cancelledOccurrences.length +
              gateway.scheduledRequests.length,
          sideEffectCount,
        );
      },
    );

    test('read failure does not block an unrelated safe plan', () async {
      final secondPlan = buildPlan(
        id: 'plan-2',
        startOffset: Duration.zero,
        repeatRule: RepeatRule.weekly({Weekday.monday}),
      );
      final pending = buildOccurrence(
        id: occurrenceId,
        status: AlarmOccurrenceStatus.userEnablePending,
        platformAlarmId: null,
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..wakePlans = [plan, secondPlan]
        ..storedOccurrences = [pending];
      final gateway = _CountingInventoryGateway(throwOnRead: true);

      final results = await service(
        store: store,
        gateway: gateway,
        rollingScheduleDays: 1,
      ).reconcileSchedules();

      expect(results, hasLength(2));
      expect(results, everyElement(isA<WakePlanSchedulingResult>()));
      expect(gateway.inventoryCalls, 1);
      expect(gateway.scheduledRequests.map((request) => request.wakePlanId), [
        'plan-2',
      ]);
    });

    test(
      'expired one-time history settles as missed without reactivation',
      () async {
        final eventNow = DateTime(2026, 7, 6, 8);
        final expiredPlan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'expired-current',
          platformAlarmId: 'native-expired',
        );
        final database = WakePlanDatabase(NativeDatabase.memory());
        final repository = WakePlanRepository(database);
        final gateway = FakeNativeAlarmGateway()
          ..pendingAlarmEvents.add(
            NativeAlarmEvent(
              eventId: 'delivered-expired',
              platformAlarmId: 'native-expired',
              type: NativeAlarmEventType.delivered,
              timestamp: eventNow.subtract(const Duration(minutes: 5)),
            ),
          );
        try {
          await repository.saveWakePlan(expiredPlan);
          await repository.saveAlarmOccurrences([occurrence]);

          final results = await WakePlanService(
            repository: repository,
            nativeAlarmGateway: gateway,
            coordinator: WakePlanMutationCoordinator(),
            clock: () => eventNow,
          ).reconcileSchedules();

          final persisted = await repository.fetchAlarmOccurrence(
            occurrence.id,
          );
          expect(results, isEmpty);
          expect(persisted!.status, AlarmOccurrenceStatus.missed);
          expect(gateway.scheduledRequests, isEmpty);
          expect(gateway.acknowledgedAlarmEventIds, ['delivered-expired']);
        } finally {
          await database.close();
        }
      },
    );

    test('per-plan prewrite failure continues with later plans', () async {
      final secondPlan = buildPlan(
        id: 'plan-2',
        startOffset: Duration.zero,
        repeatRule: RepeatRule.weekly({Weekday.monday}),
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..wakePlans = [plan, secondPlan]
        ..failSaveAlarmOccurrencesAtCalls.add(1);
      final gateway = _CountingInventoryGateway();

      final results = await service(
        store: store,
        gateway: gateway,
        rollingScheduleDays: 1,
      ).reconcileSchedules();

      expect(results.map((result) => result.status), [
        WakePlanSchedulingStatus.recoveryRequired,
        WakePlanSchedulingStatus.scheduled,
      ]);
      expect(gateway.scheduledRequests.map((request) => request.wakePlanId), [
        'plan-2',
      ]);
    });

    for (final failurePoint in ['lost reply', 'post-result persistence']) {
      test(
        '$failurePoint converges after restart without duplicates',
        () async {
          final secondPlan = buildPlan(
            id: 'plan-2',
            startOffset: Duration.zero,
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: plan)
            ..wakePlans = [plan, secondPlan];
          final gateway = _PostSideEffectThrowingGateway(
            throwAfterSchedule: failurePoint == 'lost reply',
          );
          if (failurePoint == 'post-result persistence') {
            store.failSaveAlarmOccurrencesAtCalls.add(2);
          }

          final first = await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          ).reconcileSchedules();
          final scheduleCount = gateway.scheduledRequests.length;
          final reopened = await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          ).reconcileSchedules();

          expect(first, hasLength(2));
          expect(reopened, hasLength(2));
          expect(gateway.scheduledRequests, hasLength(scheduleCount));
          expect(gateway.inventoryRows, hasLength(2));
          expect(
            store.storedOccurrences.map(
              (occurrence) => occurrence.platformAlarmId,
            ),
            everyElement(isNotNull),
          );
        },
      );
    }

    test(
      'lost reply converges after file-backed Drift close and reopen',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'calarm-task13-',
        );
        final file = File('${directory.path}/wake-plan.sqlite');
        final gateway = _PostSideEffectThrowingGateway(
          throwAfterSchedule: true,
        );
        try {
          var database = WakePlanDatabase(NativeDatabase(file));
          var repository = WakePlanRepository(database);
          await repository.saveWakePlan(plan);
          final first = await WakePlanService(
            repository: repository,
            nativeAlarmGateway: gateway,
            coordinator: WakePlanMutationCoordinator(),
            clock: () => now,
            rollingScheduleDays: 1,
          ).reconcileSchedules();
          expect(
            first.single.status,
            WakePlanSchedulingStatus.recoveryRequired,
          );
          await database.close();

          database = WakePlanDatabase(NativeDatabase(file));
          repository = WakePlanRepository(database);
          final reopened = await WakePlanService(
            repository: repository,
            nativeAlarmGateway: gateway,
            coordinator: WakePlanMutationCoordinator(),
            clock: () => now,
            rollingScheduleDays: 1,
          ).reconcileSchedules();
          final persisted = await repository.fetchOccurrencesForPlan(plan.id);

          expect(reopened.single.status, WakePlanSchedulingStatus.scheduled);
          expect(gateway.scheduledRequests, hasLength(1));
          expect(persisted.single.platformAlarmId, isNotNull);
          await database.close();
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );

    test(
      'constructor-invalid suppressed row retains native alarm and off intent',
      () async {
        final database = WakePlanDatabase(NativeDatabase.memory());
        final repository = WakePlanRepository(database);
        final occurrenceId = 'plan-1:20640:420';
        final gateway = _CountingInventoryGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrenceId,
              occurrenceId: occurrenceId,
              wakePlanId: plan.id,
              platformAlarmId: 'native-exact',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );
        try {
          await repository.saveWakePlan(plan);
          await repository.saveWakePlan(
            buildPlan(
              id: 'safe-plan',
              startOffset: Duration.zero,
              repeatRule: RepeatRule.weekly({Weekday.monday}),
            ),
          );
          await database
              .into(database.alarmOccurrenceRows)
              .insert(
                AlarmOccurrenceRowsCompanion.insert(
                  id: occurrenceId,
                  wakePlanId: plan.id,
                  scheduledAtDays: monday.daysSinceUnixEpoch,
                  scheduledAtMinutes: targetTime.minutesSinceMidnight,
                  status: AlarmOccurrenceStatus.userDisabled.name,
                  platformAlarmId: const Value('native-exact'),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          final serviceUnderTest = WakePlanService(
            repository: repository,
            nativeAlarmGateway: gateway,
            coordinator: WakePlanMutationCoordinator(),
            clock: () => now,
            rollingScheduleDays: 1,
          );

          final first = await serviceUnderTest.reconcileSchedules();
          await Future.wait([
            serviceUnderTest.reconcileSchedules(),
            serviceUnderTest.reconcileSchedules(),
          ]);
          final persisted = await (database.select(
            database.alarmOccurrenceRows,
          )..where((row) => row.id.equals(occurrenceId))).getSingle();

          expect(first, hasLength(2));
          expect(
            first.singleWhere((result) => result.wakePlanId == plan.id).status,
            WakePlanSchedulingStatus.recoveryRequired,
          );
          expect(
            first
                .singleWhere((result) => result.wakePlanId == 'safe-plan')
                .status,
            WakePlanSchedulingStatus.scheduled,
          );
          expect(persisted.status, AlarmOccurrenceStatus.userDisabled.name);
          expect(persisted.platformAlarmId, 'native-exact');
          expect(
            gateway.scheduledRequests.map((request) => request.wakePlanId),
            ['safe-plan'],
          );
          expect(gateway.cancelledOccurrences, isEmpty);
          expect(gateway.inventoryRows, hasLength(2));
        } finally {
          await database.close();
        }
      },
    );

    test(
      'undecodable plan retains its exact native occurrence and reports recovery',
      () async {
        final database = WakePlanDatabase(NativeDatabase.memory());
        final repository = WakePlanRepository(database);
        const malformedPlanId = 'malformed-plan';
        const occurrenceId = 'malformed-plan:20640:420';
        final gateway = _CountingInventoryGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrenceId,
              occurrenceId: occurrenceId,
              wakePlanId: malformedPlanId,
              platformAlarmId: 'native-exact',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );
        try {
          await database
              .into(database.wakePlanRows)
              .insert(
                WakePlanRowsCompanion.insert(
                  id: malformedPlanId,
                  title: 'Malformed',
                  targetTimeMinutes: targetTime.minutesSinceMidnight,
                  startOffsetMinutes: 60,
                  intervalMinutes: 5,
                  repeatType: RepeatType.weekly.name,
                  isEnabled: true,
                  status: WakePlanStatus.scheduled.name,
                  soundId: 'default',
                  vibrationEnabled: true,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          await database
              .into(database.alarmOccurrenceRows)
              .insert(
                AlarmOccurrenceRowsCompanion.insert(
                  id: occurrenceId,
                  wakePlanId: malformedPlanId,
                  scheduledAtDays: monday.daysSinceUnixEpoch,
                  scheduledAtMinutes: targetTime.minutesSinceMidnight,
                  status: AlarmOccurrenceStatus.scheduled.name,
                  platformAlarmId: const Value('native-exact'),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          final serviceUnderTest = WakePlanService(
            repository: repository,
            nativeAlarmGateway: gateway,
            coordinator: WakePlanMutationCoordinator(),
            clock: () => now,
            rollingScheduleDays: 1,
          );

          final first = await serviceUnderTest.reconcileSchedules();
          await Future.wait([
            serviceUnderTest.reconcileSchedules(),
            serviceUnderTest.reconcileSchedules(),
          ]);
          final persisted = await (database.select(
            database.alarmOccurrenceRows,
          )..where((row) => row.id.equals(occurrenceId))).getSingle();

          expect(first.single.wakePlanId, malformedPlanId);
          expect(
            first.single.status,
            WakePlanSchedulingStatus.recoveryRequired,
          );
          expect(persisted.status, AlarmOccurrenceStatus.scheduled.name);
          expect(persisted.platformAlarmId, 'native-exact');
          expect(gateway.scheduledRequests, isEmpty);
          expect(gateway.cancelledOccurrences, isEmpty);
          expect(gateway.inventoryRows, hasLength(1));
        } finally {
          await database.close();
        }
      },
    );

    test('expired one-time history does not re-enter reconciliation', () async {
      final database = WakePlanDatabase(NativeDatabase.memory());
      final repository = WakePlanRepository(database);
      final expiredPlan = buildPlan();
      final gateway = _CountingInventoryGateway();
      try {
        await repository.saveWakePlan(expiredPlan);
        await repository.saveAlarmOccurrences([
          AlarmOccurrence(
            id: 'expired-recovery-marker',
            wakePlanId: expiredPlan.id,
            scheduledAt: DateMinute(day: tuesday, time: targetTime),
            status: AlarmOccurrenceStatus.userEnablePending,
            createdAt: now,
            updatedAt: now,
          ),
        ]);

        final results = await WakePlanService(
          repository: repository,
          nativeAlarmGateway: gateway,
          coordinator: WakePlanMutationCoordinator(),
          clock: () => DateTime(2026, 7, 6, 8),
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(results, isEmpty);
        expect(gateway.scheduledRequests, isEmpty);
        expect(gateway.cancelledOccurrences, isEmpty);
      } finally {
        await database.close();
      }
    });
  });

  group('WakePlanService occurrence toggles', () {
    test(
      'off survives reconciliation and restart before exact re-enable',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          platformAlarmId: 'native-final',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = FakeNativeAlarmGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: 'native-final',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );
        final firstService = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );

        final disabled = await firstService.setOccurrenceEnabled(
          wakePlanId: plan.id,
          occurrenceId: occurrence.id,
          enabled: false,
        );

        expect(disabled.status, AlarmOccurrenceToggleStatus.disabled);
        expect(disabled.occurrence!.status, AlarmOccurrenceStatus.userDisabled);
        expect(
          gateway.cancelledOccurrences.single.reservationId,
          occurrence.id,
        );
        expect(gateway.inventoryRows, isEmpty);

        gateway.scheduledRequests.clear();
        await firstService.reconcileSchedules();
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          isNot(contains(occurrence.id)),
        );

        gateway.scheduledRequests.clear();
        final restartedService = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );
        await restartedService.reconcileSchedules();
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          isNot(contains(occurrence.id)),
        );

        gateway.scheduledRequests.clear();
        final enabled = await restartedService.setOccurrenceEnabled(
          wakePlanId: plan.id,
          occurrenceId: occurrence.id,
          enabled: true,
        );

        expect(enabled.status, AlarmOccurrenceToggleStatus.enabled);
        expect(gateway.scheduledRequests, hasLength(1));
        expect(gateway.scheduledRequests.single.occurrenceId, occurrence.id);
        expect(gateway.scheduledRequests.single.reservationId, occurrence.id);
        expect(
          gateway.scheduledRequests.single.scheduledAt,
          DateTime(2026, 7, 6, 7),
        );
        expect(
          gateway.scheduledRequests.single.targetAt,
          DateTime(2026, 7, 6, 7),
        );
        final inventoryRow = gateway.inventoryRows.singleWhere(
          (row) => row.occurrenceId == occurrence.id,
        );
        expect(inventoryRow.reservationId, occurrence.id);
        expect(
          inventoryRow.platformAlarmId,
          enabled.occurrence!.platformAlarmId,
        );

        await Future.wait([
          restartedService.setOccurrenceEnabled(
            wakePlanId: plan.id,
            occurrenceId: occurrence.id,
            enabled: true,
          ),
          restartedService.setOccurrenceEnabled(
            wakePlanId: plan.id,
            occurrenceId: occurrence.id,
            enabled: true,
          ),
        ]);
        expect(gateway.scheduledRequests, hasLength(1));
      },
    );

    test('does not resurrect a disabled occurrence exactly at now', () async {
      final exactNow = DateTime(2026, 7, 6, 7);
      final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
      final occurrence = buildOccurrence(
        id: 'plan-1:20640:420',
        status: AlarmOccurrenceStatus.userDisabled,
        platformAlarmId: null,
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..wakePlans = [plan]
        ..storedOccurrences = [occurrence];
      final gateway = FakeNativeAlarmGateway();

      await service(
        store: store,
        gateway: gateway,
        clockNow: exactNow,
        rollingScheduleDays: 1,
      ).reconcileSchedules();

      expect(
        gateway.scheduledRequests.map((request) => request.occurrenceId),
        isNot(contains(occurrence.id)),
      );
      expect(gateway.scheduledRequests, hasLength(4));
      expect(
        gateway.scheduledRequests.every(
          (request) => request.scheduledAt.isAfter(exactNow),
        ),
        isTrue,
      );
      expect(
        store.storedOccurrences
            .singleWhere((item) => item.id == occurrence.id)
            .status,
        AlarmOccurrenceStatus.userDisabled,
      );
    });

    test(
      're-enables a cross-midnight occurrence with its owning target',
      () async {
        final crossMidnightNow = DateTime(2026, 7, 6, 23);
        final targetDay = CalendarDay(year: 2026, month: 7, day: 7);
        final plan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 0,
            minute: 10,
          ),
          startOffset: const Duration(minutes: 30),
          interval: const Duration(minutes: 10),
          repeatRule: RepeatRule.oneTime(targetDay),
        );
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:1420',
          day: monday,
          time: TimeOfDayMinutes.fromHourMinute(hour: 23, minute: 40),
          status: AlarmOccurrenceStatus.userDisabled,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..storedOccurrences = [occurrence];
        final gateway = FakeNativeAlarmGateway();

        final result =
            await service(
              store: store,
              gateway: gateway,
              clockNow: crossMidnightNow,
            ).setOccurrenceEnabled(
              wakePlanId: plan.id,
              occurrenceId: occurrence.id,
              enabled: true,
            );

        expect(result.status, AlarmOccurrenceToggleStatus.enabled);
        expect(
          gateway.scheduledRequests.single.scheduledAt,
          DateTime(2026, 7, 6, 23, 40),
        );
        expect(
          gateway.scheduledRequests.single.targetAt,
          DateTime(2026, 7, 7, 0, 10),
        );
      },
    );

    test(
      'definite enable rejection stays disabled and retries exactly once',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          status: AlarmOccurrenceStatus.userDisabled,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = FakeNativeAlarmGateway()
          ..scheduleFailureOccurrenceIds.add(occurrence.id);
        final serviceUnderTest = service(store: store, gateway: gateway);

        final rejected = await serviceUnderTest.setOccurrenceEnabled(
          wakePlanId: plan.id,
          occurrenceId: occurrence.id,
          enabled: true,
        );

        expect(rejected.status, AlarmOccurrenceToggleStatus.scheduleFailed);
        expect(rejected.occurrence!.status, AlarmOccurrenceStatus.userDisabled);
        expect(rejected.occurrence!.platformAlarmId, isNull);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.userDisabled,
        );
        expect(store.storedOccurrences.single.platformAlarmId, isNull);
        expect(gateway.inventoryRows, isEmpty);

        gateway.scheduleFailureOccurrenceIds.clear();
        final enabled = await serviceUnderTest.setOccurrenceEnabled(
          wakePlanId: plan.id,
          occurrenceId: occurrence.id,
          enabled: true,
        );

        expect(enabled.status, AlarmOccurrenceToggleStatus.enabled);
        expect(enabled.occurrence!.status, AlarmOccurrenceStatus.scheduled);
        expect(enabled.occurrence!.hasNativeReservation, isTrue);
        expect(gateway.scheduledRequests, hasLength(2));
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          hasLength(1),
        );
      },
    );

    test(
      'persists pending off intent when cancellation reports failure',
      () async {
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          platformAlarmId: 'native-future',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..storedOccurrences = [occurrence];
        final gateway = FakeNativeAlarmGateway()
          ..cancelFailurePlatformAlarmIds.add('native-future')
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: 'native-future',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );

        final result = await service(store: store, gateway: gateway)
            .setOccurrenceEnabled(
              wakePlanId: plan.id,
              occurrenceId: occurrence.id,
              enabled: false,
            );

        expect(result.status, AlarmOccurrenceToggleStatus.recoveryRequired);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.userDisablePending,
        );
        expect(store.storedOccurrences.single.platformAlarmId, 'native-future');
      },
    );

    test(
      'does not cancel the native reservation when off intent persistence fails',
      () async {
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          platformAlarmId: 'native-future',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..storedOccurrences = [occurrence]
          ..failSaveAlarmOccurrencesAtCalls.add(1);
        final gateway = FakeNativeAlarmGateway();

        final result = await service(store: store, gateway: gateway)
            .setOccurrenceEnabled(
              wakePlanId: plan.id,
              occurrenceId: occurrence.id,
              enabled: false,
            );

        expect(result.status, AlarmOccurrenceToggleStatus.recoveryRequired);
        expect(result.compensationScheduleResult, isNull);
        expect(gateway.cancelledOccurrences, isEmpty);
        expect(
          gateway.scheduledRequests.where(
            (request) => request.occurrenceId == occurrence.id,
          ),
          isEmpty,
        );
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(
          store.storedOccurrences.single.platformAlarmId,
          occurrence.platformAlarmId,
        );
      },
    );

    test('persists pending off intent when cancellation throws', () async {
      final plan = buildPlan();
      final occurrence = buildOccurrence(
        id: 'plan-1:20640:420',
        platformAlarmId: 'native-future-throw',
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..storedOccurrences = [occurrence];
      final gateway = _ThrowingOccurrenceGateway(throwOnCancel: true)
        ..inventoryRows.add(
          NativeAlarmInventoryRow(
            reservationId: occurrence.id,
            occurrenceId: occurrence.id,
            wakePlanId: plan.id,
            platformAlarmId: 'native-future-throw',
            status: NativeAlarmReservationStatus.scheduled,
          ),
        );

      final result = await service(store: store, gateway: gateway)
          .setOccurrenceEnabled(
            wakePlanId: plan.id,
            occurrenceId: occurrence.id,
            enabled: false,
          );

      expect(result.status, AlarmOccurrenceToggleStatus.recoveryRequired);
      expect(result.warning, contains('still being turned off'));
      expect(
        store.storedOccurrences.single.status,
        AlarmOccurrenceStatus.userDisablePending,
      );
    });

    test(
      'restarts a future one-time off after cancellation fails before effect',
      () async {
        for (final failureMode in ['reported', 'thrown']) {
          final plan = buildPlan();
          final occurrence = buildOccurrence(
            id: 'plan-1:20640:420',
            reservationId: 'stable-$failureMode-slot',
            reservationGeneration: 4,
            platformAlarmId: 'native-$failureMode',
          );
          final gateway =
              failureMode == 'thrown'
                    ? _OneShotCancelExceptionGateway()
                    : FakeNativeAlarmGateway()
                ..cancelFailurePlatformAlarmIds.add(
                  occurrence.platformAlarmId!,
                );
          gateway.inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.reservationId,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: occurrence.platformAlarmId!,
              status: NativeAlarmReservationStatus.scheduled,
              reservationGeneration: occurrence.reservationGeneration,
            ),
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: plan)
            ..wakePlans = [plan]
            ..storedOccurrences = [occurrence];

          final toggled = await service(store: store, gateway: gateway)
              .setOccurrenceEnabled(
                wakePlanId: plan.id,
                occurrenceId: occurrence.id,
                enabled: false,
              );

          expect(
            toggled.status,
            AlarmOccurrenceToggleStatus.recoveryRequired,
            reason: failureMode,
          );
          expect(
            store.storedOccurrences.single.status,
            AlarmOccurrenceStatus.userDisablePending,
            reason: failureMode,
          );
          expect(gateway.inventoryRows, hasLength(1), reason: failureMode);
          gateway.cancelFailurePlatformAlarmIds.clear();

          final restarted = await service(
            store: store,
            gateway: gateway,
          ).reconcileSchedules();

          expect(restarted, hasLength(1), reason: failureMode);
          expect(
            store.storedOccurrences.single.status,
            AlarmOccurrenceStatus.userDisabled,
            reason: failureMode,
          );
          expect(gateway.inventoryRows, isEmpty, reason: failureMode);
          expect(
            gateway.scheduledRequests.where(
              (request) => request.occurrenceId == occurrence.id,
            ),
            isEmpty,
            reason: failureMode,
          );
        }
      },
    );

    test(
      'restarts one-time off after cancellation succeeds before response throws',
      () async {
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          platformAlarmId: 'native-post-cancel-throw',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = _PostSideEffectThrowingGateway(throwAfterCancel: true)
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: 'native-post-cancel-throw',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );

        final result = await service(store: store, gateway: gateway)
            .setOccurrenceEnabled(
              wakePlanId: plan.id,
              occurrenceId: occurrence.id,
              enabled: false,
            );

        expect(result.status, AlarmOccurrenceToggleStatus.recoveryRequired);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.userDisablePending,
        );
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          isEmpty,
        );

        final reconciliation = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(
          reconciliation.single.status,
          WakePlanSchedulingStatus.scheduled,
        );
        expect(
          store.storedOccurrences
              .singleWhere((item) => item.id == occurrence.id)
              .status,
          AlarmOccurrenceStatus.userDisabled,
        );
        expect(
          gateway.scheduledRequests.where(
            (request) => request.occurrenceId == occurrence.id,
          ),
          isEmpty,
        );
      },
    );

    test(
      'reports pending-off persistence failure and completes it after restart',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          platformAlarmId: 'native-pending-off',
          status: AlarmOccurrenceStatus.userDisablePending,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence]
          ..failSaveAlarmOccurrencesAtCalls.add(1);
        final gateway = FakeNativeAlarmGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: occurrence.platformAlarmId!,
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );

        final failedPersistence = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(
          failedPersistence.single.status,
          WakePlanSchedulingStatus.recoveryRequired,
        );
        expect(
          failedPersistence.single.databaseState,
          WakePlanDatabaseState.unknown,
        );
        expect(failedPersistence.single.persistenceError, isNotNull);
        expect(
          failedPersistence.single.occurrences
              .singleWhere((item) => item.id == occurrence.id)
              .status,
          AlarmOccurrenceStatus.userDisablePending,
        );
        expect(
          store.storedOccurrences
              .singleWhere((item) => item.id == occurrence.id)
              .status,
          AlarmOccurrenceStatus.userDisablePending,
        );
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          isEmpty,
        );

        final afterRestart = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(afterRestart.single.status, WakePlanSchedulingStatus.scheduled);
        expect(afterRestart.single.persistenceError, isNull);
        expect(
          store.storedOccurrences
              .singleWhere((item) => item.id == occurrence.id)
              .status,
          AlarmOccurrenceStatus.userDisabled,
        );
        expect(
          gateway.scheduledRequests.where(
            (request) => request.occurrenceId == occurrence.id,
          ),
          isEmpty,
        );
      },
    );

    test(
      'does not start uncertain cancellation when off intent cannot persist',
      () async {
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          platformAlarmId: 'native-uncertain-off',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..storedOccurrences = [occurrence]
          ..failSaveAlarmOccurrencesAtCalls.add(1);
        final gateway = _PostSideEffectThrowingGateway(throwAfterCancel: true)
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: occurrence.platformAlarmId!,
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );

        final result = await service(store: store, gateway: gateway)
            .setOccurrenceEnabled(
              wakePlanId: plan.id,
              occurrenceId: occurrence.id,
              enabled: false,
            );

        expect(result.status, AlarmOccurrenceToggleStatus.recoveryRequired);
        expect(result.compensationScheduleResult, isNull);
        expect(gateway.cancelledOccurrences, isEmpty);
        expect(
          gateway.scheduledRequests.where(
            (request) => request.occurrenceId == occurrence.id,
          ),
          isEmpty,
        );
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(store.storedOccurrences.single.platformAlarmId, isNotNull);
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          hasLength(1),
        );
      },
    );

    test(
      'restart resolves a crash after native cancel before disabled persistence',
      () async {
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          platformAlarmId: 'native-crash-seam',
        );
        final crashingStore = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence]
          ..blockSaveAlarmOccurrencesAtCall = 2;
        final gateway = FakeNativeAlarmGateway()
          ..inventoryRows.add(
            inventoryRow(
              occurrence,
              platformAlarmId: occurrence.platformAlarmId!,
            ),
          );

        final inFlightToggle = service(store: crashingStore, gateway: gateway)
            .setOccurrenceEnabled(
              wakePlanId: plan.id,
              occurrenceId: occurrence.id,
              enabled: false,
            );
        await crashingStore.saveAlarmOccurrencesBlocked.future;

        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          isEmpty,
        );
        expect(
          crashingStore.storedOccurrences.single.status,
          AlarmOccurrenceStatus.userDisablePending,
        );
        expect(
          crashingStore.storedOccurrences.single.platformAlarmId,
          occurrence.platformAlarmId,
        );

        final restartedStore = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [crashingStore.storedOccurrences.single];
        final restarted = await service(
          store: restartedStore,
          gateway: gateway,
        ).reconcileSchedules();

        expect(restarted.single.status, WakePlanSchedulingStatus.scheduled);
        expect(
          restartedStore.storedOccurrences.single.status,
          AlarmOccurrenceStatus.userDisabled,
        );
        expect(restartedStore.storedOccurrences.single.platformAlarmId, isNull);
        expect(gateway.cancelledOccurrences, hasLength(1));
        expect(gateway.scheduledRequests, isEmpty);
        expect(gateway.inventoryRows, isEmpty);

        crashingStore.releaseBlockedSave.complete();
        await inFlightToggle;
      },
    );

    test(
      'cancels a newly scheduled alarm when its result cannot persist',
      () async {
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          status: AlarmOccurrenceStatus.userDisabled,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..storedOccurrences = [occurrence]
          ..failSaveAlarmOccurrencesAtCalls.add(2);
        final gateway = FakeNativeAlarmGateway();

        final result = await service(store: store, gateway: gateway)
            .setOccurrenceEnabled(
              wakePlanId: plan.id,
              occurrenceId: occurrence.id,
              enabled: true,
            );

        expect(result.status, AlarmOccurrenceToggleStatus.recoveryRequired);
        expect(result.compensationCancelResult!.isSuccess, isTrue);
        expect(gateway.inventoryRows, isEmpty);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.userDisabled,
        );
      },
    );

    test('keeps durable on intent when native scheduling throws', () async {
      final plan = buildPlan();
      final occurrence = buildOccurrence(
        id: 'plan-1:20640:420',
        status: AlarmOccurrenceStatus.userDisabled,
        platformAlarmId: null,
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..storedOccurrences = [occurrence];
      final gateway = _ThrowingOccurrenceGateway(throwOnSchedule: true);

      final result = await service(store: store, gateway: gateway)
          .setOccurrenceEnabled(
            wakePlanId: plan.id,
            occurrenceId: occurrence.id,
            enabled: true,
          );

      expect(result.status, AlarmOccurrenceToggleStatus.recoveryRequired);
      expect(result.warning, contains('will be reconciled'));
      expect(
        store.storedOccurrences.single.status,
        AlarmOccurrenceStatus.userEnablePending,
      );
      expect(store.storedOccurrences.single.platformAlarmId, isNull);
      expect(gateway.inventoryRows, isEmpty);
    });

    test(
      'restarts final one-time on with canonical metadata and no duplicates',
      () async {
        final plan = buildPlan(startOffset: const Duration(hours: 1));
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          status: AlarmOccurrenceStatus.userDisabled,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = _PostSideEffectThrowingGateway(
          throwAfterSchedule: true,
        );

        final result = await service(store: store, gateway: gateway)
            .setOccurrenceEnabled(
              wakePlanId: plan.id,
              occurrenceId: occurrence.id,
              enabled: true,
            );

        expect(result.status, AlarmOccurrenceToggleStatus.recoveryRequired);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.userEnablePending,
        );
        expect(store.storedOccurrences.single.platformAlarmId, isNull);
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          hasLength(1),
        );
        expect(gateway.scheduledRequests.single.reservationId, occurrence.id);
        expect(
          gateway.inventoryRows
              .singleWhere((row) => row.occurrenceId == occurrence.id)
              .reservationId,
          occurrence.id,
        );

        await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(
          store.storedOccurrences
              .singleWhere((item) => item.id == occurrence.id)
              .platformAlarmId,
          gateway.inventoryRows
              .singleWhere((row) => row.occurrenceId == occurrence.id)
              .platformAlarmId,
        );
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          hasLength(1),
        );
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          [occurrence.id],
        );
        expect(
          gateway.scheduledRequests.map((request) => request.indexInPlan),
          [12],
        );
        expect(
          gateway.scheduledRequests.map((request) => request.totalInPlan),
          [13],
        );
      },
    );

    test(
      'restarts cross-midnight on with canonical metadata and stable identity',
      () async {
        final crossMidnightNow = DateTime(2026, 7, 6, 23);
        final targetDay = CalendarDay(year: 2026, month: 7, day: 7);
        final plan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 0,
            minute: 10,
          ),
          startOffset: const Duration(minutes: 30),
          interval: const Duration(minutes: 10),
          repeatRule: RepeatRule.oneTime(targetDay),
        );
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:1430',
          day: monday,
          time: TimeOfDayMinutes.fromHourMinute(hour: 23, minute: 50),
          status: AlarmOccurrenceStatus.userDisabled,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = _PostSideEffectThrowingGateway(
          throwAfterSchedule: true,
        );

        final toggled =
            await service(
              store: store,
              gateway: gateway,
              clockNow: crossMidnightNow,
            ).setOccurrenceEnabled(
              wakePlanId: plan.id,
              occurrenceId: occurrence.id,
              enabled: true,
            );
        expect(toggled.status, AlarmOccurrenceToggleStatus.recoveryRequired);

        await service(
          store: store,
          gateway: gateway,
          clockNow: crossMidnightNow,
        ).reconcileSchedules();

        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          [occurrence.id],
        );
        expect(
          gateway.scheduledRequests.map((request) => request.indexInPlan),
          [1],
        );
        expect(
          gateway.scheduledRequests.map((request) => request.totalInPlan),
          [4],
        );
        expect(gateway.scheduledRequests.map((request) => request.targetAt), [
          DateTime(2026, 7, 7, 0, 10),
        ]);
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          hasLength(1),
        );
      },
    );

    test(
      'skips exact-now one-time recovery markers without native side effects',
      () async {
        final exactNow = DateTime(2026, 7, 6, 7);
        for (final marker in [
          buildOccurrence(
            id: 'plan-1:20640:420',
            status: AlarmOccurrenceStatus.userDisablePending,
            platformAlarmId: 'native-pending',
          ),
          buildOccurrence(
            id: 'plan-1:20640:420',
            status: AlarmOccurrenceStatus.scheduled,
            platformAlarmId: null,
          ),
        ]) {
          final plan = buildPlan();
          final store = _LoggingWakePlanServiceStore(currentPlan: plan)
            ..wakePlans = [plan]
            ..storedOccurrences = [marker];
          final gateway = FakeNativeAlarmGateway();
          if (marker.platformAlarmId != null) {
            gateway.inventoryRows.add(
              NativeAlarmInventoryRow(
                reservationId: marker.id,
                occurrenceId: marker.id,
                wakePlanId: plan.id,
                platformAlarmId: marker.platformAlarmId!,
                status: NativeAlarmReservationStatus.scheduled,
              ),
            );
          }

          final reconciled = await service(
            store: store,
            gateway: gateway,
            clockNow: exactNow,
          ).reconcileSchedules();

          expect(reconciled, isEmpty, reason: marker.status.name);
          expect(
            gateway.cancelledOccurrences,
            isEmpty,
            reason: marker.status.name,
          );
          expect(
            gateway.scheduledRequests,
            isEmpty,
            reason: marker.status.name,
          );
          expect(store.savedOccurrences, isEmpty, reason: marker.status.name);
          expect(
            store.storedOccurrences.single.status,
            marker.status,
            reason: marker.status.name,
          );
          expect(
            store.storedOccurrences.single.platformAlarmId,
            marker.platformAlarmId,
            reason: marker.status.name,
          );
        }
      },
    );

    test(
      'skips ineligible one-time recovery boundaries without replenishment',
      () async {
        final scenarios =
            <({String name, WakePlan plan, AlarmOccurrence occurrence})>[
              (
                name: 'past',
                plan: buildPlan(),
                occurrence: buildOccurrence(
                  id: 'plan-1:20640:330',
                  time: TimeOfDayMinutes.fromHourMinute(hour: 5, minute: 30),
                  status: AlarmOccurrenceStatus.userDisablePending,
                ),
              ),
              (
                name: 'past-scheduled-null',
                plan: buildPlan(),
                occurrence: buildOccurrence(
                  id: 'plan-1:20640:330',
                  time: TimeOfDayMinutes.fromHourMinute(hour: 5, minute: 30),
                  status: AlarmOccurrenceStatus.scheduled,
                  platformAlarmId: null,
                ),
              ),
              (
                name: 'finished-plan',
                plan: buildPlan(status: WakePlanStatus.finished),
                occurrence: buildOccurrence(
                  id: 'plan-1:20640:420',
                  status: AlarmOccurrenceStatus.userDisablePending,
                ),
              ),
              (
                name: 'ringing',
                plan: buildPlan(),
                occurrence: buildOccurrence(
                  id: 'plan-1:20640:420',
                  status: AlarmOccurrenceStatus.ringing,
                  firedAt: now,
                ),
              ),
              (
                name: 'dismissed',
                plan: buildPlan(),
                occurrence: buildOccurrence(
                  id: 'plan-1:20640:420',
                  status: AlarmOccurrenceStatus.dismissed,
                  firedAt: now,
                  dismissedAt: now,
                ),
              ),
            ];

        for (final scenario in scenarios) {
          final store = _LoggingWakePlanServiceStore(currentPlan: scenario.plan)
            ..wakePlans = [scenario.plan]
            ..storedOccurrences = [scenario.occurrence];
          final gateway = FakeNativeAlarmGateway();

          final reconciled = await service(
            store: store,
            gateway: gateway,
          ).reconcileSchedules();

          expect(reconciled, isEmpty, reason: scenario.name);
          expect(gateway.cancelledOccurrences, isEmpty, reason: scenario.name);
          expect(gateway.scheduledRequests, isEmpty, reason: scenario.name);
          expect(store.savedOccurrences, isEmpty, reason: scenario.name);
          expect(
            store.storedOccurrences.single.status,
            scenario.occurrence.status,
            reason: scenario.name,
          );
        }
      },
    );

    test(
      'isolates a mixed one-time recovery batch with canonical metadata',
      () async {
        final plan = buildPlan();
        final pendingOff = buildOccurrence(
          id: 'plan-1:20640:405',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
          status: AlarmOccurrenceStatus.userDisablePending,
          platformAlarmId: 'native-pending-off',
        );
        final desiredOn = buildOccurrence(
          id: 'plan-1:20640:415',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
          status: AlarmOccurrenceStatus.scheduled,
          platformAlarmId: null,
        );
        final unrelated = buildOccurrence(
          id: 'plan-1:unrelated',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
          status: AlarmOccurrenceStatus.scheduled,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [pendingOff, desiredOn, unrelated];
        final gateway = FakeNativeAlarmGateway()
          ..inventoryRows.addAll([
            NativeAlarmInventoryRow(
              reservationId: pendingOff.id,
              occurrenceId: pendingOff.id,
              wakePlanId: plan.id,
              platformAlarmId: pendingOff.platformAlarmId!,
              status: NativeAlarmReservationStatus.scheduled,
            ),
            NativeAlarmInventoryRow(
              reservationId: desiredOn.id,
              occurrenceId: desiredOn.id,
              wakePlanId: plan.id,
              platformAlarmId: 'platform-${desiredOn.id}',
              status: NativeAlarmReservationStatus.scheduled,
            ),
            NativeAlarmInventoryRow(
              reservationId: unrelated.id,
              occurrenceId: unrelated.id,
              wakePlanId: plan.id,
              platformAlarmId: 'stale-unrelated-a',
              status: NativeAlarmReservationStatus.scheduled,
            ),
            NativeAlarmInventoryRow(
              reservationId: unrelated.id,
              occurrenceId: unrelated.id,
              wakePlanId: plan.id,
              platformAlarmId: 'stale-unrelated-b',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          ]);

        final reconciled = await service(
          store: store,
          gateway: gateway,
        ).reconcileSchedules();

        expect(reconciled, hasLength(1));
        expect(
          gateway.cancelledOccurrences.map((request) => request.occurrenceId),
          [pendingOff.id],
        );
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          [desiredOn.id],
        );
        expect(gateway.scheduledRequests.single.reservationId, desiredOn.id);
        expect(gateway.scheduledRequests.single.indexInPlan, 2);
        expect(gateway.scheduledRequests.single.totalInPlan, 4);
        expect(
          gateway.scheduledRequests.single.targetAt,
          DateTime(2026, 7, 6, 7),
        );
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          isNot(contains('plan-1:20640:410')),
        );
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          isNot(contains('plan-1:20640:420')),
        );

        final storedById = {
          for (final occurrence in store.storedOccurrences)
            occurrence.id: occurrence,
        };
        expect(
          storedById[pendingOff.id]!.status,
          AlarmOccurrenceStatus.userDisabled,
        );
        expect(storedById[pendingOff.id]!.platformAlarmId, isNull);
        expect(
          storedById[desiredOn.id]!.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(
          storedById[desiredOn.id]!.platformAlarmId,
          'platform-${desiredOn.id}',
        );
        expect(storedById[unrelated.id]!.status, unrelated.status);
        expect(storedById[unrelated.id]!.platformAlarmId, isNull);

        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == pendingOff.id,
          ),
          isEmpty,
        );
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == desiredOn.id,
          ),
          hasLength(1),
        );
        expect(
          gateway.inventoryRows
              .where((row) => row.occurrenceId == unrelated.id)
              .map((row) => row.platformAlarmId),
          ['stale-unrelated-a', 'stale-unrelated-b'],
        );
      },
    );

    test(
      'serializes opposite intents and reconciliation across service instances',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          platformAlarmId: 'native-serialized',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = _BlockingCancelGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: 'native-serialized',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );
        final coordinator = WakePlanMutationCoordinator();
        final toggleService = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
          coordinator: coordinator,
        );
        final reconciliationService = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
          coordinator: coordinator,
        );

        final off = toggleService.setOccurrenceEnabled(
          wakePlanId: plan.id,
          occurrenceId: occurrence.id,
          enabled: false,
        );
        await gateway.cancelStarted.future;
        final on = reconciliationService.setOccurrenceEnabled(
          wakePlanId: plan.id,
          occurrenceId: occurrence.id,
          enabled: true,
        );
        final reconciliation = reconciliationService.reconcileSchedules();
        expect(gateway.scheduledRequests, isEmpty);

        gateway.releaseCancel.complete();
        expect((await off).status, AlarmOccurrenceToggleStatus.disabled);
        expect((await on).status, AlarmOccurrenceToggleStatus.enabled);
        await reconciliation;

        expect(
          store.storedOccurrences
              .singleWhere((item) => item.id == occurrence.id)
              .status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(
          gateway.scheduledRequests.where(
            (request) => request.occurrenceId == occurrence.id,
          ),
          hasLength(1),
        );
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          hasLength(1),
        );
      },
    );

    test('serializes plan edits behind occurrence toggles', () async {
      final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
      final editedPlan = buildPlan(
        targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
          hour: 7,
          minute: 30,
        ),
        repeatRule: RepeatRule.weekly({Weekday.monday}),
      );
      final occurrence = buildOccurrence(
        id: 'plan-1:20640:420',
        platformAlarmId: 'native-edit-serialization',
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..storedOccurrences = [occurrence]
        ..reservedOccurrences = [occurrence];
      final gateway = _BlockingCancelGateway()
        ..inventoryRows.add(
          NativeAlarmInventoryRow(
            reservationId: occurrence.id,
            occurrenceId: occurrence.id,
            wakePlanId: plan.id,
            platformAlarmId: occurrence.platformAlarmId!,
            status: NativeAlarmReservationStatus.scheduled,
          ),
        );
      final coordinator = WakePlanMutationCoordinator();
      final toggleService = service(
        store: store,
        gateway: gateway,
        coordinator: coordinator,
      );
      final editService = service(
        store: store,
        gateway: gateway,
        coordinator: coordinator,
      );

      final off = toggleService.setOccurrenceEnabled(
        wakePlanId: plan.id,
        occurrenceId: occurrence.id,
        enabled: false,
      );
      await gateway.cancelStarted.future;
      final edit = editService.editPlan(editedPlan);
      await Future<void>.delayed(Duration.zero);

      expect(store.savedPlans, isEmpty);

      gateway.releaseCancel.complete();
      await off;
      await edit;

      expect(store.savedPlans, isNotEmpty);
    });

    test(
      'does not reconcile an unknown persisted status into a new alarm',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          status: AlarmOccurrenceStatus.unknownPersisted,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = FakeNativeAlarmGateway();

        await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          isNot(contains(occurrence.id)),
        );
        expect(
          store.storedOccurrences
              .singleWhere((item) => item.id == occurrence.id)
              .status,
          AlarmOccurrenceStatus.unknownPersisted,
        );
      },
    );

    test(
      'reconciles desired on after uncertain compensation across inventory states',
      () async {
        for (final inventoryCase in [
          'success',
          'unavailable',
          'read-failure',
          'stale-present',
          'malformed',
        ]) {
          final plan = buildPlan(
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final occurrence = buildOccurrence(
            id: 'plan-1:20640:420',
            status: AlarmOccurrenceStatus.userDisabled,
            platformAlarmId: null,
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: plan)
            ..wakePlans = [plan]
            ..storedOccurrences = [occurrence]
            ..failSaveAlarmOccurrencesAtCalls.add(2);
          final gateway = _PostSideEffectThrowingGateway(
            throwAfterCancel: true,
            throwOnInventory: inventoryCase == 'malformed',
          );
          if (inventoryCase == 'unavailable') {
            gateway.capability = const NativeAlarmCapability(
              permissionStatus: NativeAlarmPermissionStatus.authorized,
              canScheduleAlarms: true,
              canRequestPermission: true,
              supportsInventory: false,
            );
          } else if (inventoryCase == 'read-failure') {
            gateway.inventoryFailureReason =
                NativeAlarmInventoryFailureReason.nativeError;
          }

          final result = await service(store: store, gateway: gateway)
              .setOccurrenceEnabled(
                wakePlanId: plan.id,
                occurrenceId: occurrence.id,
                enabled: true,
              );
          if (inventoryCase == 'stale-present') {
            gateway.inventoryRows.add(
              NativeAlarmInventoryRow(
                reservationId: occurrence.id,
                occurrenceId: occurrence.id,
                wakePlanId: plan.id,
                platformAlarmId: 'platform-${occurrence.id}',
                status: NativeAlarmReservationStatus.scheduled,
              ),
            );
          }

          expect(
            result.status,
            AlarmOccurrenceToggleStatus.recoveryRequired,
            reason: inventoryCase,
          );
          expect(result.warning, contains('will be reconciled'));
          expect(
            store.storedOccurrences.single.status,
            AlarmOccurrenceStatus.userEnablePending,
          );
          expect(store.storedOccurrences.single.platformAlarmId, isNotNull);

          final reconciliation = await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          ).reconcileSchedules();

          final reconciled = store.storedOccurrences.singleWhere(
            (item) => item.id == occurrence.id,
          );
          final inventoryIsAuthoritative =
              inventoryCase == 'success' || inventoryCase == 'stale-present';
          expect(
            reconciled.status,
            inventoryIsAuthoritative
                ? AlarmOccurrenceStatus.scheduled
                : AlarmOccurrenceStatus.userEnablePending,
            reason: inventoryCase,
          );
          expect(reconciled.platformAlarmId, isNotNull, reason: inventoryCase);
          expect(
            gateway.inventoryRows.where(
              (row) => row.occurrenceId == occurrence.id,
            ),
            inventoryIsAuthoritative ? hasLength(1) : isEmpty,
            reason: inventoryCase,
          );
          expect(
            reconciliation.single.status,
            inventoryIsAuthoritative
                ? WakePlanSchedulingStatus.scheduled
                : WakePlanSchedulingStatus.recoveryRequired,
            reason: inventoryCase,
          );
          expect(
            gateway.scheduledRequests.where(
              (request) => request.occurrenceId == occurrence.id,
            ),
            inventoryCase == 'success' ? hasLength(2) : hasLength(1),
            reason: inventoryCase,
          );
        }
      },
    );

    test(
      'pending off ignores non-authoritative inventory snapshots and retries cancel',
      () async {
        for (final inventoryCase in [
          'unavailable',
          'read-failure',
          'stale-present',
          'stale-absent',
          'malformed',
        ]) {
          final plan = buildPlan(
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final occurrence = buildOccurrence(
            id: 'plan-1:20640:420',
            platformAlarmId: 'native-$inventoryCase',
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: plan)
            ..wakePlans = [plan]
            ..storedOccurrences = [occurrence];
          final gateway =
              _PostSideEffectThrowingGateway(
                  throwAfterCancel: true,
                  throwOnInventory: inventoryCase == 'malformed',
                )
                ..inventoryRows.add(
                  NativeAlarmInventoryRow(
                    reservationId: occurrence.id,
                    occurrenceId: occurrence.id,
                    wakePlanId: plan.id,
                    platformAlarmId: occurrence.platformAlarmId!,
                    status: NativeAlarmReservationStatus.scheduled,
                  ),
                );
          if (inventoryCase == 'unavailable') {
            gateway.capability = const NativeAlarmCapability(
              permissionStatus: NativeAlarmPermissionStatus.authorized,
              canScheduleAlarms: true,
              canRequestPermission: true,
              supportsInventory: false,
            );
          } else if (inventoryCase == 'read-failure') {
            gateway.inventoryFailureReason =
                NativeAlarmInventoryFailureReason.nativeError;
          }

          final toggled = await service(store: store, gateway: gateway)
              .setOccurrenceEnabled(
                wakePlanId: plan.id,
                occurrenceId: occurrence.id,
                enabled: false,
              );
          if (inventoryCase == 'stale-present') {
            gateway.inventoryRows.add(
              NativeAlarmInventoryRow(
                reservationId: occurrence.id,
                occurrenceId: occurrence.id,
                wakePlanId: plan.id,
                platformAlarmId: occurrence.platformAlarmId!,
                status: NativeAlarmReservationStatus.scheduled,
              ),
            );
          }

          expect(
            toggled.occurrence!.status,
            AlarmOccurrenceStatus.userDisablePending,
            reason: inventoryCase,
          );
          await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          ).reconcileSchedules();

          final reconciled = store.storedOccurrences.singleWhere(
            (item) => item.id == occurrence.id,
          );
          expect(
            reconciled.status,
            AlarmOccurrenceStatus.userDisabled,
            reason: inventoryCase,
          );
          expect(
            gateway.scheduledRequests.where(
              (request) => request.occurrenceId == occurrence.id,
            ),
            isEmpty,
            reason: inventoryCase,
          );
        }
      },
    );

    test(
      'pending off without an id resolves only authoritative absence as off',
      () async {
        for (final inventoryCase in [
          'unavailable',
          'read-failure',
          'stale-absent',
          'malformed',
        ]) {
          final plan = buildPlan(
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final occurrence = buildOccurrence(
            id: 'plan-1:20640:420',
            status: AlarmOccurrenceStatus.userDisablePending,
            platformAlarmId: null,
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: plan)
            ..wakePlans = [plan]
            ..storedOccurrences = [occurrence];
          final gateway = _PostSideEffectThrowingGateway(
            throwOnInventory: inventoryCase == 'malformed',
          );
          if (inventoryCase == 'unavailable') {
            gateway.capability = const NativeAlarmCapability(
              permissionStatus: NativeAlarmPermissionStatus.authorized,
              canScheduleAlarms: true,
              canRequestPermission: true,
              supportsInventory: false,
            );
          } else if (inventoryCase == 'read-failure') {
            gateway.inventoryFailureReason =
                NativeAlarmInventoryFailureReason.nativeError;
          }

          final result = await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          ).reconcileSchedules();

          final inventoryIsAuthoritative = inventoryCase == 'stale-absent';
          expect(
            result.single.status,
            inventoryIsAuthoritative
                ? WakePlanSchedulingStatus.scheduled
                : WakePlanSchedulingStatus.recoveryRequired,
            reason: inventoryCase,
          );
          expect(
            store.storedOccurrences
                .singleWhere((item) => item.id == occurrence.id)
                .status,
            inventoryIsAuthoritative
                ? AlarmOccurrenceStatus.userDisabled
                : AlarmOccurrenceStatus.userDisablePending,
            reason: inventoryCase,
          );
          expect(
            gateway.scheduledRequests.where(
              (request) => request.occurrenceId == occurrence.id,
            ),
            isEmpty,
            reason: inventoryCase,
          );
        }
      },
    );

    test(
      'pending off without an id uses inventory only to retry cancel',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          status: AlarmOccurrenceStatus.userDisablePending,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = FakeNativeAlarmGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: 'native-discovered',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );

        await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(
          gateway.cancelledOccurrences.single.platformAlarmId,
          'native-discovered',
        );
        expect(
          store.storedOccurrences
              .singleWhere((item) => item.id == occurrence.id)
              .status,
          AlarmOccurrenceStatus.userDisabled,
        );
        expect(
          gateway.scheduledRequests.where(
            (request) => request.occurrenceId == occurrence.id,
          ),
          isEmpty,
        );
      },
    );

    test(
      'pending off trusts authoritative absence over a stale stored id',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          status: AlarmOccurrenceStatus.userDisablePending,
          platformAlarmId: 'stale-native-id',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = _StrictMissingMirrorGateway();

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(result.single.status, WakePlanSchedulingStatus.scheduled);
        expect(gateway.cancelledOccurrences, isEmpty);
        expect(
          store.storedOccurrences.singleWhere(
            (item) => item.id == occurrence.id,
          ),
          isA<AlarmOccurrence>()
              .having(
                (item) => item.status,
                'status',
                AlarmOccurrenceStatus.userDisabled,
              )
              .having(
                (item) => item.platformAlarmId,
                'platformAlarmId',
                isNull,
              ),
        );
        expect(
          gateway.scheduledRequests.where(
            (request) => request.occurrenceId == occurrence.id,
          ),
          isEmpty,
        );
      },
    );

    test(
      'pending off uses the exact active tuple over a stale stored id',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          status: AlarmOccurrenceStatus.userDisablePending,
          platformAlarmId: 'stale-native-id',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = _StrictMissingMirrorGateway()
          ..inventoryRows.add(
            inventoryRow(
              occurrence,
              platformAlarmId: 'authoritative-native-id',
            ),
          );

        await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(gateway.cancelledOccurrences.map((item) => item.idLabel), [
          '${occurrence.id}/authoritative-native-id',
        ]);
        final persisted = store.storedOccurrences.singleWhere(
          (item) => item.id == occurrence.id,
        );
        expect(persisted.status, AlarmOccurrenceStatus.userDisabled);
        expect(persisted.platformAlarmId, isNull);
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          isEmpty,
        );
      },
    );

    test(
      'stale discovered id is not made durable after cancel failure',
      () async {
        final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
        final occurrence = buildOccurrence(
          id: 'plan-1:20640:420',
          status: AlarmOccurrenceStatus.userDisablePending,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..wakePlans = [plan]
          ..storedOccurrences = [occurrence];
        final gateway = FakeNativeAlarmGateway()
          ..inventoryRows.addAll([
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: 'stale-id',
              status: NativeAlarmReservationStatus.scheduled,
            ),
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: 'actual-id',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          ]);

        final first = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(first.single.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(
          store.storedOccurrences
              .singleWhere((item) => item.id == occurrence.id)
              .platformAlarmId,
          isNull,
        );

        gateway.inventoryRows
          ..clear()
          ..add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: 'fresh-id',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );
        await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(
          store.storedOccurrences
              .singleWhere((item) => item.id == occurrence.id)
              .status,
          AlarmOccurrenceStatus.userDisabled,
        );
      },
    );

    test('rejects past, ringing, and dismissed occurrence mutations', () async {
      final plan = buildPlan();
      final past = buildOccurrence(
        id: 'past',
        time: TimeOfDayMinutes.fromHourMinute(hour: 5, minute: 30),
      );
      final pastDisabled = buildOccurrence(
        id: 'past-disabled',
        time: TimeOfDayMinutes.fromHourMinute(hour: 5, minute: 30),
        status: AlarmOccurrenceStatus.userDisabled,
        platformAlarmId: null,
      );
      final ringing = buildOccurrence(
        id: 'ringing',
        status: AlarmOccurrenceStatus.ringing,
        firedAt: now,
      );
      final dismissed = buildOccurrence(
        id: 'dismissed',
        status: AlarmOccurrenceStatus.dismissed,
        firedAt: now,
        dismissedAt: now,
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..storedOccurrences = [past, pastDisabled, ringing, dismissed];
      final gateway = FakeNativeAlarmGateway();
      final wakePlanService = service(store: store, gateway: gateway);

      for (final occurrence in store.storedOccurrences) {
        final result = await wakePlanService.setOccurrenceEnabled(
          wakePlanId: plan.id,
          occurrenceId: occurrence.id,
          enabled: false,
        );
        expect(result.status, AlarmOccurrenceToggleStatus.invalidState);
      }
      expect(gateway.cancelledOccurrences, isEmpty);
      expect(gateway.scheduledRequests, isEmpty);
    });
  });

  group('WakePlanService editPlan', () {
    test(
      'hides and rejects stale disabled identities after timing edits',
      () async {
        for (final scenario in [
          (
            name: 'target time',
            oldTime: targetTime,
            edit: buildPlan(
              targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
                hour: 7,
                minute: 30,
              ),
            ),
          ),
          (
            name: 'start offset',
            oldTime: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
            edit: buildPlan(startOffset: const Duration(minutes: 10)),
          ),
          (
            name: 'interval',
            oldTime: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
            edit: buildPlan(interval: const Duration(minutes: 7)),
          ),
        ]) {
          final originalPlan = buildPlan();
          final staleId =
              'plan-1:20640:${scenario.oldTime.minutesSinceMidnight}';
          final staleDisabled = buildOccurrence(
            id: staleId,
            time: scenario.oldTime,
            status: AlarmOccurrenceStatus.userDisabled,
            platformAlarmId: null,
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
            ..storedOccurrences = [staleDisabled];
          final gateway = FakeNativeAlarmGateway();
          final serviceUnderTest = service(store: store, gateway: gateway);

          final edited = await serviceUnderTest.editPlan(scenario.edit);
          expect(
            edited.status,
            WakePlanSchedulingStatus.scheduled,
            reason: scenario.name,
          );
          final visible = await serviceUnderTest.fetchOccurrencesForPlan(
            originalPlan.id,
          );
          expect(
            visible,
            isNotEmpty,
            reason: 'new canonical occurrences:${scenario.name}',
          );
          expect(
            visible.map((occurrence) => occurrence.id),
            isNot(contains(staleId)),
            reason: scenario.name,
          );

          final scheduledCount = gateway.scheduledRequests.length;
          final rejected = await serviceUnderTest.setOccurrenceEnabled(
            wakePlanId: originalPlan.id,
            occurrenceId: staleId,
            enabled: true,
          );
          expect(
            rejected.status,
            AlarmOccurrenceToggleStatus.invalidState,
            reason: scenario.name,
          );
          expect(gateway.scheduledRequests, hasLength(scheduledCount));
          expect(
            store.storedOccurrences
                .singleWhere((occurrence) => occurrence.id == staleId)
                .status,
            AlarmOccurrenceStatus.userDisabled,
            reason: 'durable suppression:${scenario.name}',
          );
          expect(
            gateway.inventoryRows.where((row) => row.occurrenceId == staleId),
            isEmpty,
            reason: scenario.name,
          );
        }
      },
    );

    for (final scenario
        in <
          ({
            String name,
            Object error,
            bool applyNativeSideEffect,
            bool failRestorationPersistence,
          })
        >[
          (
            name: 'throws before its side effect',
            error: StateError('injected pre-schedule response exception'),
            applyNativeSideEffect: false,
            failRestorationPersistence: false,
          ),
          (
            name: 'throws after its side effect',
            error: StateError('injected post-schedule response exception'),
            applyNativeSideEffect: true,
            failRestorationPersistence: false,
          ),
          (
            name:
                'returns a malformed response after its side effect and persistence fails',
            error: const FormatException(
              'injected malformed schedule response',
            ),
            applyNativeSideEffect: true,
            failRestorationPersistence: true,
          ),
        ]) {
      test(
        'restores the prior plan when partial-cancel compensation ${scenario.name}',
        () async {
          final originalPlan = buildPlan(
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final editedPlan = buildPlan(
            targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
              hour: 7,
              minute: 30,
            ),
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final first = buildOccurrence(
            id: 'plan-1:20640:415',
            time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
            platformAlarmId: 'native-old-1',
          );
          final second = buildOccurrence(
            id: 'plan-1:20640:420',
            platformAlarmId: 'native-old-2',
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
            ..wakePlans = [originalPlan]
            ..reservedOccurrences = [first, second]
            ..storedOccurrences = [first, second];
          if (scenario.failRestorationPersistence) {
            store.failSaveAlarmOccurrencesAtCalls.add(2);
          }
          final gateway =
              _OneShotRestorationExceptionGateway(
                  error: scenario.error,
                  applyNativeSideEffect: scenario.applyNativeSideEffect,
                )
                ..cancelFailurePlatformAlarmIds.add(second.platformAlarmId!)
                ..inventoryRows.addAll([
                  NativeAlarmInventoryRow(
                    reservationId: first.id,
                    occurrenceId: first.id,
                    wakePlanId: originalPlan.id,
                    platformAlarmId: first.platformAlarmId!,
                    status: NativeAlarmReservationStatus.scheduled,
                  ),
                  NativeAlarmInventoryRow(
                    reservationId: second.id,
                    occurrenceId: second.id,
                    wakePlanId: originalPlan.id,
                    platformAlarmId: second.platformAlarmId!,
                    status: NativeAlarmReservationStatus.scheduled,
                  ),
                ]);

          final result = await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          ).editPlan(editedPlan);

          expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
          expect(result.changeState, WakePlanChangeState.recoveryRequired);
          expect(result.compensationScheduleResult!.isSuccess, isFalse);
          expect(
            result.databaseState,
            scenario.failRestorationPersistence
                ? WakePlanDatabaseState.unknown
                : WakePlanDatabaseState.persisted,
          );
          expect(
            result.persistenceError,
            scenario.failRestorationPersistence ? isNotNull : isNull,
          );
          expect(store.currentPlan!.targetTime, originalPlan.targetTime);
          final compensationSave = store.operations.indexOf(
            'saveAlarmOccurrences:1',
          );
          final previousPlanSave = store.operations.lastIndexOf(
            'saveWakePlan:plan-1',
          );
          expect(compensationSave, greaterThanOrEqualTo(0));
          expect(previousPlanSave, greaterThan(compensationSave));

          final reconciliation = await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          ).reconcileSchedules();

          expect(
            reconciliation.single.status,
            WakePlanSchedulingStatus.scheduled,
          );
          expect(store.currentPlan!.targetTime, originalPlan.targetTime);
          expect(gateway.inventoryRows.map((row) => row.occurrenceId).toSet(), {
            'plan-1:20640:405',
            'plan-1:20640:410',
            'plan-1:20640:415',
            'plan-1:20640:420',
          });
          expect(gateway.inventoryRows, hasLength(4));
          expect(
            gateway.scheduledRequests.where(
              (request) => request.occurrenceId == first.id,
            ),
            hasLength(1),
          );
        },
      );
    }

    test(
      'persists merged suppression and desired-on recovery after partial cancellation',
      () async {
        final originalPlan = buildPlan();
        final editedPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 7,
            minute: 30,
          ),
        );
        final unknown = buildOccurrence(
          id: 'plan-1:20640:405',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
          status: AlarmOccurrenceStatus.unknownPersisted,
          platformAlarmId: 'native-unknown',
        );
        final desiredOn = buildOccurrence(
          id: 'plan-1:20640:410',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
          platformAlarmId: 'native-desired',
        );
        final uncancelled = buildOccurrence(
          id: 'plan-1:20640:415',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
          platformAlarmId: 'native-uncancelled',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..wakePlans = [originalPlan]
          ..reservedOccurrences = [unknown, desiredOn, uncancelled]
          ..storedOccurrences = [unknown, desiredOn, uncancelled];
        final gateway =
            _OneShotRestorationExceptionGateway(
                error: StateError('injected restoration response exception'),
                applyNativeSideEffect: false,
              )
              ..cancelFailurePlatformAlarmIds.add('native-uncancelled')
              ..inventoryRows.addAll([
                for (final occurrence in [unknown, desiredOn, uncancelled])
                  NativeAlarmInventoryRow(
                    reservationId: occurrence.id,
                    occurrenceId: occurrence.id,
                    wakePlanId: occurrence.wakePlanId,
                    platformAlarmId: occurrence.platformAlarmId!,
                    status: NativeAlarmReservationStatus.scheduled,
                  ),
              ]);

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.databaseState, WakePlanDatabaseState.persisted);
        expect(store.currentPlan!.targetTime, originalPlan.targetTime);
        expect(store.savedOccurrences.last, hasLength(2));
        expect(store.savedOccurrences.last.map((item) => item.status).toSet(), {
          AlarmOccurrenceStatus.unknownPersisted,
          AlarmOccurrenceStatus.scheduled,
        });
        expect(
          store.storedOccurrences
              .singleWhere((item) => item.id == desiredOn.id)
              .platformAlarmId,
          isNull,
        );

        final recovery = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        ).reconcileSchedules();

        expect(recovery.single.status, WakePlanSchedulingStatus.scheduled);
        expect(gateway.inventoryRows.map((row) => row.occurrenceId).toSet(), {
          desiredOn.id,
          uncancelled.id,
        });
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == desiredOn.id,
          ),
          hasLength(1),
        );
        expect(
          store.storedOccurrences.singleWhere((item) => item.id == unknown.id),
          isA<AlarmOccurrence>().having(
            (item) => item.status,
            'status',
            AlarmOccurrenceStatus.unknownPersisted,
          ),
        );
      },
    );

    test('reports merged restoration persistence failure truthfully', () async {
      final originalPlan = buildPlan();
      final unknown = buildOccurrence(
        id: 'plan-1:20640:405',
        time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
        status: AlarmOccurrenceStatus.unknownPersisted,
        platformAlarmId: 'native-unknown',
      );
      final desiredOn = buildOccurrence(
        id: 'plan-1:20640:410',
        time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
        platformAlarmId: 'native-desired',
      );
      final uncancelled = buildOccurrence(
        id: 'plan-1:20640:415',
        time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
        platformAlarmId: 'native-uncancelled',
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
        ..failSaveAlarmOccurrencesAtCalls.add(2)
        ..reservedOccurrences = [unknown, desiredOn, uncancelled]
        ..storedOccurrences = [unknown, desiredOn, uncancelled];
      final gateway = withUnavailableInventory(
        _OneShotRestorationExceptionGateway(
          error: StateError('injected restoration response exception'),
          applyNativeSideEffect: false,
        )..cancelFailurePlatformAlarmIds.add('native-uncancelled'),
      );

      final result =
          await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          ).editPlan(
            originalPlan.copyWith(
              targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 30),
            ),
          );

      expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
      expect(result.databaseState, WakePlanDatabaseState.unknown);
      expect(result.persistenceError, isNotNull);
      expect(result.occurrences, hasLength(3));
      expect(store.currentPlan!.targetTime, originalPlan.targetTime);
    });

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
        final gateway = withUnavailableInventory(FakeNativeAlarmGateway());
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
          'fetchOccurrencesForPlan:plan-1',
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
      'edit cancels the authoritative inventory id instead of a stale stored id',
      () async {
        final originalPlan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'old-future-1',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 30),
          platformAlarmId: 'stale-native-id',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..reservedOccurrences = [occurrence]
          ..storedOccurrences = [occurrence];
        final gateway = FakeNativeAlarmGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: occurrence.wakePlanId,
              platformAlarmId: 'authoritative-native-id',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          );

        final result = await service(store: store, gateway: gateway).editPlan(
          buildPlan(
            targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
              hour: 7,
              minute: 30,
            ),
          ),
        );

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(gateway.cancelledOccurrences.map((request) => request.idLabel), [
          'old-future-1/authoritative-native-id',
        ]);
        expect(
          gateway.inventoryRows.where(
            (row) => row.reservationId == occurrence.id,
          ),
          isEmpty,
        );
      },
    );

    test(
      'restart reconciles a failed authoritative-id cancel without duplicates',
      () async {
        final originalPlan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'old-future-1',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 30),
          platformAlarmId: 'stale-native-id',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..wakePlans = [originalPlan]
          ..reservedOccurrences = [occurrence]
          ..storedOccurrences = [occurrence];
        final gateway = FakeNativeAlarmGateway()
          ..inventoryRows.add(
            NativeAlarmInventoryRow(
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: occurrence.wakePlanId,
              platformAlarmId: 'authoritative-native-id',
              status: NativeAlarmReservationStatus.scheduled,
            ),
          )
          ..cancelFailurePlatformAlarmIds.add('authoritative-native-id');

        final editResult = await service(store: store, gateway: gateway)
            .editPlan(
              buildPlan(
                targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
                  hour: 7,
                  minute: 30,
                ),
              ),
            );

        expect(editResult.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(gateway.cancelledOccurrences.map((request) => request.idLabel), [
          'old-future-1/authoritative-native-id',
        ]);
        expect(
          store.storedOccurrences.singleWhere(
            (item) => item.id == occurrence.id,
          ),
          isA<AlarmOccurrence>()
              .having(
                (item) => item.status,
                'status',
                AlarmOccurrenceStatus.userEnablePending,
              )
              .having(
                (item) => item.platformAlarmId,
                'platformAlarmId',
                isNull,
              ),
        );

        gateway.cancelFailurePlatformAlarmIds.clear();
        gateway.scheduledRequests.clear();
        final restartedResult = await service(
          store: store,
          gateway: gateway,
        ).reconcileSchedules();

        expect(
          restartedResult.single.status,
          WakePlanSchedulingStatus.scheduled,
        );
        expect(gateway.scheduledRequests, hasLength(4));
        expect(
          gateway.inventoryRows.where(
            (row) => row.reservationId == occurrence.id,
          ),
          isEmpty,
        );
        expect(gateway.inventoryRows, hasLength(4));
        expect(
          store.storedOccurrences.singleWhere(
            (item) => item.id == occurrence.id,
          ),
          isA<AlarmOccurrence>()
              .having(
                (item) => item.status,
                'status',
                AlarmOccurrenceStatus.cancelled,
              )
              .having(
                (item) => item.platformAlarmId,
                'platformAlarmId',
                isNull,
              ),
        );
        final sideEffectCount =
            gateway.cancelledOccurrences.length +
            gateway.scheduledRequests.length;
        await service(store: store, gateway: gateway).reconcileSchedules();
        expect(
          gateway.cancelledOccurrences.length +
              gateway.scheduledRequests.length,
          sideEffectCount,
        );
      },
    );

    test(
      'preserves canonical metadata when editing around a disabled occurrence',
      () async {
        final originalPlan = buildPlan();
        final occurrences = [
          buildOccurrence(
            id: 'plan-1:20640:405',
            time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
            platformAlarmId: 'native-405',
          ),
          buildOccurrence(
            id: 'plan-1:20640:410',
            time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
            platformAlarmId: null,
            status: AlarmOccurrenceStatus.userDisabled,
          ),
          buildOccurrence(
            id: 'plan-1:20640:415',
            time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
            platformAlarmId: 'native-415',
          ),
          buildOccurrence(
            id: 'plan-1:20640:420',
            platformAlarmId: 'native-420',
          ),
        ];
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..reservedOccurrences = [
            occurrences[0],
            occurrences[2],
            occurrences[3],
          ]
          ..storedOccurrences = occurrences;
        final gateway = FakeNativeAlarmGateway();

        final result = await service(
          store: store,
          gateway: gateway,
        ).editPlan(originalPlan.copyWith(soundId: 'edited-sound'));

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          ['plan-1:20640:405', 'plan-1:20640:415', 'plan-1:20640:420'],
        );
        expect(
          gateway.scheduledRequests.map((request) => request.reservationId),
          ['plan-1:20640:405', 'plan-1:20640:415', 'plan-1:20640:420'],
        );
        expect(
          gateway.scheduledRequests.map(
            (request) => request.reservationGeneration,
          ),
          everyElement(1),
        );
        expect(
          gateway.scheduledRequests.map((request) => request.indexInPlan),
          [0, 2, 3],
        );
        expect(
          gateway.scheduledRequests.map((request) => request.totalInPlan),
          everyElement(4),
        );
        expect(
          gateway.scheduledRequests.map((request) => request.targetAt),
          everyElement(DateTime(2026, 7, 6, 7)),
        );
        expect(
          store.storedOccurrences
              .singleWhere((occurrence) => occurrence.id == 'plan-1:20640:410')
              .status,
          AlarmOccurrenceStatus.userDisabled,
        );
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
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = withUnavailableInventory(
          FakeNativeAlarmGateway()
            ..cancelFailurePlatformAlarmIds.add('old-native-1'),
        );

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
      'preserves a known reservation when the cancellation response is uncertain',
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
        final occurrence = buildOccurrence(
          id: 'old-future-uncertain',
          time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
          platformAlarmId: 'old-native-uncertain',
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..reservedOccurrences = [occurrence]
          ..storedOccurrences = [occurrence];
        final gateway = withUnavailableInventory(
          _PostSideEffectThrowingGateway(throwAfterCancel: true),
        );

        final result = await service(
          store: store,
          gateway: gateway,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.changeState, WakePlanChangeState.recoveryRequired);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.recoveryRequired,
        );
        expect(result.databaseState, WakePlanDatabaseState.persisted);
        expect(result.persistenceError, isNull);
        expect(gateway.scheduledRequests, isEmpty);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.userEnablePending,
        );
        expect(
          store.storedOccurrences.single.platformAlarmId,
          occurrence.platformAlarmId,
        );
      },
    );

    test(
      'keeps desired-on recovery through uncertain edit and delete cancellation',
      () async {
        for (final scenario in [
          (
            name: 'weekly edit before side effect',
            plan: buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday})),
            edit: true,
            applySideEffect: false,
          ),
          (
            name: 'weekly delete after side effect',
            plan: buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday})),
            edit: false,
            applySideEffect: true,
          ),
          (
            name: 'one-time edit after side effect',
            plan: buildPlan(),
            edit: true,
            applySideEffect: true,
          ),
          (
            name: 'one-time delete before side effect',
            plan: buildPlan(),
            edit: false,
            applySideEffect: false,
          ),
        ]) {
          final occurrence = buildOccurrence(
            id: 'plan-1:20640:420',
            platformAlarmId: 'native-old',
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: scenario.plan)
            ..wakePlans = [scenario.plan]
            ..reservedOccurrences = [occurrence]
            ..storedOccurrences = [occurrence];
          final gateway =
              _UncertainPlanMutationCancelGateway(
                  applySideEffect: scenario.applySideEffect,
                )
                ..inventoryRows.add(
                  NativeAlarmInventoryRow(
                    reservationId: occurrence.id,
                    occurrenceId: occurrence.id,
                    wakePlanId: occurrence.wakePlanId,
                    platformAlarmId: occurrence.platformAlarmId!,
                    status: NativeAlarmReservationStatus.scheduled,
                  ),
                );

          final mutation = scenario.edit
              ? await service(
                  store: store,
                  gateway: gateway,
                  rollingScheduleDays: 1,
                ).editPlan(scenario.plan.copyWith(vibrationEnabled: false))
              : await service(
                  store: store,
                  gateway: gateway,
                  rollingScheduleDays: 1,
                ).deletePlan(scenario.plan.id);

          expect(
            mutation.status,
            WakePlanSchedulingStatus.recoveryRequired,
            reason: scenario.name,
          );
          expect(
            mutation.changeState,
            WakePlanChangeState.recoveryRequired,
            reason: scenario.name,
          );
          expect(
            mutation.warning!.kind,
            WakePlanSchedulingWarningKind.recoveryRequired,
            reason: scenario.name,
          );
          expect(
            mutation.databaseState,
            WakePlanDatabaseState.persisted,
            reason: scenario.name,
          );
          expect(mutation.persistenceError, isNull, reason: scenario.name);
          expect(store.deletedPlanIds, isEmpty, reason: scenario.name);
          expect(
            store.storedOccurrences
                .singleWhere((item) => item.id == occurrence.id)
                .status,
            AlarmOccurrenceStatus.userEnablePending,
            reason: scenario.name,
          );

          final recovery = await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          ).reconcileSchedules();

          expect(
            recovery.single.status,
            WakePlanSchedulingStatus.scheduled,
            reason: scenario.name,
          );
          final recovered = store.storedOccurrences.singleWhere(
            (item) => item.id == occurrence.id,
          );
          expect(
            recovered.status,
            AlarmOccurrenceStatus.scheduled,
            reason: scenario.name,
          );
          expect(recovered.platformAlarmId, isNotNull, reason: scenario.name);
          expect(
            gateway.inventoryRows.where(
              (row) => row.occurrenceId == occurrence.id,
            ),
            hasLength(1),
            reason: scenario.name,
          );
        }
      },
    );

    test(
      'keeps duplicate native reservations unresolved across recovery and mutations',
      () async {
        for (final pendingStatus in [
          AlarmOccurrenceStatus.userDisablePending,
          AlarmOccurrenceStatus.userEnablePending,
        ]) {
          final plan = buildPlan();
          final occurrence = buildOccurrence(
            id: 'plan-1:20640:420',
            status: pendingStatus,
            platformAlarmId: 'native-a',
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: plan)
            ..wakePlans = [plan]
            ..storedOccurrences = [occurrence];
          final gateway = FakeNativeAlarmGateway()
            ..inventoryRows.addAll([
              inventoryRow(occurrence, platformAlarmId: 'native-a'),
              inventoryRow(occurrence, platformAlarmId: 'native-b'),
            ]);

          final result = await service(
            store: store,
            gateway: gateway,
            rollingScheduleDays: 1,
          ).reconcileSchedules();

          expect(
            result.single.status,
            WakePlanSchedulingStatus.recoveryRequired,
            reason: pendingStatus.name,
          );
          expect(
            store.storedOccurrences
                .singleWhere((item) => item.id == occurrence.id)
                .status,
            pendingStatus,
            reason: pendingStatus.name,
          );
          expect(
            gateway.cancelledOccurrences,
            isEmpty,
            reason: pendingStatus.name,
          );
          expect(
            gateway.scheduledRequests,
            isEmpty,
            reason: pendingStatus.name,
          );
          expect(
            gateway.inventoryRows,
            hasLength(2),
            reason: pendingStatus.name,
          );
        }

        for (final operation in ['edit', 'delete']) {
          final plan = buildPlan(
            repeatRule: RepeatRule.weekly({Weekday.monday}),
          );
          final occurrence = buildOccurrence(
            id: 'plan-1:20640:420',
            platformAlarmId: 'native-a',
          );
          final store = _LoggingWakePlanServiceStore(currentPlan: plan)
            ..reservedOccurrences = [occurrence]
            ..storedOccurrences = [occurrence];
          final gateway = FakeNativeAlarmGateway()
            ..inventoryRows.addAll([
              inventoryRow(occurrence, platformAlarmId: 'native-a'),
              inventoryRow(occurrence, platformAlarmId: 'native-b'),
            ]);

          final result = operation == 'edit'
              ? await service(
                  store: store,
                  gateway: gateway,
                  rollingScheduleDays: 1,
                ).editPlan(plan.copyWith(soundId: 'edited'))
              : await service(
                  store: store,
                  gateway: gateway,
                  rollingScheduleDays: 1,
                ).deletePlan(plan.id);

          expect(
            result.status,
            WakePlanSchedulingStatus.recoveryRequired,
            reason: operation,
          );
          expect(
            result.changeState,
            WakePlanChangeState.recoveryRequired,
            reason: operation,
          );
          expect(
            result.databaseState,
            WakePlanDatabaseState.persisted,
            reason: operation,
          );
          expect(result.persistenceError, isNull, reason: operation);
          expect(store.deletedPlanIds, isEmpty, reason: operation);
          expect(gateway.cancelledOccurrences, isEmpty, reason: operation);
          expect(gateway.cancelledPlans, isEmpty, reason: operation);
          expect(gateway.scheduledRequests, isEmpty, reason: operation);
          expect(gateway.inventoryRows, hasLength(2), reason: operation);
          expect(
            store.storedOccurrences.single.status,
            AlarmOccurrenceStatus.scheduled,
            reason: operation,
          );
        }
      },
    );

    test(
      'conservatively resolves id-less desired-on state during edit and delete',
      () async {
        for (final operation in ['edit', 'delete']) {
          for (final inventoryState in ['active', 'absent', 'unavailable']) {
            final plan = buildPlan(
              repeatRule: RepeatRule.weekly({Weekday.monday}),
            );
            final pending = buildOccurrence(
              id: 'plan-1:20640:420',
              status: AlarmOccurrenceStatus.userEnablePending,
              platformAlarmId: null,
            );
            final store = _LoggingWakePlanServiceStore(currentPlan: plan)
              ..reservedOccurrences = [pending]
              ..storedOccurrences = [pending];
            final gateway = FakeNativeAlarmGateway();
            if (inventoryState == 'active') {
              gateway.inventoryRows.add(
                NativeAlarmInventoryRow(
                  reservationId: pending.id,
                  occurrenceId: pending.id,
                  wakePlanId: pending.wakePlanId,
                  platformAlarmId: 'discovered-native',
                  status: NativeAlarmReservationStatus.scheduled,
                ),
              );
            } else if (inventoryState == 'unavailable') {
              gateway.inventoryFailureReason =
                  NativeAlarmInventoryFailureReason.nativeError;
            }

            final result = operation == 'edit'
                ? await service(
                    store: store,
                    gateway: gateway,
                    rollingScheduleDays: 1,
                  ).editPlan(plan.copyWith(soundId: 'edited'))
                : await service(
                    store: store,
                    gateway: gateway,
                    rollingScheduleDays: 1,
                  ).deletePlan(plan.id);
            final reason = '$operation/$inventoryState';

            if (inventoryState == 'unavailable') {
              expect(
                result.status,
                WakePlanSchedulingStatus.recoveryRequired,
                reason: reason,
              );
              expect(store.deletedPlanIds, isEmpty, reason: reason);
              expect(gateway.scheduledRequests, isEmpty, reason: reason);
              expect(
                store.storedOccurrences.single.status,
                AlarmOccurrenceStatus.userEnablePending,
                reason: reason,
              );
              continue;
            }

            expect(
              result.status,
              operation == 'edit'
                  ? WakePlanSchedulingStatus.scheduled
                  : WakePlanSchedulingStatus.deleted,
              reason: reason,
            );
            if (inventoryState == 'active') {
              final cancellations = operation == 'edit'
                  ? gateway.cancelledOccurrences
                  : gateway.cancelledPlans;
              expect(
                cancellations.single.platformAlarmId,
                'discovered-native',
                reason: reason,
              );
            }
            if (operation == 'edit') {
              expect(
                gateway.scheduledRequests.map(
                  (request) => request.occurrenceId,
                ),
                contains(pending.id),
                reason: reason,
              );
            } else {
              expect(store.deletedPlanIds, [plan.id], reason: reason);
            }
          }
        }
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
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
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

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.changeState, WakePlanChangeState.recoveryRequired);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.recoveryRequired,
        );
        expect(result.warning!.scheduleStatus, isNull);
        expect(gateway.cancelledOccurrences.map((request) => request.idLabel), [
          'old-future-1/old-native-1',
        ]);
        expect(gateway.scheduledRequests, hasLength(5));
        expect(store.operations, [
          'fetchWakePlan:plan-1',
          'saveWakePlan:plan-1',
          'fetchReservedOccurrencesForPlan:plan-1',
          'saveAlarmOccurrences:1',
          'fetchOccurrencesForPlan:plan-1',
          'saveAlarmOccurrences:4',
          'saveAlarmOccurrences:4',
          'saveAlarmOccurrences:1',
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

    test(
      'cancels partially scheduled replacements before restoring previous plan',
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
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = withUnavailableInventory(
          FakeNativeAlarmGateway()
            ..scheduleFailureOccurrenceIds.add('plan-1:20640:440'),
        );

        final result = await service(
          store: store,
          gateway: gateway,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.scheduleFailed);
        expect(result.changeState, WakePlanChangeState.failed);
        expect(gateway.scheduledRequests, hasLength(5));
        expect(gateway.cancelledOccurrences.map((request) => request.idLabel), [
          'old-future-1/old-native-1',
          'plan-1:20640:435/platform-plan-1:20640:435',
          'plan-1:20640:445/platform-plan-1:20640:445',
          'plan-1:20640:450/platform-plan-1:20640:450',
        ]);
        expect(store.operations, [
          'fetchWakePlan:plan-1',
          'saveWakePlan:plan-1',
          'fetchReservedOccurrencesForPlan:plan-1',
          'saveAlarmOccurrences:1',
          'fetchOccurrencesForPlan:plan-1',
          'saveAlarmOccurrences:4',
          'saveAlarmOccurrences:4',
          'saveAlarmOccurrences:3',
          'saveAlarmOccurrences:1',
          'saveWakePlan:plan-1',
        ]);
        expect(store.savedPlans[0].targetTime, editedPlan.targetTime);
        expect(store.savedPlans[1].targetTime, originalPlan.targetTime);
        expect(store.currentPlan!.targetTime, originalPlan.targetTime);
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'plan-1:20640:440')
              .single
              .status,
          AlarmOccurrenceStatus.failed,
        );
      },
    );

    test(
      'restores the old native reservation after replacement scheduling fails',
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
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          scheduleFailuresByCall: [
            {'plan-1:20640:440'},
          ],
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
        expect(result.compensationScheduleResult!.isSuccess, isTrue);
        expect(store.currentPlan!.targetTime, originalPlan.targetTime);
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
      },
    );

    test(
      'restores cross-midnight reservations with the owning next-day target',
      () async {
        final originalPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 0,
            minute: 0,
          ),
          startOffset: const Duration(hours: 1),
          repeatRule: RepeatRule.weekly({Weekday.tuesday}),
        );
        final editedPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 0,
            minute: 30,
          ),
          startOffset: const Duration(hours: 1),
          repeatRule: RepeatRule.weekly({Weekday.tuesday}),
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'plan-1:20640:1380',
              day: monday,
              time: TimeOfDayMinutes.fromHourMinute(hour: 23, minute: 0),
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          scheduleFailuresByCall: [
            {'plan-1:20640:1410'},
          ],
        );

        final result = await service(
          store: store,
          gateway: gateway,
          clockNow: DateTime(2026, 7, 6, 22),
          rollingScheduleDays: 2,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.scheduleFailed);
        expect(result.compensationScheduleResult!.isSuccess, isTrue);
        expect(
          gateway.scheduledRequests.last.scheduledAt,
          DateTime(2026, 7, 6, 23),
        );
        expect(gateway.scheduledRequests.last.targetAt, DateTime(2026, 7, 7));
      },
    );

    test(
      'returns recoveryRequired when a full old cancel save fails',
      () async {
        final originalPlan = buildPlan();
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..failSaveAlarmOccurrencesAtCalls.add(1)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ]
          ..storedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ];

        final result =
            await service(
              store: store,
              gateway: FakeNativeAlarmGateway(),
            ).editPlan(
              buildPlan(
                targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
                  hour: 7,
                  minute: 30,
                ),
              ),
            );

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.changeState, WakePlanChangeState.recoveryRequired);
        expect(result.databaseState, WakePlanDatabaseState.persisted);
        expect(result.persistenceError, isNotNull);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.recoveryRequired,
        );
        expect(store.currentPlan!.targetTime, originalPlan.targetTime);
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
      },
    );

    test(
      'returns recoveryRequired when a partial old cancel save fails',
      () async {
        final originalPlan = buildPlan();
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..failSaveAlarmOccurrencesAtCalls.add(1)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
            buildOccurrence(
              id: 'old-future-2',
              platformAlarmId: 'old-native-2',
            ),
          ]
          ..storedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
            buildOccurrence(
              id: 'old-future-2',
              platformAlarmId: 'old-native-2',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          cancelFailuresByCall: [
            {'old-native-2'},
          ],
        );

        final result = await service(store: store, gateway: gateway).editPlan(
          buildPlan(
            targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
              hour: 7,
              minute: 30,
            ),
          ),
        );

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.persistenceError, isNotNull);
        expect(gateway.scheduledRequests, hasLength(1));
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-2')
              .single
              .platformAlarmId,
          'old-native-2',
        );
      },
    );

    test(
      'returns recoveryRequired when completed schedule persistence fails',
      () async {
        final originalPlan = buildPlan();
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..failSaveAlarmOccurrencesAtCalls.add(3)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ]
          ..storedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = _SequencedFaultGateway();

        final result = await service(store: store, gateway: gateway).editPlan(
          buildPlan(
            targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
              hour: 7,
              minute: 30,
            ),
          ),
        );

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.changeState, WakePlanChangeState.recoveryRequired);
        expect(result.persistenceError, isNotNull);
        expect(result.databaseState, WakePlanDatabaseState.persisted);
        expect(gateway.cancelledOccurrences, hasLength(5));
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
      },
    );

    test(
      'returns recoveryRequired when partial schedule persistence fails',
      () async {
        final originalPlan = buildPlan();
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..failSaveAlarmOccurrencesAtCalls.add(3)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ]
          ..storedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          scheduleFailuresByCall: [
            {'plan-1:20640:440'},
          ],
        );

        final result = await service(store: store, gateway: gateway).editPlan(
          buildPlan(
            targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
              hour: 7,
              minute: 30,
            ),
          ),
        );

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.persistenceError, isNotNull);
        expect(gateway.cancelledOccurrences, hasLength(4));
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
      },
    );

    test(
      'returns recoveryRequired when restoration persistence fails',
      () async {
        final originalPlan = buildPlan();
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..failSaveAlarmOccurrencesAtCalls.add(5)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ]
          ..storedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          scheduleFailuresByCall: [
            {'plan-1:20640:440'},
          ],
        );

        final result = await service(store: store, gateway: gateway).editPlan(
          buildPlan(
            targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
              hour: 7,
              minute: 30,
            ),
          ),
        );

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.databaseState, WakePlanDatabaseState.unknown);
        expect(result.persistenceError, isNotNull);
        expect(gateway.scheduledRequests.last.occurrenceId, 'old-future-1');
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          isNull,
        );
      },
    );

    test(
      'restores successful old cancellations after a partial old cancel',
      () async {
        final originalPlan = buildPlan();
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
            buildOccurrence(
              id: 'old-future-2',
              platformAlarmId: 'old-native-2',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          cancelFailuresByCall: [
            {'old-native-2'},
          ],
        );

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
        expect(result.compensationScheduleResult!.isSuccess, isTrue);
        expect(gateway.scheduledRequests, hasLength(1));
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-2')
              .single
              .platformAlarmId,
          'old-native-2',
        );
      },
    );

    test(
      'preserves canonical native indexes when restoring a cancelled subset',
      () async {
        final originalPlan = buildPlan(
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        );
        final editedPlan = originalPlan.copyWith(
          targetTime: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 30),
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: originalPlan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'legacy-old-1',
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
              platformAlarmId: 'old-native-1',
            ),
            buildOccurrence(
              id: 'legacy-old-2',
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
              platformAlarmId: 'old-native-2',
            ),
            buildOccurrence(
              id: 'legacy-old-3',
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
              platformAlarmId: 'old-native-3',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          cancelFailuresByCall: [
            {'old-native-1'},
          ],
        );

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 2,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.cancelFailed);
        expect(result.compensationScheduleResult!.isSuccess, isTrue);
        expect(
          gateway.scheduledRequests.map((request) => request.indexInPlan),
          [1, 2],
        );
        expect(
          gateway.scheduledRequests.map((request) => request.totalInPlan),
          [8, 8],
        );
      },
    );

    test(
      'returns recoveryRequired when old-cancel compensation also fails',
      () async {
        final originalPlan = buildPlan();
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
            buildOccurrence(
              id: 'old-future-2',
              platformAlarmId: 'old-native-2',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          scheduleFailuresByCall: [
            {'old-future-1'},
          ],
          cancelFailuresByCall: [
            {'old-native-2'},
          ],
        );

        final result = await service(
          store: store,
          gateway: gateway,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.changeState, WakePlanChangeState.recoveryRequired);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.recoveryRequired,
        );
        expect(result.compensationScheduleResult!.isSuccess, isFalse);
        expect(store.currentPlan!.targetTime, originalPlan.targetTime);
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          isNull,
        );
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-2')
              .single
              .platformAlarmId,
          'old-native-2',
        );
      },
    );

    test(
      'keeps the edited plan recoverable when replacement cancellation is partial',
      () async {
        final originalPlan = buildPlan();
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
        final gateway = _SequencedFaultGateway(
          scheduleFailuresByCall: [
            {'plan-1:20640:440'},
          ],
          cancelFailuresByCall: [
            {},
            {'platform-plan-1:20640:435'},
          ],
        );

        final result = await service(
          store: store,
          gateway: gateway,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.changeState, WakePlanChangeState.recoveryRequired);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.recoveryRequired,
        );
        expect(result.compensationCancelResult!.isSuccess, isFalse);
        expect(store.currentPlan!.targetTime, editedPlan.targetTime);
        expect(gateway.scheduledRequests, hasLength(4));
        expect(
          result.occurrences
              .where((occurrence) => occurrence.id == 'plan-1:20640:440')
              .single
              .status,
          AlarmOccurrenceStatus.failed,
        );
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'plan-1:20640:435')
              .single
              .platformAlarmId,
          'platform-plan-1:20640:435',
        );
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          isNull,
        );
      },
    );

    test('does not restore stale skip state from an edit payload', () async {
      final editedPlan = buildPlan(
        repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
      ).copyWith(skipNextDate: monday);
      final currentPlan = buildPlan(
        repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: currentPlan);
      final gateway = FakeNativeAlarmGateway();

      final result = await service(
        store: store,
        gateway: gateway,
        rollingScheduleDays: 2,
      ).editPlan(editedPlan);

      expect(result.status, WakePlanSchedulingStatus.scheduled);
      expect(store.savedPlans.first.skipNextDate, isNull);
    });

    test(
      'preserves current skip state when an edit keeps that repeat day',
      () async {
        final editedPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 7,
            minute: 30,
          ),
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        );
        final currentPlan = buildPlan(
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        ).copyWith(skipNextDate: monday);
        final store = _LoggingWakePlanServiceStore(currentPlan: currentPlan);
        final gateway = FakeNativeAlarmGateway();

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 2,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(store.savedPlans.first.skipNextDate, monday);
        expect(store.savedPlans.first.targetTime, editedPlan.targetTime);
      },
    );

    test(
      'clears current skip state when an edit removes that repeat day',
      () async {
        final editedPlan = buildPlan(
          repeatRule: RepeatRule.weekly({Weekday.tuesday}),
        );
        final currentPlan = buildPlan(
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        ).copyWith(skipNextDate: monday);
        final store = _LoggingWakePlanServiceStore(currentPlan: currentPlan);
        final gateway = FakeNativeAlarmGateway();

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 2,
        ).editPlan(editedPlan);

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(store.savedPlans.first.skipNextDate, isNull);
        expect(
          store.savedPlans.first.repeatRule,
          RepeatRule.weekly({Weekday.tuesday}),
        );
      },
    );
  });

  test(
    'edit preserves unknown suppression for a retained occurrence identity',
    () async {
      final original = buildPlan(
        repeatRule: RepeatRule.weekly({Weekday.monday}),
      );
      final edited = buildPlan(
        repeatRule: RepeatRule.weekly({Weekday.monday}),
        vibrationEnabled: false,
      );
      final unknown = buildOccurrence(
        id: 'plan-1:20640:420',
        status: AlarmOccurrenceStatus.unknownPersisted,
        platformAlarmId: 'native-unknown',
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: original)
        ..reservedOccurrences = [unknown]
        ..storedOccurrences = [unknown];
      final gateway = FakeNativeAlarmGateway()
        ..inventoryRows.add(
          NativeAlarmInventoryRow(
            reservationId: unknown.id,
            occurrenceId: unknown.id,
            wakePlanId: original.id,
            platformAlarmId: unknown.platformAlarmId!,
            status: NativeAlarmReservationStatus.scheduled,
          ),
        );

      final result = await service(
        store: store,
        gateway: gateway,
        rollingScheduleDays: 1,
      ).editPlan(edited);

      expect(result.status, WakePlanSchedulingStatus.scheduled);
      expect(
        store.storedOccurrences.singleWhere((item) => item.id == unknown.id),
        isA<AlarmOccurrence>()
            .having(
              (item) => item.status,
              'status',
              AlarmOccurrenceStatus.unknownPersisted,
            )
            .having((item) => item.platformAlarmId, 'platformAlarmId', isNull),
      );
      expect(
        gateway.scheduledRequests.where(
          (request) => request.occurrenceId == unknown.id,
        ),
        isEmpty,
      );
    },
  );

  test(
    'edit cancels changed unknown identity without suppressing new ones',
    () async {
      final original = buildPlan(
        repeatRule: RepeatRule.weekly({Weekday.monday}),
      );
      final edited = buildPlan(
        targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
          hour: 7,
          minute: 30,
        ),
        repeatRule: RepeatRule.weekly({Weekday.monday}),
      );
      final unknown = buildOccurrence(
        id: 'plan-1:20640:420',
        status: AlarmOccurrenceStatus.unknownPersisted,
        platformAlarmId: 'native-unknown',
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: original)
        ..reservedOccurrences = [unknown]
        ..storedOccurrences = [unknown];
      final gateway = FakeNativeAlarmGateway();

      await service(
        store: store,
        gateway: gateway,
        rollingScheduleDays: 1,
      ).editPlan(edited);

      expect(
        store.storedOccurrences.singleWhere((item) => item.id == unknown.id),
        isA<AlarmOccurrence>()
            .having(
              (item) => item.status,
              'status',
              AlarmOccurrenceStatus.unknownPersisted,
            )
            .having((item) => item.platformAlarmId, 'platformAlarmId', isNull),
      );
      expect(
        gateway.scheduledRequests.map((request) => request.occurrenceId),
        contains('plan-1:20640:450'),
      );
    },
  );

  test(
    'edit preserves id-less forward-unknown suppression on authoritative absence',
    () async {
      final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
      final unknown = buildOccurrence(
        id: 'plan-1:20640:420',
        status: AlarmOccurrenceStatus.unknownPersisted,
        platformAlarmId: null,
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..reservedOccurrences = [unknown]
        ..storedOccurrences = [unknown];
      final gateway = FakeNativeAlarmGateway();

      final result = await service(
        store: store,
        gateway: gateway,
        rollingScheduleDays: 1,
      ).editPlan(plan.copyWith(soundId: 'edited'));

      expect(result.status, WakePlanSchedulingStatus.scheduled);
      expect(
        store.storedOccurrences.singleWhere((item) => item.id == unknown.id),
        isA<AlarmOccurrence>()
            .having(
              (item) => item.status,
              'status',
              AlarmOccurrenceStatus.unknownPersisted,
            )
            .having((item) => item.platformAlarmId, 'platformAlarmId', isNull),
      );
      expect(
        gateway.scheduledRequests.where(
          (request) => request.occurrenceId == unknown.id,
        ),
        isEmpty,
      );
    },
  );

  test('edit blocks when unknown native identity cannot be verified', () async {
    final plan = buildPlan(repeatRule: RepeatRule.weekly({Weekday.monday}));
    final unknown = buildOccurrence(
      id: 'plan-1:20640:420',
      status: AlarmOccurrenceStatus.unknownPersisted,
      platformAlarmId: null,
    );
    final store = _LoggingWakePlanServiceStore(currentPlan: plan)
      ..reservedOccurrences = [unknown]
      ..storedOccurrences = [unknown];
    final gateway = FakeNativeAlarmGateway()
      ..inventoryFailureReason = NativeAlarmInventoryFailureReason.nativeError;

    final result = await service(
      store: store,
      gateway: gateway,
      rollingScheduleDays: 1,
    ).editPlan(plan.copyWith(vibrationEnabled: false));

    expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
    expect(gateway.scheduledRequests, isEmpty);
    expect(store.currentPlan!.vibrationEnabled, isTrue);
    expect(
      store.storedOccurrences.single.status,
      AlarmOccurrenceStatus.unknownPersisted,
    );
  });

  group('WakePlanService authoritative cancellation inventory', () {
    for (final operation in ['edit', 'delete']) {
      test(
        '$operation distinguishes absence, unavailable inventory, and exact active tuples',
        () async {
          for (final inventoryCase in ['absent', 'unavailable', 'active']) {
            final plan = buildPlan();
            final occurrence = buildOccurrence(
              id: 'old-future-$operation-$inventoryCase',
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
              platformAlarmId: 'stale-$operation-$inventoryCase',
            );
            final store = _LoggingWakePlanServiceStore(currentPlan: plan)
              ..reservedOccurrences = [occurrence]
              ..storedOccurrences = [occurrence];
            final gateway = _StrictMissingMirrorGateway();
            if (inventoryCase == 'unavailable') {
              withUnavailableInventory(gateway);
              gateway.inventoryRows.add(
                inventoryRow(
                  occurrence,
                  platformAlarmId: occurrence.platformAlarmId!,
                ),
              );
            } else if (inventoryCase == 'active') {
              gateway.inventoryRows.add(
                inventoryRow(
                  occurrence,
                  platformAlarmId: 'authoritative-$operation',
                ),
              );
            }

            final result = operation == 'edit'
                ? await service(store: store, gateway: gateway).editPlan(
                    plan.copyWith(
                      targetTime: TimeOfDayMinutes.fromHourMinute(
                        hour: 7,
                        minute: 30,
                      ),
                    ),
                  )
                : await service(
                    store: store,
                    gateway: gateway,
                  ).deletePlan(plan.id);

            expect(
              result.status,
              operation == 'edit'
                  ? WakePlanSchedulingStatus.scheduled
                  : WakePlanSchedulingStatus.deleted,
              reason: '$operation/$inventoryCase',
            );
            final cancelled = operation == 'edit'
                ? gateway.cancelledOccurrences
                : gateway.cancelledPlans;
            if (inventoryCase == 'absent') {
              expect(cancelled, isEmpty, reason: '$operation/$inventoryCase');
            } else {
              expect(
                cancelled.single.platformAlarmId,
                inventoryCase == 'active'
                    ? 'authoritative-$operation'
                    : occurrence.platformAlarmId,
                reason: '$operation/$inventoryCase',
              );
            }
            expect(
              store.storedOccurrences.singleWhere(
                (item) => item.id == occurrence.id,
              ),
              isA<AlarmOccurrence>()
                  .having(
                    (item) => item.status,
                    'status',
                    AlarmOccurrenceStatus.cancelled,
                  )
                  .having(
                    (item) => item.platformAlarmId,
                    'platformAlarmId',
                    isNull,
                  ),
              reason: '$operation/$inventoryCase',
            );
          }
        },
      );
    }
  });

  group('WakePlanService deletePlan', () {
    test('deletion cancels a conservatively decoded native alarm', () async {
      final plan = buildPlan();
      final withId = buildOccurrence(
        id: 'unknown-with-id',
        status: AlarmOccurrenceStatus.unknownPersisted,
        platformAlarmId: 'native-unknown',
      );
      final store = _LoggingWakePlanServiceStore(currentPlan: plan)
        ..reservedOccurrences = [withId]
        ..storedOccurrences = [withId];
      final gateway = withUnavailableInventory(FakeNativeAlarmGateway());

      final result = await service(
        store: store,
        gateway: gateway,
      ).deletePlan(plan.id);

      expect(result.status, WakePlanSchedulingStatus.deleted);
      expect(gateway.cancelledPlans.single.platformAlarmId, 'native-unknown');
      expect(store.deletedPlanIds, [plan.id]);
      expect(
        store.storedOccurrences.singleWhere((item) => item.id == withId.id),
        isA<AlarmOccurrence>()
            .having(
              (item) => item.status,
              'status',
              AlarmOccurrenceStatus.unknownPersisted,
            )
            .having((item) => item.platformAlarmId, 'platformAlarmId', isNull),
      );
    });
    test(
      'deletion accepts authoritative absence for an unknown native identity',
      () async {
        final plan = buildPlan();
        final unknown = buildOccurrence(
          id: 'unknown-without-id',
          status: AlarmOccurrenceStatus.unknownPersisted,
          platformAlarmId: null,
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..reservedOccurrences = [unknown]
          ..storedOccurrences = [unknown];
        final gateway = FakeNativeAlarmGateway();

        final result = await service(
          store: store,
          gateway: gateway,
        ).deletePlan(plan.id);

        expect(result.status, WakePlanSchedulingStatus.deleted);
        expect(store.deletedPlanIds, [plan.id]);
        expect(gateway.cancelledPlans, isEmpty);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.unknownPersisted,
        );
      },
    );
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
      final gateway = withUnavailableInventory(FakeNativeAlarmGateway());

      final result = await service(
        store: store,
        gateway: gateway,
      ).deletePlan('plan-1');

      expect(result.status, WakePlanSchedulingStatus.deleted);
      expect(store.operations, [
        'fetchWakePlan:plan-1',
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
      final gateway = withUnavailableInventory(
        FakeNativeAlarmGateway()..cancelFailurePlatformAlarmIds.add('native-1'),
      );

      final result = await service(
        store: store,
        gateway: gateway,
      ).deletePlan('plan-1');

      expect(result.status, WakePlanSchedulingStatus.cancelFailed);
      expect(result.changeState, WakePlanChangeState.failed);
      expect(store.operations, [
        'fetchWakePlan:plan-1',
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

    test(
      'restores successful reservations after a partial delete cancellation',
      () async {
        final plan = buildPlan();
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
            buildOccurrence(
              id: 'old-future-2',
              platformAlarmId: 'old-native-2',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          cancelFailuresByCall: [
            {'old-native-2'},
          ],
        );

        final result = await service(
          store: store,
          gateway: gateway,
        ).deletePlan('plan-1');

        expect(result.status, WakePlanSchedulingStatus.cancelFailed);
        expect(result.changeState, WakePlanChangeState.failed);
        expect(result.compensationScheduleResult!.isSuccess, isTrue);
        expect(store.deletedPlanIds, isEmpty);
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-2')
              .single
              .platformAlarmId,
          'old-native-2',
        );
      },
    );

    test(
      'returns recoveryRequired when delete cancellation compensation fails',
      () async {
        final plan = buildPlan();
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
            buildOccurrence(
              id: 'old-future-2',
              platformAlarmId: 'old-native-2',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          scheduleFailuresByCall: [
            {'old-future-1'},
          ],
          cancelFailuresByCall: [
            {'old-native-2'},
          ],
        );

        final result = await service(
          store: store,
          gateway: gateway,
        ).deletePlan('plan-1');

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.changeState, WakePlanChangeState.recoveryRequired);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.recoveryRequired,
        );
        expect(result.compensationScheduleResult!.isSuccess, isFalse);
        expect(store.deletedPlanIds, isEmpty);
      },
    );

    test(
      'restores reservations when the delete database write fails',
      () async {
        final plan = buildPlan();
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..failSoftDelete = true
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = _SequencedFaultGateway();

        final result = await service(
          store: store,
          gateway: gateway,
        ).deletePlan('plan-1');

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.changeState, WakePlanChangeState.recoveryRequired);
        expect(
          result.warning!.kind,
          WakePlanSchedulingWarningKind.recoveryRequired,
        );
        expect(store.deletedPlanIds, isEmpty);
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
      },
    );

    test(
      'returns recoveryRequired when delete cancellation persistence fails',
      () async {
        final plan = buildPlan();
        final store = _LoggingWakePlanServiceStore(currentPlan: plan)
          ..failSaveAlarmOccurrencesAtCalls.add(1)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ]
          ..storedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              platformAlarmId: 'old-native-1',
            ),
          ];

        final result = await service(
          store: store,
          gateway: FakeNativeAlarmGateway(),
        ).deletePlan('plan-1');

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(result.databaseState, WakePlanDatabaseState.persisted);
        expect(result.persistenceError, isNotNull);
        expect(store.deletedPlanIds, isEmpty);
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
      },
    );
  });

  group('WakePlanService skipNextOccurrence', () {
    test('does not strand one-time plans in a skipped state', () async {
      final oneTimePlan = buildPlan();
      final store = _LoggingWakePlanServiceStore(currentPlan: oneTimePlan);
      final gateway = FakeNativeAlarmGateway();

      final result = await service(
        store: store,
        gateway: gateway,
      ).skipNextOccurrence(oneTimePlan);

      expect(result.status, WakePlanSchedulingStatus.scheduled);
      expect(store.operations, ['fetchWakePlan:plan-1']);
      expect(gateway.cancelledOccurrences, isEmpty);
      expect(gateway.scheduledRequests, isEmpty);
    });

    test(
      'stores the next target date and recreates following concrete alarms',
      () async {
        final weeklyPlan = buildPlan(
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: weeklyPlan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'monday-old',
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
              platformAlarmId: 'native-monday',
            ),
            buildOccurrence(
              id: 'tuesday-old',
              day: tuesday,
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
              platformAlarmId: 'native-tuesday',
            ),
          ];
        final gateway = withUnavailableInventory(FakeNativeAlarmGateway());

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 2,
        ).skipNextOccurrence(weeklyPlan);

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(store.savedPlans.first.skipNextDate, monday);
        expect(gateway.cancelledOccurrences.map((request) => request.idLabel), [
          'monday-old/native-monday',
          'tuesday-old/native-tuesday',
        ]);
        expect(
          result.occurrences.map((occurrence) => occurrence.scheduledAt.day),
          everyElement(tuesday),
        );
      },
    );

    test(
      'skip restores the old reservation when replacement scheduling fails',
      () async {
        final weeklyPlan = buildPlan(
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: weeklyPlan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          scheduleFailuresByCall: [
            {'plan-1:20641:405'},
          ],
        );

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 2,
        ).skipNextOccurrence(weeklyPlan);

        expect(result.status, WakePlanSchedulingStatus.scheduleFailed);
        expect(result.changeState, WakePlanChangeState.failed);
        expect(result.compensationScheduleResult!.isSuccess, isTrue);
        expect(store.currentPlan!.skipNextDate, isNull);
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
      },
    );

    test(
      'undo clears skip date and makes the next target reservable again',
      () async {
        final skippedPlan = buildPlan(
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        ).copyWith(skipNextDate: monday);
        final store = _LoggingWakePlanServiceStore(currentPlan: skippedPlan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'tuesday-old',
              day: tuesday,
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
              platformAlarmId: 'native-tuesday',
            ),
          ];
        final gateway = FakeNativeAlarmGateway();

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 2,
        ).undoSkipNextOccurrence(skippedPlan);

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(store.savedPlans.first.skipNextDate, isNull);
        expect(
          result.occurrences.map((occurrence) => occurrence.scheduledAt.day),
          contains(monday),
        );
        expect(
          result.occurrences.map((occurrence) => occurrence.scheduledAt.day),
          contains(tuesday),
        );
      },
    );

    test(
      'undo restores the old reservation when replacement scheduling fails',
      () async {
        final skippedPlan = buildPlan(
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        ).copyWith(skipNextDate: monday);
        final store = _LoggingWakePlanServiceStore(currentPlan: skippedPlan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'old-future-1',
              day: tuesday,
              time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 45),
              platformAlarmId: 'old-native-1',
            ),
          ];
        final gateway = _SequencedFaultGateway(
          scheduleFailuresByCall: [
            {'plan-1:20640:405'},
          ],
        );

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 2,
        ).undoSkipNextOccurrence(skippedPlan);

        expect(result.status, WakePlanSchedulingStatus.scheduleFailed);
        expect(result.changeState, WakePlanChangeState.failed);
        expect(result.compensationScheduleResult!.isSuccess, isTrue);
        expect(store.currentPlan!.skipNextDate, monday);
        expect(
          store.storedOccurrences
              .where((occurrence) => occurrence.id == 'old-future-1')
              .single
              .platformAlarmId,
          'platform-old-future-1',
        );
      },
    );

    test(
      'uses the current stored plan instead of a stale UI snapshot when skipping',
      () async {
        final staleSnapshot = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 7,
            minute: 0,
          ),
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        );
        final currentPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 8,
            minute: 0,
          ),
          repeatRule: RepeatRule.weekly({Weekday.tuesday}),
        );
        final store = _LoggingWakePlanServiceStore(currentPlan: currentPlan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'current-old',
              day: tuesday,
              time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 45),
              platformAlarmId: 'native-current',
            ),
          ];
        final gateway = FakeNativeAlarmGateway();

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 2,
        ).skipNextOccurrence(staleSnapshot);

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(store.savedPlans.first.targetTime, currentPlan.targetTime);
        expect(store.savedPlans.first.repeatRule, currentPlan.repeatRule);
        expect(store.savedPlans.first.skipNextDate, tuesday);
        expect(
          result.occurrences.map((occurrence) => occurrence.scheduledAt.day),
          isEmpty,
        );
      },
    );

    test(
      'uses the current stored plan instead of a stale UI snapshot when undoing',
      () async {
        final staleSnapshot = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 7,
            minute: 0,
          ),
          repeatRule: RepeatRule.weekly({Weekday.monday, Weekday.tuesday}),
        ).copyWith(skipNextDate: monday);
        final currentPlan = buildPlan(
          targetTimeOverride: TimeOfDayMinutes.fromHourMinute(
            hour: 8,
            minute: 0,
          ),
          repeatRule: RepeatRule.weekly({Weekday.tuesday}),
        ).copyWith(skipNextDate: tuesday);
        final store = _LoggingWakePlanServiceStore(currentPlan: currentPlan)
          ..reservedOccurrences = [
            buildOccurrence(
              id: 'current-old',
              day: tuesday,
              time: TimeOfDayMinutes.fromHourMinute(hour: 7, minute: 45),
              platformAlarmId: 'native-current',
            ),
          ];
        final gateway = FakeNativeAlarmGateway();

        final result = await service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 2,
        ).undoSkipNextOccurrence(staleSnapshot);

        expect(result.status, WakePlanSchedulingStatus.scheduled);
        expect(store.savedPlans.first.targetTime, currentPlan.targetTime);
        expect(store.savedPlans.first.repeatRule, currentPlan.repeatRule);
        expect(store.savedPlans.first.skipNextDate, isNull);
        expect(
          result.occurrences.map((occurrence) => occurrence.scheduledAt.day),
          contains(tuesday),
        );
      },
    );
  });
  group('WakePlanMutationCoordinator', () {
    test('runs queued operations one at a time in submission order', () async {
      final coordinator = WakePlanMutationCoordinator();
      final order = <String>[];
      final firstGate = Completer<void>();

      final first = coordinator.run(() async {
        order.add('first-start');
        await firstGate.future;
        order.add('first-end');
        return 1;
      });
      final second = coordinator.run(() async {
        order.add('second-start');
        return 2;
      });

      await Future<void>.delayed(Duration.zero);
      expect(order, ['first-start']);

      firstGate.complete();
      expect(await first, 1);
      expect(await second, 2);
      expect(order, ['first-start', 'first-end', 'second-start']);
    });

    test('a failed operation does not block later ones', () async {
      final coordinator = WakePlanMutationCoordinator();

      final failed = coordinator.run(() async {
        throw StateError('boom');
      });
      final succeeded = coordinator.run(() async => 'ok');

      await expectLater(failed, throwsA(isA<StateError>()));
      expect(await succeeded, 'ok');
    });
  });
}

class _LoggingWakePlanServiceStore implements WakePlanServiceStore {
  _LoggingWakePlanServiceStore({this.currentPlan});

  final operations = <String>[];
  final savedPlans = <WakePlan>[];
  final savedOccurrences = <List<AlarmOccurrence>>[];
  final deletedPlanIds = <String>[];
  bool failSoftDelete = false;
  final failSaveAlarmOccurrencesAtCalls = <int>{};
  final failSaveAlarmOccurrencesAfterMutationAtCalls = <int>{};
  final failSaveWakePlanAfterMutationAtCalls = <int>{};
  var saveWakePlanCallCount = 0;
  int? blockSaveAlarmOccurrencesAtCall;
  final saveAlarmOccurrencesBlocked = Completer<void>();
  final releaseBlockedSave = Completer<void>();
  var saveAlarmOccurrencesCallCount = 0;
  WakePlan? currentPlan;
  List<WakePlan> wakePlans = [];
  List<AlarmOccurrence> reservedOccurrences = [];
  List<AlarmOccurrence> storedOccurrences = [];
  Set<String> corruptPlanIds = {};
  Set<String> corruptOccurrenceIds = {};
  Set<String> corruptOccurrenceWakePlanIds = {};
  Set<String> corruptPlatformAlarmIds = {};
  final fetchPlanNows = <DateTime>[];

  @override
  Future<WakePlan?> fetchWakePlan(String id) async {
    operations.add('fetchWakePlan:$id');
    return currentPlan?.id == id ? currentPlan : null;
  }

  @override
  Future<WakePlanReconciliationSnapshot> fetchReconciliationSnapshot({
    required DateTime now,
  }) async {
    operations.add('fetchReconciliationSnapshot');
    fetchPlanNows.add(now);
    return WakePlanReconciliationSnapshot(
      plans: wakePlans,
      occurrences: storedOccurrences,
      corruptPlanIds: corruptPlanIds,
      corruptOccurrenceIds: corruptOccurrenceIds,
      corruptOccurrenceWakePlanIds: corruptOccurrenceWakePlanIds,
    );
  }

  @override
  Future<AlarmOccurrencePlatformMatchSnapshot>
  fetchAlarmOccurrencesByPlatformAlarmIds(Set<String> platformAlarmIds) async {
    operations.add('fetchAlarmOccurrencesByPlatformAlarmIds');
    return AlarmOccurrencePlatformMatchSnapshot(
      occurrences: storedOccurrences
          .where(
            (occurrence) =>
                platformAlarmIds.contains(occurrence.platformAlarmId),
          )
          .toList(growable: false),
      corruptPlatformAlarmIds: corruptPlatformAlarmIds.intersection(
        platformAlarmIds,
      ),
    );
  }

  @override
  Future<void> saveWakePlan(WakePlan plan) async {
    saveWakePlanCallCount += 1;
    operations.add('saveWakePlan:${plan.id}');
    savedPlans.add(plan);
    currentPlan = plan;
    if (failSaveWakePlanAfterMutationAtCalls.contains(saveWakePlanCallCount)) {
      throw StateError(
        'injected post-mutation wake plan persistence failure at call '
        '$saveWakePlanCallCount',
      );
    }
  }

  @override
  Future<void> softDeleteWakePlan({
    required String id,
    required DateTime updatedAt,
  }) async {
    operations.add('softDeleteWakePlan:$id');
    if (failSoftDelete) {
      throw StateError('injected soft-delete failure');
    }
    deletedPlanIds.add(id);
  }

  @override
  Future<void> saveAlarmOccurrences(
    Iterable<AlarmOccurrence> occurrences,
  ) async {
    saveAlarmOccurrencesCallCount += 1;
    final snapshot = occurrences.toList(growable: false);
    operations.add('saveAlarmOccurrences:${snapshot.length}');
    if (failSaveAlarmOccurrencesAtCalls.contains(
      saveAlarmOccurrencesCallCount,
    )) {
      throw StateError(
        'injected alarm occurrence persistence failure at call '
        '$saveAlarmOccurrencesCallCount',
      );
    }
    if (blockSaveAlarmOccurrencesAtCall == saveAlarmOccurrencesCallCount) {
      if (!saveAlarmOccurrencesBlocked.isCompleted) {
        saveAlarmOccurrencesBlocked.complete();
      }
      await releaseBlockedSave.future;
    }
    savedOccurrences.add(snapshot);
    final byId = {
      for (final occurrence in storedOccurrences) occurrence.id: occurrence,
    };
    for (final occurrence in snapshot) {
      byId[occurrence.id] = occurrence;
    }
    storedOccurrences = byId.values.toList(growable: false);
    if (failSaveAlarmOccurrencesAfterMutationAtCalls.contains(
      saveAlarmOccurrencesCallCount,
    )) {
      throw StateError(
        'injected post-mutation alarm occurrence persistence failure at call '
        '$saveAlarmOccurrencesCallCount',
      );
    }
  }

  @override
  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(
    String wakePlanId,
  ) async {
    operations.add('fetchOccurrencesForPlan:$wakePlanId');
    return storedOccurrences
        .where((occurrence) => occurrence.wakePlanId == wakePlanId)
        .toList(growable: false);
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

class _ObservingAckGateway extends FakeNativeAlarmGateway {
  _ObservingAckGateway({required this.onAcknowledge});

  final void Function() onAcknowledge;

  @override
  Future<void> acknowledgeAlarmEvents(List<String> eventIds) async {
    onAcknowledge();
    await super.acknowledgeAlarmEvents(eventIds);
  }
}

class _FailingAckGateway extends FakeNativeAlarmGateway {
  bool failAcknowledgement = true;

  @override
  Future<void> acknowledgeAlarmEvents(List<String> eventIds) async {
    if (failAcknowledgement) {
      throw StateError('injected acknowledgement failure');
    }
    await super.acknowledgeAlarmEvents(eventIds);
  }
}

class _DuplicateEventGateway extends FakeNativeAlarmGateway {
  _DuplicateEventGateway({required this.event});

  final NativeAlarmEvent event;

  @override
  Future<List<NativeAlarmEvent>> fetchAlarmEvents() async => [event, event];
}

class _StrictMissingMirrorGateway extends FakeNativeAlarmGateway {
  @override
  Future<CancelResult> cancelOccurrences(
    List<NativeAlarmCancelRequest> alarms,
  ) async {
    return _cancelStrictly(alarms, cancelledOccurrences);
  }

  @override
  Future<CancelResult> cancelPlan(List<NativeAlarmCancelRequest> alarms) async {
    return _cancelStrictly(alarms, cancelledPlans);
  }

  CancelResult _cancelStrictly(
    List<NativeAlarmCancelRequest> alarms,
    List<NativeAlarmCancelRequest> recorded,
  ) {
    CancelResult.validateRequests(alarms);
    recorded.addAll(alarms);
    final results = alarms
        .map((alarm) {
          final hasExactMirror = inventoryRows.any(
            (row) =>
                row.reservationId == alarm.reservationId &&
                row.occurrenceId == alarm.occurrenceId &&
                row.platformAlarmId == alarm.platformAlarmId,
          );
          if (!hasExactMirror) {
            return CancelAlarmResult.failure(
              occurrenceId: alarm.occurrenceId,
              platformAlarmId: alarm.platformAlarmId,
              reservationId: alarm.reservationId,
              reason: CancelFailureReason.invalidRequest,
              message: 'The strict native mirror has no matching reservation.',
            );
          }
          inventoryRows.removeWhere(
            (row) =>
                row.reservationId == alarm.reservationId &&
                row.occurrenceId == alarm.occurrenceId &&
                row.platformAlarmId == alarm.platformAlarmId,
          );
          return CancelAlarmResult.success(
            occurrenceId: alarm.occurrenceId,
            platformAlarmId: alarm.platformAlarmId,
            reservationId: alarm.reservationId,
          );
        })
        .toList(growable: false);
    return CancelResult.fromRequestResults(requests: alarms, results: results);
  }
}

class _ThrowingOccurrenceGateway extends FakeNativeAlarmGateway {
  _ThrowingOccurrenceGateway({
    this.throwOnCancel = false,
    this.throwOnSchedule = false,
  });

  final bool throwOnCancel;
  final bool throwOnSchedule;

  @override
  Future<CancelResult> cancelOccurrences(
    List<NativeAlarmCancelRequest> alarms,
  ) {
    if (throwOnCancel) {
      throw StateError('injected cancellation exception');
    }
    return super.cancelOccurrences(alarms);
  }

  @override
  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  ) {
    if (throwOnSchedule) {
      throw StateError('injected scheduling exception');
    }
    return super.scheduleOccurrences(occurrences);
  }
}

class _OneShotCancelExceptionGateway extends FakeNativeAlarmGateway {
  var _didThrow = false;

  @override
  Future<CancelResult> cancelOccurrences(
    List<NativeAlarmCancelRequest> alarms,
  ) {
    if (!_didThrow) {
      _didThrow = true;
      throw StateError('injected pre-cancel response exception');
    }
    return super.cancelOccurrences(alarms);
  }
}

class _PostSideEffectThrowingGateway extends FakeNativeAlarmGateway {
  _PostSideEffectThrowingGateway({
    this.throwAfterCancel = false,
    this.throwAfterSchedule = false,
    this.throwOnInventory = false,
  });

  bool throwAfterCancel;
  bool throwAfterSchedule;
  final bool throwOnInventory;

  @override
  Future<NativeAlarmInventoryResult> getInventory() {
    if (throwOnInventory) {
      throw FormatException('injected malformed inventory response');
    }
    return super.getInventory();
  }

  @override
  Future<CancelResult> cancelOccurrences(
    List<NativeAlarmCancelRequest> alarms,
  ) async {
    final result = await super.cancelOccurrences(alarms);
    if (throwAfterCancel) {
      throwAfterCancel = false;
      throw StateError('injected post-cancel response exception');
    }
    return result;
  }

  @override
  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  ) async {
    final result = await super.scheduleOccurrences(occurrences);
    if (throwAfterSchedule) {
      throwAfterSchedule = false;
      throw StateError('injected post-schedule response exception');
    }
    return result;
  }
}

class _CountingInventoryGateway extends FakeNativeAlarmGateway {
  _CountingInventoryGateway({this.throwOnRead = false});

  bool throwOnRead;
  var inventoryCalls = 0;

  @override
  Future<NativeAlarmInventoryResult> getInventory() {
    inventoryCalls += 1;
    if (throwOnRead) {
      throw StateError('injected native inventory read failure');
    }
    return super.getInventory();
  }
}

class _UncertainPlanMutationCancelGateway extends FakeNativeAlarmGateway {
  _UncertainPlanMutationCancelGateway({required this.applySideEffect});

  final bool applySideEffect;
  var _didThrow = false;

  @override
  Future<CancelResult> cancelOccurrences(
    List<NativeAlarmCancelRequest> alarms,
  ) => _cancel(alarms, () => super.cancelOccurrences(alarms));

  @override
  Future<CancelResult> cancelPlan(List<NativeAlarmCancelRequest> alarms) =>
      _cancel(alarms, () => super.cancelPlan(alarms));

  Future<CancelResult> _cancel(
    List<NativeAlarmCancelRequest> alarms,
    Future<CancelResult> Function() operation,
  ) async {
    if (_didThrow) {
      return operation();
    }
    _didThrow = true;
    if (applySideEffect) {
      await operation();
    }
    throw StateError('injected uncertain cancellation response');
  }
}

class _OneShotRestorationExceptionGateway extends FakeNativeAlarmGateway {
  _OneShotRestorationExceptionGateway({
    required this.error,
    required this.applyNativeSideEffect,
  });

  final Object error;
  final bool applyNativeSideEffect;
  var _didThrow = false;

  @override
  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  ) async {
    if (_didThrow) {
      return super.scheduleOccurrences(occurrences);
    }
    _didThrow = true;
    if (applyNativeSideEffect) {
      await super.scheduleOccurrences(occurrences);
    }
    throw error;
  }
}

class _BlockingCancelGateway extends FakeNativeAlarmGateway {
  final cancelStarted = Completer<void>();
  final releaseCancel = Completer<void>();

  @override
  Future<CancelResult> cancelOccurrences(
    List<NativeAlarmCancelRequest> alarms,
  ) async {
    if (!cancelStarted.isCompleted) {
      cancelStarted.complete();
    }
    await releaseCancel.future;
    return super.cancelOccurrences(alarms);
  }
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

class _SequencedFaultGateway extends FakeNativeAlarmGateway {
  _SequencedFaultGateway({
    this.scheduleFailuresByCall = const [],
    this.cancelFailuresByCall = const [],
  }) : super(
         capability: const NativeAlarmCapability(
           permissionStatus: NativeAlarmPermissionStatus.authorized,
           canScheduleAlarms: true,
           canRequestPermission: true,
           supportsInventory: false,
         ),
       );

  final List<Set<String>> scheduleFailuresByCall;
  final List<Set<String>> cancelFailuresByCall;
  var scheduleCallCount = 0;
  var cancelCallCount = 0;

  @override
  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  ) async {
    scheduleCallCount += 1;
    final previousFailures = Set<String>.of(scheduleFailureOccurrenceIds);
    scheduleFailureOccurrenceIds
      ..clear()
      ..addAll(_at(scheduleFailuresByCall, scheduleCallCount));
    try {
      return await super.scheduleOccurrences(occurrences);
    } finally {
      scheduleFailureOccurrenceIds
        ..clear()
        ..addAll(previousFailures);
    }
  }

  @override
  Future<CancelResult> cancelOccurrences(
    List<NativeAlarmCancelRequest> alarms,
  ) async {
    cancelCallCount += 1;
    return _cancelWithSequence(alarms, () => super.cancelOccurrences(alarms));
  }

  @override
  Future<CancelResult> cancelPlan(List<NativeAlarmCancelRequest> alarms) async {
    cancelCallCount += 1;
    return _cancelWithSequence(alarms, () => super.cancelPlan(alarms));
  }

  Future<CancelResult> _cancelWithSequence(
    List<NativeAlarmCancelRequest> alarms,
    Future<CancelResult> Function() operation,
  ) async {
    final previousFailures = Set<String>.of(cancelFailurePlatformAlarmIds);
    cancelFailurePlatformAlarmIds
      ..clear()
      ..addAll(_at(cancelFailuresByCall, cancelCallCount));
    try {
      return await operation();
    } finally {
      cancelFailurePlatformAlarmIds
        ..clear()
        ..addAll(previousFailures);
    }
  }

  Set<String> _at(List<Set<String>> values, int call) {
    return call <= values.length ? values[call - 1] : const {};
  }
}

class _BlockingScheduleGateway extends FakeNativeAlarmGateway {
  final firstScheduleStarted = Completer<void>();
  final releaseFirstSchedule = Completer<void>();
  final scheduledBatches = <List<NativeAlarmScheduleRequest>>[];
  var activeScheduleCalls = 0;
  var maxConcurrentScheduleCalls = 0;
  var scheduleCallCount = 0;

  @override
  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  ) async {
    scheduleCallCount += 1;
    activeScheduleCalls += 1;
    maxConcurrentScheduleCalls =
        activeScheduleCalls > maxConcurrentScheduleCalls
        ? activeScheduleCalls
        : maxConcurrentScheduleCalls;
    scheduledBatches.add(List<NativeAlarmScheduleRequest>.of(occurrences));
    try {
      if (scheduleCallCount == 1) {
        firstScheduleStarted.complete();
        await releaseFirstSchedule.future;
      }
      return await super.scheduleOccurrences(occurrences);
    } finally {
      activeScheduleCalls -= 1;
    }
  }
}

class _EmptyOccurrencePlanner extends OccurrencePlanner {
  @override
  OccurrencePlan plan({
    required WakePlan wakePlan,
    required CalendarDay startDay,
    required CalendarDay endExclusive,
    required DateTime now,
  }) {
    return OccurrencePlan(
      wakeInstances: const [],
      previewOccurrences: const [],
      schedulingCandidates: const [],
    );
  }
}
