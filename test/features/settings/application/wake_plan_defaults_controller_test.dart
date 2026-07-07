import 'package:calarm/features/settings/application/wake_plan_defaults_controller.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WakePlanDatabase database;
  late WakePlanRepository repository;
  late ProviderContainer container;

  setUp(() {
    database = WakePlanDatabase(NativeDatabase.memory());
    repository = WakePlanRepository(database);
    container = ProviderContainer(
      overrides: [
        wakePlanDefaultsRepositoryProvider.overrideWith(
          (ref) async => repository,
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('loads initial defaults when nothing has been saved', () async {
    final settings = await container.read(wakePlanDefaultsProvider.future);

    expect(settings.defaultStartOffset, const Duration(minutes: 60));
    expect(settings.defaultInterval, const Duration(minutes: 5));
    expect(settings.defaultRepeatType, RepeatType.oneTime);
  });

  test('persists default changes through the wake plan repository', () async {
    await container.read(wakePlanDefaultsProvider.future);

    await container
        .read(wakePlanDefaultsProvider.notifier)
        .setWakeWindow(const Duration(minutes: 90));
    await container
        .read(wakePlanDefaultsProvider.notifier)
        .setInterval(const Duration(minutes: 10));
    await container
        .read(wakePlanDefaultsProvider.notifier)
        .setVibrationEnabled(false);
    await container
        .read(wakePlanDefaultsProvider.notifier)
        .setRepeatType(RepeatType.weekly);

    final saved = await repository.fetchEffectiveAppSettings();

    expect(saved.defaultStartOffset, const Duration(minutes: 90));
    expect(saved.defaultInterval, const Duration(minutes: 10));
    expect(saved.defaultVibrationEnabled, isFalse);
    expect(saved.defaultRepeatType, RepeatType.weekly);
    expect(saved.defaultSoundId, defaultWakePlanSoundId);
  });

  test('serializes concurrent default changes against latest state', () async {
    await container.read(wakePlanDefaultsProvider.future);
    final controller = container.read(wakePlanDefaultsProvider.notifier);

    await Future.wait([
      controller.setWakeWindow(const Duration(minutes: 90)),
      controller.setInterval(const Duration(minutes: 10)),
      controller.setVibrationEnabled(false),
      controller.setRepeatType(RepeatType.weekly),
    ]);

    final saved = await repository.fetchEffectiveAppSettings();

    expect(saved.defaultStartOffset, const Duration(minutes: 90));
    expect(saved.defaultInterval, const Duration(minutes: 10));
    expect(saved.defaultVibrationEnabled, isFalse);
    expect(saved.defaultRepeatType, RepeatType.weekly);
  });

  test('restores previous state when persistence fails', () async {
    final initial = await container.read(wakePlanDefaultsProvider.future);

    await database.close();

    await expectLater(
      container
          .read(wakePlanDefaultsProvider.notifier)
          .setWakeWindow(const Duration(minutes: 90)),
      throwsA(anything),
    );

    expect(
      container.read(wakePlanDefaultsProvider).value!.defaultStartOffset,
      initial.defaultStartOffset,
    );

    database = WakePlanDatabase(NativeDatabase.memory());
  });

  test('sanitizes attempted invalid updates before persistence', () async {
    await container.read(wakePlanDefaultsProvider.future);

    await container
        .read(wakePlanDefaultsProvider.notifier)
        .setWakeWindow(const Duration(hours: 12));

    final saved = await repository.fetchEffectiveAppSettings();

    expect(saved.defaultStartOffset, maximumWakePlanStartOffset);
  });
}
