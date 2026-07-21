import 'package:calarm/app.dart';
import 'package:calarm/core/bootstrap/app_bootstrap.dart';
import 'package:calarm/core/platform/fake_native_alarm_gateway.dart';
import 'package:calarm/features/alarm_ringing/presentation/alarm_ringing_placeholder.dart';
import 'package:calarm/features/wake_plan/application/wake_plan_service_providers.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/week_calendar/presentation/week_calendar_placeholder.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature provider names alias the canonical session providers', () {
    expect(appWakePlanServiceProvider, same(wakePlanServiceProvider));
    expect(weekCalendarWakePlanServiceProvider, same(wakePlanServiceProvider));
    expect(weekCalendarRepositoryProvider, same(appWakePlanRepositoryProvider));
    expect(alarmRingingRepositoryProvider, same(appWakePlanRepositoryProvider));
    expect(
      weekCalendarNativeAlarmGatewayProvider,
      same(appNativeAlarmGatewayProvider),
    );
    expect(
      alarmRingingNativeAlarmGatewayProvider,
      same(appNativeAlarmGatewayProvider),
    );
    expect(weekCalendarClockProvider, same(wakePlanClockProvider));
    expect(alarmRingingClockProvider, same(wakePlanClockProvider));
  });

  test('aliases preserve overrides across feature provider names', () {
    DateTime clock() => DateTime(2026, 7, 22, 7, 30);

    final gateway = FakeNativeAlarmGateway();
    final container = ProviderContainer(
      overrides: [
        weekCalendarClockProvider.overrideWithValue(clock),
        alarmRingingNativeAlarmGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(wakePlanClockProvider), same(clock));
    expect(container.read(alarmRingingClockProvider), same(clock));
    expect(container.read(appNativeAlarmGatewayProvider), same(gateway));
    expect(
      container.read(weekCalendarNativeAlarmGatewayProvider),
      same(gateway),
    );
  });

  test('app and calendar resolve one service instance per session', () async {
    final database = WakePlanDatabase(NativeDatabase.memory());
    final repository = WakePlanRepository(database);
    final gateway = FakeNativeAlarmGateway();
    final container = ProviderContainer(
      overrides: [
        appWakePlanRepositoryProvider.overrideWith((ref) async => repository),
        appNativeAlarmGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    final service = await container.read(wakePlanServiceProvider.future);

    expect(
      await container.read(appWakePlanServiceProvider.future),
      same(service),
    );
    expect(
      await container.read(weekCalendarWakePlanServiceProvider.future),
      same(service),
    );
  });

  test('coordinator is stable within and isolated between sessions', () {
    final first = ProviderContainer();
    final second = ProviderContainer();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    final firstCoordinator = first.read(wakePlanMutationCoordinatorProvider);

    expect(
      first.read(wakePlanMutationCoordinatorProvider),
      same(firstCoordinator),
    );
    expect(
      second.read(wakePlanMutationCoordinatorProvider),
      isNot(same(firstCoordinator)),
    );
  });
}
