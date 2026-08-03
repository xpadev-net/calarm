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
    required this._database,
    required this._fetchIcs,
    this._staleAfter = defaultHolidayStaleAfter,
    this._now = DateTime.now,
  });

  final WakePlanDatabase _database;
  final HolidayIcsFetcher _fetchIcs;
  final Duration _staleAfter;
  final DateTime Function() _now;

  Future<Set<CalendarDay>> holidaysFor(HolidayRegion region) async {
    unawaited(refreshIfStale(region));
    try {
      return await _cachedDays(region);
    } catch (_) {
      return const {};
    }
  }

  /// Like [holidaysFor], but keeps emitting as the cache is updated —
  /// including once a background [refreshIfStale] triggered by this same
  /// call completes. Plain one-shot reads of [holidaysFor] would otherwise
  /// never observe data that only became available *after* the read.
  Stream<Set<CalendarDay>> watchHolidays(HolidayRegion region) {
    unawaited(refreshIfStale(region));
    // Swallow (rather than propagate) query errors on this long-lived
    // subscription: fail open by keeping whatever was last emitted instead
    // of tearing the stream down over a transient error.
    return (_database.select(_database.holidayCacheRows)
          ..where((row) => row.region.equals(region.code)))
        .watch()
        .map(_toCalendarDays)
        .handleError((Object _, StackTrace _) {});
  }

  Future<Set<CalendarDay>> _cachedDays(HolidayRegion region) async {
    final rows = await (_database.select(
      _database.holidayCacheRows,
    )..where((row) => row.region.equals(region.code))).get();
    return _toCalendarDays(rows);
  }

  Set<CalendarDay> _toCalendarDays(List<HolidayCacheRow> rows) {
    final epoch = CalendarDay.fromDateTime(DateTime.utc(1970, 1, 1));
    return rows.map((row) => epoch.addDays(row.dateDays)).toSet();
  }

  Future<void> refreshIfStale(HolidayRegion region) async {
    try {
      final metadata = await (_database.select(
        _database.holidayFetchMetadataRows,
      )..where((row) => row.region.equals(region.code))).getSingleOrNull();

      final lastSuccessAt = metadata?.lastSuccessAt;
      final isStale =
          lastSuccessAt == null ||
          _now().difference(lastSuccessAt) > _staleAfter;
      if (!isStale) {
        return;
      }

      await refresh(region);
    } catch (_) {
      // Fail open: a DB-layer error here must not surface as an unhandled
      // async error (this is invoked via `unawaited` from holidaysFor) or
      // block scheduling — a future call will simply retry.
    }
  }

  Future<void> refresh(HolidayRegion region) async {
    final fetchedAt = _now();
    try {
      final icsContent = await _fetchIcs(holidayIcsUriFor(region));
      final holidays = parseHolidayIcs(icsContent);
      if (holidays.isEmpty) {
        // A syntactically valid but event-free response is virtually always
        // a transient/degraded fetch (truncated body, wrong content, etc.)
        // rather than a real "this region has zero holidays" answer. Treat
        // it as a failure rather than silently replacing a previously good
        // cache with nothing.
        throw HolidayIcsParseException(
          'fetched ICS contained no holiday events',
        );
      }
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
