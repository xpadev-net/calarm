import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/identity/app_identity.dart';
import 'features/alarm_ringing/presentation/alarm_ringing_placeholder.dart';
import 'features/settings/presentation/settings_placeholder.dart';
import 'features/settings/application/alarm_health_controller.dart';
import 'features/settings/presentation/alarm_permission_gate.dart';
import 'features/wake_plan/application/wake_plan_service_providers.dart';
import 'features/wake_plan/presentation/wake_plan_placeholder.dart';
import 'features/week_calendar/presentation/week_calendar_placeholder.dart';

const _homeSectionGap = 8.0;
const _homeToolsButtonKey = ValueKey<String>('home-tools-button');
const _homeSectionsScrollKey = ValueKey<String>('home-sections-scroll');
const _homeToolsTooltip = 'Open alarm and settings';

final appWakePlanServiceProvider = wakePlanServiceProvider;

class CalarmApp extends ConsumerStatefulWidget {
  const CalarmApp({super.key});

  @override
  ConsumerState<CalarmApp> createState() => _CalarmAppState();
}

class _CalarmAppState extends ConsumerState<CalarmApp>
    with WidgetsBindingObserver {
  var _disposed = false;
  var _lastQueuedCapabilityRevision = 0;
  Future<void> _reconciliationTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      unawaited(ref.read(alarmHealthProvider.notifier).refresh());
    }
  }

  void _queueReconciliation(AlarmHealthState health) {
    if (_disposed ||
        health.readinessStatus != AlarmReadinessStatus.ready ||
        health.capabilityRevision <= _lastQueuedCapabilityRevision) {
      return;
    }
    _lastQueuedCapabilityRevision = health.capabilityRevision;
    _reconciliationTail = _reconciliationTail.then((_) => _runReconciliation());
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
    final alarmHealth = ref.watch(alarmHealthProvider);
    final health = alarmHealth.value;
    if (health != null) {
      _queueReconciliation(health);
    }

    return MaterialApp(
      title: identity.displayName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home:
          health?.readinessStatus == AlarmReadinessStatus.ready &&
              !alarmHealth.hasError
          ? const CalarmHomePage()
          : AlarmPermissionGate(
              state: alarmHealth.hasError ? null : health,
              onRequestPermission: () =>
                  ref.read(alarmHealthProvider.notifier).requestPermission(),
              onRetry: () => ref.read(alarmHealthProvider.notifier).refresh(),
            ),
    );
  }
}

class CalarmHomePage extends StatelessWidget {
  const CalarmHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return IconButton(
              key: _homeToolsButtonKey,
              tooltip: _homeToolsTooltip,
              icon: const Icon(Icons.tune),
              onPressed: Scaffold.of(context).openDrawer,
            );
          },
        ),
        title: const Text(AppIdentity.defaultDisplayName),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: SingleChildScrollView(
            key: _homeSectionsScrollKey,
            padding: const EdgeInsets.all(12),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AlarmRingingPlaceholder(),
                SizedBox(height: _homeSectionGap),
                SettingsPlaceholder(),
                SizedBox(height: _homeSectionGap),
                WakePlanPlaceholder(),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: const WeekCalendarPlaceholder(),
        ),
      ),
    );
  }
}
