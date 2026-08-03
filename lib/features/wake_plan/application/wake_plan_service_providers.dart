import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/app_bootstrap.dart';
import '../data/wake_plan_data.dart';
import 'holiday_set_provider.dart';
import 'wake_plan_service.dart';

final wakePlanClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

final wakePlanMutationCoordinatorProvider =
    Provider<WakePlanMutationCoordinator>((ref) {
      return WakePlanMutationCoordinator();
    });

final wakePlanServiceProvider = FutureProvider<WakePlanService>((ref) async {
  return WakePlanService(
    repository: await ref.watch(appWakePlanRepositoryProvider.future),
    nativeAlarmGateway: ref.watch(appNativeAlarmGatewayProvider),
    clock: ref.watch(wakePlanClockProvider),
    // Read (not watch): resolves the current holiday set fresh on every
    // scheduling operation without making wakePlanServiceProvider itself
    // rebuild (and discard in-flight service state) whenever the holiday
    // set changes in the background.
    holidaysSnapshot: () =>
        ref.read(activeHolidaySetProvider).value ?? const {},
    coordinator: ref.watch(wakePlanMutationCoordinatorProvider),
  );
});
