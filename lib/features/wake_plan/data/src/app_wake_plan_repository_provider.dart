import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/bootstrap/app_bootstrap.dart';
import '../../../../core/persistence/open_app_database.dart';
import 'wake_plan_database.dart';
import 'wake_plan_repository.dart';

final appWakePlanDatabaseProvider = FutureProvider<WakePlanDatabase>((
  ref,
) async {
  final config = ref.watch(appDatabaseConfigProvider);
  final database = WakePlanDatabase(await openAppDatabase(config.name));
  ref.onDispose(database.close);
  return database;
});

final appWakePlanRepositoryProvider = FutureProvider<WakePlanRepository>((
  ref,
) async {
  final database = await ref.watch(appWakePlanDatabaseProvider.future);
  return WakePlanRepository(database);
});
