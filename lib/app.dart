import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/identity/app_identity.dart';
import 'features/alarm_ringing/presentation/alarm_ringing_placeholder.dart';
import 'features/settings/presentation/settings_placeholder.dart';
import 'features/wake_plan/presentation/wake_plan_placeholder.dart';
import 'features/week_calendar/presentation/week_calendar_placeholder.dart';

const _homeSectionGap = 8.0;
const _calendarErrorMinHeight = 180.0;

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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight - _homeSectionGap;
              final preferredCalendarHeight = availableHeight * 2 / 3;
              final calendarHeight =
                  preferredCalendarHeight < _calendarErrorMinHeight
                  ? _calendarErrorMinHeight
                  : preferredCalendarHeight;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: calendarHeight,
                    child: const WeekCalendarPlaceholder(),
                  ),
                  const SizedBox(height: _homeSectionGap),
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey<String>('home-sections-scroll'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AlarmRingingPlaceholder(),
                          const SizedBox(height: _homeSectionGap),
                          const SettingsPlaceholder(),
                          const SizedBox(height: _homeSectionGap),
                          const WakePlanPlaceholder(),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
