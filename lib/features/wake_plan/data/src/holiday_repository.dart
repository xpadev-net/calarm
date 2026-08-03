import 'dart:async';

import '../../../../core/time/time.dart';
import '../../domain/wake_plan_domain.dart';
import 'holiday_ics_parser.dart';
import 'wake_plan_database.dart';

typedef HolidayIcsFetcher = Future<String> Function(Uri uri);

const Duration defaultHolidayStaleAfter = Duration(days: 7);

Uri holidayIcsUriFor(HolidayRegion region) {
  return Uri.parse(
    'https://raw.githubusercontent.com/xpadev-net/holidays-ical/main/'
    'holidays/${region.code}.ics',
  );
}

/// Fetches, parses, and caches holiday calendars for a [HolidayRegion].
///
/// Network/parse failures are recorded but never rethrown from
/// [holidaysFor] — alarms must never be affected by a data-fetch failure,
/// so this repository always fails open (an empty/last-known-good set).
class HolidayRepository {
  HolidayRepository({
    required WakePlanDatabase database,
    required HolidayIcsFetcher fetchIcs,
    Duration staleAfter = defaultHolidayStaleAfter,
    DateTime Function() now = DateTime.now,
  }) : _database = database,
       _fetchIcs = fetchIcs,
       _staleAfter = staleAfter,
       _now = now;

  final WakePlanDatabase _database;
  final HolidayIcsFetcher _fetchIcs;
  final Duration _staleAfter;
  final DateTime Function() _now;

  Future<Set<CalendarDay>> holidaysFor(HolidayRegion region) async {
    unawaited(refreshIfStale(region));
    return _cachedDays(region);
  }

  Future<Set<CalendarDay>> _cachedDays(HolidayRegion region) async {
    final rows = await (_database.select(
      _database.holidayCacheRows,
    )..where((row) => row.region.equals(region.code))).get();
    final epoch = CalendarDay.fromDateTime(DateTime.utc(1970, 1, 1));
    return rows.map((row) => epoch.addDays(row.dateDays)).toSet();
  }

  Future<void> refreshIfStale(HolidayRegion region) async {
    final metadata = await (_database.select(
      _database.holidayFetchMetadataRows,
    )..where((row) => row.region.equals(region.code))).getSingleOrNull();

    final lastSuccessAt = metadata?.lastSuccessAt;
    final isStale =
        lastSuccessAt == null || _now().difference(lastSuccessAt) > _staleAfter;
    if (!isStale) {
      return;
    }

    await refresh(region);
  }

  Future<void> refresh(HolidayRegion region) async {
    final fetchedAt = _now();
    try {
      final icsContent = await _fetchIcs(holidayIcsUriFor(region));
      final holidays = parseHolidayIcs(icsContent);
      await _replaceCachedHolidays(region, holidays);
      await _writeFetchMetadata(
        region,
        lastFetchedAt: fetchedAt,
        lastSuccessAt: fetchedAt,
        lastError: null,
      );
    } catch (error) {
      await _recordFetchFailure(region, fetchedAt: fetchedAt, error: error);
    }
  }

  Future<void> _replaceCachedHolidays(
    HolidayRegion region,
    List<Holiday> holidays,
  ) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.holidayCacheRows,
      )..where((row) => row.region.equals(region.code))).go();
      await _database.batch((batch) {
        batch.insertAll(
          _database.holidayCacheRows,
          holidays.map(
            (holiday) => HolidayCacheRow(
              region: region.code,
              dateDays: holiday.date.daysSinceUnixEpoch,
              name: holiday.name,
            ),
          ),
        );
      });
    });
  }

  Future<void> _recordFetchFailure(
    HolidayRegion region, {
    required DateTime fetchedAt,
    required Object error,
  }) async {
    final existing = await (_database.select(
      _database.holidayFetchMetadataRows,
    )..where((row) => row.region.equals(region.code))).getSingleOrNull();

    await _writeFetchMetadata(
      region,
      lastFetchedAt: fetchedAt,
      lastSuccessAt: existing?.lastSuccessAt,
      lastError: error.toString(),
    );
  }

  Future<void> _writeFetchMetadata(
    HolidayRegion region, {
    required DateTime lastFetchedAt,
    required DateTime? lastSuccessAt,
    required String? lastError,
  }) async {
    await _database
        .into(_database.holidayFetchMetadataRows)
        .insertOnConflictUpdate(
          HolidayFetchMetadataRow(
            region: region.code,
            lastFetchedAt: lastFetchedAt,
            lastSuccessAt: lastSuccessAt,
            lastError: lastError,
          ),
        );
  }
}
