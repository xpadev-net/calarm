import 'dart:async';

import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/application/occurrence_planner.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
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
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );
  }

  WakePlanService service({
    required _LoggingWakePlanServiceStore store,
    required FakeNativeAlarmGateway gateway,
    int rollingScheduleDays = 7,
    DateTime? clockNow,
    OccurrencePlanner occurrencePlanner = const OccurrencePlanner(),
  }) {
    return WakePlanService.withStore(
      store: store,
      nativeAlarmGateway: gateway,
      occurrencePlanner: occurrencePlanner,
      clock: () => clockNow ?? now,
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
        final secondGateway = FakeNativeAlarmGateway();
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

        final nextGateway = FakeNativeAlarmGateway();
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
        await service(
          store: store,
          gateway: FakeNativeAlarmGateway(),
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
        final retryGateway = FakeNativeAlarmGateway();

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
        expect(
          gateway.scheduledRequests.single.scheduledAt,
          DateTime(2026, 7, 6, 7),
        );
        expect(
          gateway.scheduledRequests.single.targetAt,
          DateTime(2026, 7, 6, 7),
        );
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          hasLength(1),
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

      expect(gateway.scheduledRequests, isEmpty);
      expect(
        store.storedOccurrences.single.status,
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
      'persists pending off intent when cancellation reports failure',
      () async {
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'future',
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
      'restores the native reservation when disabled persistence fails',
      () async {
        final plan = buildPlan();
        final occurrence = buildOccurrence(
          id: 'future',
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
        expect(result.compensationScheduleResult!.isSuccess, isTrue);
        expect(
          store.storedOccurrences.single.status,
          AlarmOccurrenceStatus.scheduled,
        );
        expect(store.storedOccurrences.single.platformAlarmId, isNotNull);
      },
    );

    test('persists pending off intent when cancellation throws', () async {
      final plan = buildPlan();
      final occurrence = buildOccurrence(
        id: 'future-throw',
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
              reservationId: occurrence.id,
              occurrenceId: occurrence.id,
              wakePlanId: plan.id,
              platformAlarmId: occurrence.platformAlarmId!,
              status: NativeAlarmReservationStatus.scheduled,
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
        expect(gateway.inventoryRows, isEmpty);

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
      'restores on when uncertain cancellation off intent cannot persist',
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
        expect(result.compensationScheduleResult!.isSuccess, isTrue);
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
        AlarmOccurrenceStatus.scheduled,
      );
      expect(store.storedOccurrences.single.platformAlarmId, isNull);
      expect(gateway.inventoryRows, isEmpty);
    });

    test(
      'restarts one-time on uncertainty without duplicate replenishment',
      () async {
        final plan = buildPlan();
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
          AlarmOccurrenceStatus.scheduled,
        );
        expect(store.storedOccurrences.single.platformAlarmId, isNull);
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          hasLength(1),
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
          isNotNull,
        );
        expect(
          gateway.inventoryRows.where(
            (row) => row.occurrenceId == occurrence.id,
          ),
          hasLength(1),
        );
        expect(
          gateway.scheduledRequests.map((request) => request.occurrenceId),
          [occurrence.id, occurrence.id],
        );
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
          expect(
            store.storedOccurrences.single.status,
            scenario.occurrence.status,
            reason: scenario.name,
          );
        }
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
        final toggleService = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
        );
        final reconciliationService = service(
          store: store,
          gateway: gateway,
          rollingScheduleDays: 1,
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
          expect(store.storedOccurrences.single.platformAlarmId, isNull);

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
            AlarmOccurrenceStatus.scheduled,
            reason: inventoryCase,
          );
          expect(reconciled.platformAlarmId, isNotNull, reason: inventoryCase);
          expect(
            gateway.inventoryRows.where(
              (row) => row.occurrenceId == occurrence.id,
            ),
            hasLength(1),
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
      'pending off without an id never treats absence or inventory failure as off',
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

          expect(
            result.single.status,
            WakePlanSchedulingStatus.recoveryRequired,
            reason: inventoryCase,
          );
          expect(
            store.storedOccurrences
                .singleWhere((item) => item.id == occurrence.id)
                .status,
            AlarmOccurrenceStatus.userDisablePending,
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
            scenario.applyNativeSideEffect ? hasLength(2) : hasLength(1),
          );
        },
      );
    }

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
        final gateway = FakeNativeAlarmGateway()
          ..scheduleFailureOccurrenceIds.add('plan-1:20640:440');

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
      final gateway = FakeNativeAlarmGateway();

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
      'deletion blocks when unknown native identity cannot be verified',
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

        expect(result.status, WakePlanSchedulingStatus.recoveryRequired);
        expect(store.deletedPlanIds, isEmpty);
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
      final gateway = FakeNativeAlarmGateway();

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
      final gateway = FakeNativeAlarmGateway()
        ..cancelFailurePlatformAlarmIds.add('native-1');

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
        final gateway = FakeNativeAlarmGateway();

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
}

class _LoggingWakePlanServiceStore implements WakePlanServiceStore {
  _LoggingWakePlanServiceStore({this.currentPlan});

  final operations = <String>[];
  final savedPlans = <WakePlan>[];
  final savedOccurrences = <List<AlarmOccurrence>>[];
  final deletedPlanIds = <String>[];
  bool failSoftDelete = false;
  final failSaveAlarmOccurrencesAtCalls = <int>{};
  var saveAlarmOccurrencesCallCount = 0;
  WakePlan? currentPlan;
  List<WakePlan> wakePlans = [];
  List<AlarmOccurrence> reservedOccurrences = [];
  List<AlarmOccurrence> storedOccurrences = [];
  final fetchPlanNows = <DateTime>[];

  @override
  Future<WakePlan?> fetchWakePlan(String id) async {
    operations.add('fetchWakePlan:$id');
    return currentPlan?.id == id ? currentPlan : null;
  }

  @override
  Future<List<WakePlan>> fetchWakePlans({required DateTime now}) async {
    operations.add('fetchWakePlans');
    fetchPlanNows.add(now);
    return List<WakePlan>.of(wakePlans);
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
    savedOccurrences.add(snapshot);
    final byId = {
      for (final occurrence in storedOccurrences) occurrence.id: occurrence,
    };
    for (final occurrence in snapshot) {
      byId[occurrence.id] = occurrence;
    }
    storedOccurrences = byId.values.toList(growable: false);
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
    cancelStarted.complete();
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
  });

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
