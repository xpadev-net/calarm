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
      final regions = settings.holidayRegions;
      if (regions.isEmpty) {
        return;
      }
      final repository = await ref.read(holidayRepositoryProvider.future);
      await Future.wait(regions.map(repository.refreshIfStale));
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

class CalarmHomePage extends StatefulWidget {
  const CalarmHomePage({super.key});

  @override
  State<CalarmHomePage> createState() => _CalarmHomePageState();
}

class _CalarmHomePageState extends State<CalarmHomePage> {
  int _visibleDays = 1;
  bool _draftActive = false;

  void _setVisibleDays(int visibleDays) {
    if (_visibleDays == visibleDays) {
      return;
    }
    setState(() {
      _visibleDays = visibleDays;
    });
  }

  void _setDraftActive(bool draftActive) {
    if (_draftActive == draftActive) {
      return;
    }
    setState(() {
      _draftActive = draftActive;
    });
  }

  @override
  Widget build(BuildContext context) {
    final systemBottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 4,
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
        title: Text(
          AppIdentity.defaultDisplayName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _CalendarViewToggle(
              visibleDays: _visibleDays,
              enabled: !_draftActive,
              onVisibleDaysChanged: _setVisibleDays,
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: SingleChildScrollView(
            key: _homeSectionsScrollKey,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CalendarViewSection(
                  visibleDays: _visibleDays,
                  enabled: !_draftActive,
                  onVisibleDaysChanged: _setVisibleDays,
                ),
                const SizedBox(height: _homeSectionGap),
                const AlarmRingingPlaceholder(),
                const SizedBox(height: _homeSectionGap),
                const SettingsPlaceholder(),
                const SizedBox(height: _homeSectionGap),
                const WakePlanPlaceholder(),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: WeekCalendarPlaceholder(
            visibleDays: _visibleDays,
            onDraftActiveChanged: _setDraftActive,
            bottomPadding: systemBottomInset,
          ),
        ),
      ),
    );
  }
}

const _calendarViewToggleKey = ValueKey<String>('calendar-view-toggle');

class _CalendarViewToggle extends StatelessWidget {
  const _CalendarViewToggle({
    required this.visibleDays,
    required this.enabled,
    required this.onVisibleDaysChanged,
  });

  final int visibleDays;
  final bool enabled;
  final ValueChanged<int> onVisibleDaysChanged;

  static const _options = [
    (value: 1, label: '1D'),
    (value: 3, label: '3D'),
    (value: DateTime.daysPerWeek, label: '7D'),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SegmentedButton<int>(
      key: _calendarViewToggleKey,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        selectedBackgroundColor: colorScheme.secondaryContainer,
        selectedForegroundColor: colorScheme.onSecondaryContainer,
      ),
      showSelectedIcon: false,
      segments: [
        for (final option in _options)
          ButtonSegment<int>(
            value: option.value,
            label: Text(option.label),
          ),
      ],
      selected: {visibleDays},
      onSelectionChanged: (selection) {
        final selectedValue = selection.first;
        if (selectedValue == visibleDays) {
          return;
        }
        if (!enabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Finish or cancel the current draft before switching views',
              ),
            ),
          );
          return;
        }
        onVisibleDaysChanged(selectedValue);
      },
    );
  }
}

const _calendarViewSectionKey = ValueKey<String>('calendar-view-section');

class _CalendarViewSection extends StatelessWidget {
  const _CalendarViewSection({
    required this.visibleDays,
    required this.enabled,
    required this.onVisibleDaysChanged,
  });

  final int visibleDays;
  final bool enabled;
  final ValueChanged<int> onVisibleDaysChanged;

  static const _options = [
    (value: 1, label: '1 day', icon: Icons.view_day_outlined),
    (value: 3, label: '3 days', icon: Icons.view_column_outlined),
    (
      value: DateTime.daysPerWeek,
      label: '7 days',
      icon: Icons.view_week_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      key: _calendarViewSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in _options)
          _CalendarViewOptionTile(
            key: ValueKey('calendar-view-option-${option.value}'),
            label: option.label,
            icon: option.icon,
            selected: visibleDays == option.value,
            onTap: () {
              if (!enabled) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Finish or cancel the current draft before '
                      'switching views',
                    ),
                  ),
                );
                return;
              }
              onVisibleDaysChanged(option.value);
            },
          ),
      ],
    );
  }
}

class _CalendarViewOptionTile extends StatelessWidget {
  const _CalendarViewOptionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 24),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: selected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
