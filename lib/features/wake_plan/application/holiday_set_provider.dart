import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../settings/application/wake_plan_defaults_controller.dart';
import '../data/wake_plan_data.dart';
import '../domain/wake_plan_domain.dart';

/// The current set of holiday dates for the app-wide configured regions
/// (unioned across all of them), or an empty set if no region is
/// configured. Fails open (empty set) while loading or on any upstream
/// error, since alarm scheduling must never be blocked by holiday-data
/// availability.
///
/// Backed by Drift reactive queries (not one-shot fetches): once a
/// background refresh (triggered on first read) finishes populating the
/// cache, this provider re-emits the updated union automatically instead of
/// staying frozen at whatever was cached at the moment it first resolved.
final activeHolidaySetProvider = StreamProvider<Set<CalendarDay>>((ref) async* {
  final settings = await ref.watch(wakePlanDefaultsProvider.future);
  final regions = settings.holidayRegions;
  if (regions.isEmpty) {
    yield const {};
    return;
  }

  final repository = await ref.watch(holidayRepositoryProvider.future);
  yield* _unionHolidays(repository, regions);
});

/// Combines each region's independently-updating holiday stream into a
/// single stream of the union, re-emitting whenever any one region's set
/// changes. Written by hand (rather than pulling in a combine-latest
/// package) since this is the only place that needs it.
Stream<Set<CalendarDay>> _unionHolidays(
  HolidayRepository repository,
  Set<HolidayRegion> regions,
) {
  late final StreamController<Set<CalendarDay>> controller;
  final latestByRegion = <HolidayRegion, Set<CalendarDay>>{};
  final subscriptions = <StreamSubscription<Set<CalendarDay>>>[];

  void emitUnion() {
    if (latestByRegion.length != regions.length) {
      return;
    }
    controller.add(latestByRegion.values.expand((days) => days).toSet());
  }

  controller = StreamController<Set<CalendarDay>>(
    onListen: () {
      for (final region in regions) {
        subscriptions.add(
          repository.watchHolidays(region).listen((days) {
            latestByRegion[region] = days;
            emitUnion();
          }, onError: (Object _, StackTrace _) {}),
        );
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}
