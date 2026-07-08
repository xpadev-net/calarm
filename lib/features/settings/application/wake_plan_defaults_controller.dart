import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wake_plan/data/wake_plan_data.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';

final wakePlanDefaultsRepositoryProvider = FutureProvider<WakePlanRepository>((
  ref,
) async {
  return ref.watch(appWakePlanRepositoryProvider.future);
});

final wakePlanDefaultsProvider =
    AsyncNotifierProvider<WakePlanDefaultsController, AppSettings>(
      WakePlanDefaultsController.new,
    );

class WakePlanDefaultsController extends AsyncNotifier<AppSettings> {
  Future<void> _pendingSave = Future.value();

  @override
  Future<AppSettings> build() async {
    final repository = await ref.watch(
      wakePlanDefaultsRepositoryProvider.future,
    );
    return repository.fetchEffectiveAppSettings();
  }

  Future<void> setWakeWindow(Duration value) {
    return _enqueueSave(
      (current) => sanitizeAppSettings(
        defaultStartOffset: value,
        defaultInterval: current.defaultInterval,
        defaultSoundId: current.defaultSoundId,
        defaultVibrationEnabled: current.defaultVibrationEnabled,
        defaultRepeatType: current.defaultRepeatType,
        defaultTargetTime: current.defaultTargetTime,
      ),
    );
  }

  Future<void> setInterval(Duration value) {
    return _enqueueSave(
      (current) => sanitizeAppSettings(
        defaultStartOffset: current.defaultStartOffset,
        defaultInterval: value,
        defaultSoundId: current.defaultSoundId,
        defaultVibrationEnabled: current.defaultVibrationEnabled,
        defaultRepeatType: current.defaultRepeatType,
        defaultTargetTime: current.defaultTargetTime,
      ),
    );
  }

  Future<void> setSoundId(String value) {
    return _enqueueSave(
      (current) => sanitizeAppSettings(
        defaultStartOffset: current.defaultStartOffset,
        defaultInterval: current.defaultInterval,
        defaultSoundId: value,
        defaultVibrationEnabled: current.defaultVibrationEnabled,
        defaultRepeatType: current.defaultRepeatType,
        defaultTargetTime: current.defaultTargetTime,
      ),
    );
  }

  Future<void> setVibrationEnabled(bool value) {
    return _enqueueSave(
      (current) => current.copyWith(defaultVibrationEnabled: value),
    );
  }

  Future<void> setRepeatType(RepeatType value) {
    return _enqueueSave(
      (current) => current.copyWith(defaultRepeatType: value),
    );
  }

  AppSettings get _current => state.value ?? AppSettings.initial();

  Future<void> _enqueueSave(AppSettings Function(AppSettings current) update) {
    final operation = _pendingSave.then((_) => _save(update(_current)));
    _pendingSave = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _save(AppSettings settings) async {
    final previous = state;
    final next = sanitizeAppSettings(
      defaultStartOffset: settings.defaultStartOffset,
      defaultInterval: settings.defaultInterval,
      defaultSoundId: settings.defaultSoundId,
      defaultVibrationEnabled: settings.defaultVibrationEnabled,
      defaultRepeatType: settings.defaultRepeatType,
      defaultTargetTime: settings.defaultTargetTime,
    );

    final repository = await ref.read(
      wakePlanDefaultsRepositoryProvider.future,
    );
    try {
      await repository.saveAppSettings(next);
      state = AsyncData(next);
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
