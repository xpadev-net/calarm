import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/core/platform/native_alarm_gateway.dart';
import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/alarm_ringing/application/alarm_ringing_controller.dart';
import 'package:calarm/features/alarm_ringing/presentation/alarm_ringing_placeholder.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders ringing metadata and only the current stop action', (
    tester,
  ) async {
    var stopped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlarmRingingScreen(
            snapshot: _snapshot(),
            now: DateTime(2026, 7, 6, 6, 50),
            onStop: () async {
              stopped = true;
              return AlarmDismissResult.dismissed;
            },
          ),
        ),
      ),
    );

    expect(find.text('Alarm ringing'), findsOneWidget);
    expect(find.text('Current time'), findsOneWidget);
    expect(find.text('07/06 06:50'), findsOneWidget);
    expect(find.text('Wake target'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('Alarm'), findsOneWidget);
    expect(find.text('2 of 4'), findsOneWidget);
    expect(find.text('Next scheduled'), findsOneWidget);
    expect(find.text('07/06 06:55'), findsOneWidget);
    expect(find.text('Stop current alarm'), findsOneWidget);
    expect(find.textContaining('Snooze'), findsNothing);
    expect(find.textContaining('Skip'), findsNothing);
    expect(find.textContaining('Stop all'), findsNothing);
    expect(find.textContaining('Wake up'), findsNothing);

    await tester.tap(find.text('Stop current alarm'));
    await tester.pumpAndSettle();

    expect(stopped, isTrue);
    expect(find.text('Current alarm stopped.'), findsOneWidget);
  });

  testWidgets('keeps stop action retryable when stop throws', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlarmRingingScreen(
            snapshot: _snapshot(),
            now: DateTime(2026, 7, 6, 6, 50),
            onStop: () async {
              attempts += 1;
              throw StateError('native bridge unavailable');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Stop current alarm'));
    await tester.pump();
    await tester.pump();

    expect(attempts, 1);
    expect(
      find.text('Could not stop the current alarm. Try again.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('keeps inline stop failure visible without reloading snapshot', (
    tester,
  ) async {
    final snapshot = _snapshot();
    final gateway = FakeNativeAlarmGateway()
      ..cancelFailurePlatformAlarmIds.add('native-current')
      ..inventoryRows.add(
        NativeAlarmInventoryRow(
          reservationId: snapshot.currentOccurrence.id,
          occurrenceId: snapshot.currentOccurrence.id,
          wakePlanId: snapshot.currentOccurrence.wakePlanId,
          platformAlarmId: 'native-current',
          status: NativeAlarmReservationStatus.ringing,
        ),
      );
    final store = _AlarmRingingStore([snapshot.currentOccurrence]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmRingingSnapshotProvider.overrideWith((ref) async => snapshot),
          alarmRingingControllerProvider.overrideWith((ref) async {
            return AlarmRingingController(
              store: store,
              nativeAlarmGateway: gateway,
              coordinator: WakePlanMutationCoordinator(),
              clock: () => DateTime(2026, 7, 6, 6, 50),
            );
          }),
          alarmRingingClockProvider.overrideWith(
            (ref) =>
                () => DateTime(2026, 7, 6, 6, 50),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AlarmRingingPlaceholder()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stop current alarm'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not stop the native alarm. Try again.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });
}

AlarmRingingSnapshot _snapshot() {
  final createdAt = DateTime(2026, 7, 6, 5);
  final day = CalendarDay(year: 2026, month: 7, day: 6);
  final plan = WakePlan(
    id: 'plan-1',
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
  return AlarmRingingSnapshot(
    wakePlan: plan,
    currentOccurrence: AlarmOccurrence(
      id: 'plan-1:20640:410',
      wakePlanId: plan.id,
      scheduledAt: DateMinute(
        day: day,
        time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 50),
      ),
      status: AlarmOccurrenceStatus.ringing,
      platformAlarmId: 'native-current',
      firedAt: DateTime(2026, 7, 6, 6, 50),
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
    occurrenceIndex: 2,
    occurrenceCount: 4,
    nextScheduledAt: DateMinute(
      day: day,
      time: TimeOfDayMinutes.fromHourMinute(hour: 6, minute: 55),
    ),
  );
}

class _AlarmRingingStore implements AlarmRingingStore {
  _AlarmRingingStore(Iterable<AlarmOccurrence> occurrences)
    : occurrences = {
        for (final occurrence in occurrences) occurrence.id: occurrence,
      };

  final Map<String, AlarmOccurrence> occurrences;
  final Map<String, AlarmOccurrenceDismissalIntent> pendingDismissals = {};

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
    final existing = pendingDismissals[occurrenceId];
    if (existing != null) {
      return AlarmOccurrenceDismissalPreparation.ready(existing);
    }
    final occurrence = occurrences[occurrenceId];
    if (occurrence == null) {
      return const AlarmOccurrenceDismissalPreparation.notFound();
    }
    if (occurrence.status == AlarmOccurrenceStatus.dismissed) {
      return const AlarmOccurrenceDismissalPreparation.alreadyDismissed();
    }
    final intent = AlarmOccurrenceDismissalIntent(
      occurrence: occurrence,
      requestedAt: requestedAt,
      platformAlarmId: expectedPlatformAlarmId,
    );
    pendingDismissals[occurrenceId] = intent;
    return AlarmOccurrenceDismissalPreparation.ready(intent);
  }

  @override
  Future<void> completeAlarmOccurrenceDismissal({
    required AlarmOccurrenceDismissalIntent intent,
    required DateTime dismissedAt,
  }) async {
    final occurrence = occurrences[intent.occurrence.id]!;
    occurrences[occurrence.id] = occurrence.copyWith(
      status: AlarmOccurrenceStatus.dismissed,
      platformAlarmId: null,
      firedAt: occurrence.firedAt ?? intent.requestedAt,
      dismissedAt: dismissedAt,
      updatedAt: dismissedAt,
    );
    pendingDismissals.remove(occurrence.id);
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
  Future<List<WakePlan>> fetchWakePlans({required DateTime now}) async {
    return const [];
  }
}
