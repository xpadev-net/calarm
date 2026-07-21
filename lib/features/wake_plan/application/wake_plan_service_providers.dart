import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/app_bootstrap.dart';
import '../data/wake_plan_data.dart';
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
    coordinator: ref.watch(wakePlanMutationCoordinatorProvider),
  );
});
