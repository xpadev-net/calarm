import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../identity/app_identity.dart';
import '../persistence/app_database.dart';

final appIdentityProvider = Provider<AppIdentity>((ref) => AppIdentity.current);

final appDatabaseConfigProvider = Provider<AppDatabaseConfig>(
  (ref) => const AppDatabaseConfig(name: 'calarm.sqlite'),
);
