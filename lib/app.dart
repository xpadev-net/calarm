import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/identity/app_identity.dart';
import 'features/alarm_ringing/presentation/alarm_ringing_placeholder.dart';
import 'features/settings/presentation/settings_placeholder.dart';
import 'features/wake_plan/application/wake_plan_service.dart';
import 'features/wake_plan/data/src/app_wake_plan_repository_provider.dart';
import 'features/wake_plan/presentation/wake_plan_placeholder.dart';
import 'features/week_calendar/presentation/week_calendar_placeholder.dart';

const _homeSectionGap = 8.0;
const _calendarErrorMinHeight = 180.0;

final appWakePlanServiceProvider = FutureProvider<WakePlanService>((ref) async {
  return WakePlanService(
    repository: await ref.watch(appWakePlanRepositoryProvider.future),
    nativeAlarmGateway: ref.watch(appNativeAlarmGatewayProvider),
  );
});

class CalarmApp extends ConsumerStatefulWidget {
  const CalarmApp({super.key});

  @override
  ConsumerState<CalarmApp> createState() => _CalarmAppState();
}

class _CalarmAppState extends ConsumerState<CalarmApp>
    with WidgetsBindingObserver {
  var _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reconcileWakePlans();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileWakePlans();
    }
  }

  void _reconcileWakePlans() {
    if (_disposed) {
      return;
    }
    unawaited(_runReconciliation());
  }

  Future<void> _runReconciliation() async {
    if (_disposed) {
      return;
    }
    try {
      final service = await ref.read(appWakePlanServiceProvider.future);
      if (_disposed) {
        return;
      }
      await service.reconcileSchedules();
    } catch (error) {
      if (!_disposed) {
        debugPrint('Could not reconcile wake plans: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
