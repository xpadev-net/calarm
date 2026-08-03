import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../settings/application/wake_plan_defaults_controller.dart';
import '../data/wake_plan_data.dart';

/// The current set of holiday dates for the app-wide configured region, or
/// an empty set if no region is configured. Fails open (empty set) while
/// loading or on any upstream error, since alarm scheduling must never be
/// blocked by holiday-data availability.
///
/// Backed by a Drift reactive query (not a one-shot fetch): once a
/// background refresh (triggered on first read) finishes populating the
/// cache, this provider re-emits the updated set automatically instead of
/// staying frozen at whatever was cached at the moment it first resolved.
final activeHolidaySetProvider = StreamProvider<Set<CalendarDay>>((ref) async* {
  final settings = await ref.watch(wakePlanDefaultsProvider.future);
  final region = settings.holidayRegion;
  if (region == null) {
    yield const {};
    return;
  }

  final repository = await ref.watch(holidayRepositoryProvider.future);
  yield* repository.watchHolidays(region);
});
