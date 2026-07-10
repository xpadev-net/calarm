import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/method_channel_native_alarm_gateway.dart';
import '../platform/native_alarm_gateway.dart';
import '../identity/app_identity.dart';
import '../persistence/app_database.dart';

final appIdentityProvider = Provider<AppIdentity>((ref) => AppIdentity.current);

final appDatabaseConfigProvider = Provider<AppDatabaseConfig>(
  (ref) => const AppDatabaseConfig(name: 'calarm.sqlite'),
);

final appNativeAlarmGatewayProvider = Provider<NativeAlarmGateway>((ref) {
  return MethodChannelNativeAlarmGateway();
});
