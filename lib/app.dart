import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/identity/app_identity.dart';
import 'core/time/time.dart';
import 'features/alarm_ringing/presentation/alarm_ringing_placeholder.dart';
import 'features/settings/presentation/settings_placeholder.dart';
import 'features/settings/application/alarm_health_controller.dart';
import 'features/settings/presentation/alarm_permission_gate.dart';
import 'features/settings/application/wake_plan_defaults_controller.dart';
import 'features/wake_plan/application/holiday_set_provider.dart';
import 'features/wake_plan/application/wake_plan_service_providers.dart';
import 'features/wake_plan/data/wake_plan_data.dart';
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
  static const _holidayReconciliationRetryDelay = Duration(seconds: 30);

  var _disposed = false;
  var _lastQueuedCapabilityRevision = 0;
  Set<CalendarDay>? _lastReconciledHolidays;
  Future<void> _reconciliationTail = Future<void>.value();
  Timer? _holidayReconciliationRetryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _disposed = true;
    _holidayReconciliationRetryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(alarmHealthProvider.notifier).refresh());
      unawaited(_refreshHolidaysIfStale());
    }
  }

  /// The holiday cache is otherwise only checked for staleness once, when
  /// activeHolidaySetProvider first subscribes — an app session kept alive
  /// (foregrounded) for longer than the stale threshold would never
  /// re-check it. Resume is a reasonably-timed hook to also cover that.
  Future<void> _refreshHolidaysIfStale() async {
    try {
      final settings = await ref.read(wakePlanDefaultsProvider.future);
      final region = settings.holidayRegion;
      if (region == null) {
        return;
      }
      final repository = await ref.read(holidayRepositoryProvider.future);
      await repository.refreshIfStale(region);
    } catch (_) {
      // Fail open: a holiday refresh failure must never disrupt resume.
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

  /// Reconciliation only ever reads the *current* holiday set when it
  /// builds a plan's occurrence bundle — nothing else re-derives scheduled
  /// native alarms once holiday data changes. Without this, an alarm
  /// created (or already scheduled) before a background holiday refresh
  /// completes could keep firing on a day that's since been confirmed a
  /// holiday, for as long as the app session runs without some other event
  /// (a capability change, an edit) happening to trigger reconciliation.
  void _queueReconciliationForHolidayChange(
    AlarmHealthState health,
    Set<CalendarDay> holidays,
  ) {
    if (_disposed ||
        health.readinessStatus != AlarmReadinessStatus.ready ||
        _setEquals(_lastReconciledHolidays, holidays)) {
      return;
    }
    _holidayReconciliationRetryTimer?.cancel();
    // Only commit the marker once reconciliation actually succeeds — if it
    // fails, `_lastReconciledHolidays` stays at its previous value, so an
    // unchanged (but still-not-reconciled) `holidays` set is retried on the
    // next build instead of being silently treated as already handled.
    _reconciliationTail = _reconciliationTail.then((_) async {
      final succeeded = await _runReconciliation();
      if (_disposed) {
        return;
      }
      if (succeeded) {
        _lastReconciledHolidays = holidays;
      } else {
        // Nothing else guarantees another rebuild will happen soon (the
        // holiday stream may have already gone quiet at this exact set) —
        // schedule a bounded retry ourselves rather than leaving alarms
        // scheduled through a holiday until some unrelated event happens
        // to trigger reconciliation again.
        _holidayReconciliationRetryTimer = Timer(
          _holidayReconciliationRetryDelay,
          () => _queueReconciliationForHolidayChange(health, holidays),
        );
      }
    });
  }

  Future<bool> _runReconciliation() async {
    if (_disposed) {
      return false;
    }
    try {
      final service = await ref.read(appWakePlanServiceProvider.future);
      if (_disposed) {
        return false;
      }
      await service.reconcileSchedules();
      return true;
    } catch (error) {
      if (!_disposed) {
        debugPrint('Could not reconcile wake plans: $error');
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(appIdentityProvider);
    final alarmHealth = ref.watch(alarmHealthProvider);
    final holidays = ref.watch(activeHolidaySetProvider);
    final health = alarmHealth.value;
    if (health != null) {
      _queueReconciliation(health);
      final holidaySet = holidays.value;
      if (holidaySet != null) {
        _queueReconciliationForHolidayChange(health, holidaySet);
      }
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

bool _setEquals(Set<CalendarDay>? a, Set<CalendarDay> b) {
  if (a == null) {
    return false;
  }
  return a.length == b.length && a.containsAll(b);
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
