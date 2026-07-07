import 'package:calarm/features/settings/application/wake_plan_defaults_controller.dart';
import 'package:calarm/features/settings/presentation/settings_placeholder.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WakePlanDatabase database;
  late WakePlanRepository repository;

  setUp(() {
    database = WakePlanDatabase(NativeDatabase.memory());
    repository = WakePlanRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('renders and persists settings default controls', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wakePlanDefaultsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPlaceholder())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wake window'), findsOneWidget);
    expect(find.text('1 h'), findsOneWidget);
    expect(find.text('Interval'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('OS default'), findsOneWidget);
    expect(find.text('No repeat'), findsOneWidget);

    await tester.tap(find.text('Weekday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vibration'));
    await tester.pumpAndSettle();

    final saved = await repository.fetchEffectiveAppSettings();

    expect(saved.defaultRepeatType, RepeatType.weekly);
    expect(saved.defaultVibrationEnabled, isFalse);
  });
}
