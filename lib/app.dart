import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/identity/app_identity.dart';
import 'features/alarm_ringing/presentation/alarm_ringing_placeholder.dart';
import 'features/settings/presentation/settings_placeholder.dart';
import 'features/wake_plan/presentation/wake_plan_placeholder.dart';
import 'features/week_calendar/presentation/week_calendar_placeholder.dart';

class CalarmApp extends ConsumerWidget {
  const CalarmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(appIdentityProvider);

    return MaterialApp(
      title: identity.displayName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const CalarmHomePage(),
    );
  }
}

class CalarmHomePage extends StatelessWidget {
  const CalarmHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppIdentity.defaultDisplayName)),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WakePlanPlaceholder(),
              SizedBox(height: 12),
              WeekCalendarPlaceholder(),
              SizedBox(height: 12),
              AlarmRingingPlaceholder(),
              SizedBox(height: 12),
              SettingsPlaceholder(),
            ],
          ),
        ),
      ),
    );
  }
}
