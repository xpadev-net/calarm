import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/bootstrap/app_bootstrap.dart';
import '../../wake_plan/data/wake_plan_data.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';

final wakePlanDefaultsRepositoryProvider = FutureProvider<WakePlanRepository>((
  ref,
) async {
  final config = ref.watch(appDatabaseConfigProvider);
  final database = WakePlanDatabase(await _openSettingsDatabase(config.name));
  ref.onDispose(database.close);

  return WakePlanRepository(database);
});

final wakePlanDefaultsProvider =
    AsyncNotifierProvider<WakePlanDefaultsController, AppSettings>(
      WakePlanDefaultsController.new,
    );

class WakePlanDefaultsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final repository = await ref.watch(
      wakePlanDefaultsRepositoryProvider.future,
    );
    return repository.fetchEffectiveAppSettings();
  }

  Future<void> setWakeWindow(Duration value) {
    final current = _current;
    return _saveSanitized(defaultStartOffset: value, current: current);
  }

  Future<void> setInterval(Duration value) {
    final current = _current;
    return _saveSanitized(defaultInterval: value, current: current);
  }

  Future<void> setSoundId(String value) {
    final current = _current;
    return _saveSanitized(defaultSoundId: value, current: current);
  }

  Future<void> setVibrationEnabled(bool value) {
    return _save(_current.copyWith(defaultVibrationEnabled: value));
  }

  Future<void> setRepeatType(RepeatType value) {
    return _save(_current.copyWith(defaultRepeatType: value));
  }

  AppSettings get _current => state.value ?? AppSettings.initial();

  Future<void> _saveSanitized({
    required AppSettings current,
    Duration? defaultStartOffset,
    Duration? defaultInterval,
    String? defaultSoundId,
  }) {
    return _save(
      sanitizeAppSettings(
        defaultStartOffset: defaultStartOffset ?? current.defaultStartOffset,
        defaultInterval: defaultInterval ?? current.defaultInterval,
        defaultSoundId: defaultSoundId ?? current.defaultSoundId,
        defaultVibrationEnabled: current.defaultVibrationEnabled,
        defaultRepeatType: current.defaultRepeatType,
        defaultTargetTime: current.defaultTargetTime,
      ),
    );
  }

  Future<void> _save(AppSettings settings) async {
    final next = sanitizeAppSettings(
      defaultStartOffset: settings.defaultStartOffset,
      defaultInterval: settings.defaultInterval,
      defaultSoundId: settings.defaultSoundId,
      defaultVibrationEnabled: settings.defaultVibrationEnabled,
      defaultRepeatType: settings.defaultRepeatType,
      defaultTargetTime: settings.defaultTargetTime,
    );
    state = AsyncData(next);

    final repository = await ref.read(
      wakePlanDefaultsRepositoryProvider.future,
    );
    await repository.saveAppSettings(next);
  }
}

Future<QueryExecutor> _openSettingsDatabase(String name) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(
      File(p.join(directory.path, name)),
    );
  } on MissingPluginException {
    return NativeDatabase.memory();
  }
}
