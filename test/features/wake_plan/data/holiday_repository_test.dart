import 'dart:async';

import 'package:calarm/core/time/time.dart';
import 'package:calarm/features/wake_plan/data/wake_plan_data.dart';
import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleIcs =
    'BEGIN:VCALENDAR\r\n'
    'BEGIN:VEVENT\r\n'
    'DTSTART;VALUE=DATE:20260101\r\n'
    'SUMMARY:元日\r\n'
    'END:VEVENT\r\n'
    'BEGIN:VEVENT\r\n'
    'DTSTART;VALUE=DATE:20260112\r\n'
    'SUMMARY:成人の日\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  late WakePlanDatabase database;

  setUp(() {
    database = WakePlanDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  group('HolidayRepository', () {
    test('holidaysFor returns an empty set before any refresh', () async {
      // holidaysFor also kicks off a non-blocking background refresh; using
      // a fetcher that never resolves keeps that background work from
      // touching the database after this test (and its database) complete.
      final repository = HolidayRepository(
        database: database,
        fetchIcs: (uri) => Completer<String>().future,
      );

      final holidays = await repository.holidaysFor(HolidayRegion.japan);

      expect(holidays, isEmpty);
    });

    test('refresh caches parsed holidays queryable by holidaysFor', () async {
      final repository = HolidayRepository(
        database: database,
        fetchIcs: (uri) async => _sampleIcs,
      );

      await repository.refresh(HolidayRegion.japan);
      final holidays = await repository.holidaysFor(HolidayRegion.japan);

      expect(holidays, {
        CalendarDay(year: 2026, month: 1, day: 1),
        CalendarDay(year: 2026, month: 1, day: 12),
      });
    });

    test(
      'refresh requests the expected raw.githubusercontent.com URL',
      () async {
        Uri? requestedUri;
        final repository = HolidayRepository(
          database: database,
          fetchIcs: (uri) async {
            requestedUri = uri;
            return _sampleIcs;
          },
        );

        await repository.refresh(HolidayRegion.japan);

        expect(
          requestedUri.toString(),
          'https://raw.githubusercontent.com/xpadev-net/holidays-ical/main/'
          'holidays/JP.ics',
        );
      },
    );

    test(
      'refresh replaces previously cached holidays for the region',
      () async {
        var callCount = 0;
        final repository = HolidayRepository(
          database: database,
          fetchIcs: (uri) async {
            callCount += 1;
            if (callCount == 1) {
              return _sampleIcs;
            }
            return 'BEGIN:VCALENDAR\r\n'
                'BEGIN:VEVENT\r\n'
                'DTSTART;VALUE=DATE:20260503\r\n'
                'SUMMARY:憲法記念日\r\n'
                'END:VEVENT\r\n'
                'END:VCALENDAR\r\n';
          },
        );

        await repository.refresh(HolidayRegion.japan);
        await repository.refresh(HolidayRegion.japan);
        final holidays = await repository.holidaysFor(HolidayRegion.japan);

        expect(holidays, {CalendarDay(year: 2026, month: 5, day: 3)});
      },
    );

    test(
      'fails open on network failure: holidaysFor stays empty, no throw',
      () async {
        final repository = HolidayRepository(
          database: database,
          fetchIcs: (uri) async => throw Exception('network unreachable'),
        );

        await expectLater(repository.refresh(HolidayRegion.japan), completes);
        final holidays = await repository.holidaysFor(HolidayRegion.japan);

        expect(holidays, isEmpty);

        // holidaysFor also kicks off a non-blocking background refresh
        // (always retried here, since the fetch never records a success).
        // Drain it before tearDown closes the database.
        await _drainMicrotasks();
      },
    );

    test(
      'fails open on malformed ICS: keeps previously cached data untouched',
      () async {
        var callCount = 0;
        final repository = HolidayRepository(
          database: database,
          fetchIcs: (uri) async {
            callCount += 1;
            if (callCount == 1) {
              return _sampleIcs;
            }
            // Missing SUMMARY makes this VEVENT unparsable.
            return 'BEGIN:VCALENDAR\r\n'
                'BEGIN:VEVENT\r\n'
                'DTSTART;VALUE=DATE:20260101\r\n'
                'END:VEVENT\r\n'
                'END:VCALENDAR\r\n';
          },
        );

        await repository.refresh(HolidayRegion.japan);
        await repository.refresh(HolidayRegion.japan);
        final holidays = await repository.holidaysFor(HolidayRegion.japan);

        expect(holidays, {
          CalendarDay(year: 2026, month: 1, day: 1),
          CalendarDay(year: 2026, month: 1, day: 12),
        });
      },
    );

    test('refresh treats a valid but event-free response as a failure, '
        'preserving the prior cache', () async {
      var callCount = 0;
      final repository = HolidayRepository(
        database: database,
        fetchIcs: (uri) async {
          callCount += 1;
          if (callCount == 1) {
            return _sampleIcs;
          }
          // Well-formed but zero VEVENTs — e.g. a truncated/degraded
          // response that's still syntactically parsable.
          return 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n';
        },
      );

      await repository.refresh(HolidayRegion.japan);
      await repository.refresh(HolidayRegion.japan);
      final holidays = await repository.holidaysFor(HolidayRegion.japan);

      expect(holidays, {
        CalendarDay(year: 2026, month: 1, day: 1),
        CalendarDay(year: 2026, month: 1, day: 12),
      });
    });

    test('watchHolidays reactively emits an updated set once a background '
        'refresh completes', () async {
      final fetchCompleter = Completer<String>();
      final repository = HolidayRepository(
        database: database,
        fetchIcs: (uri) => fetchCompleter.future,
      );

      final emissions = <Set<CalendarDay>>[];
      final subscription = repository
          .watchHolidays(HolidayRegion.japan)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await _drainMicrotasks();
      expect(emissions, [isEmpty]);

      fetchCompleter.complete(_sampleIcs);
      await _drainMicrotasks();

      expect(emissions.last, {
        CalendarDay(year: 2026, month: 1, day: 1),
        CalendarDay(year: 2026, month: 1, day: 12),
      });
    });

    test('refreshIfStale skips refresh when recently fetched', () async {
      var fetchCount = 0;
      final fixedNow = DateTime(2026, 1, 10);
      final repository = HolidayRepository(
        database: database,
        fetchIcs: (uri) async {
          fetchCount += 1;
          return _sampleIcs;
        },
        now: () => fixedNow,
      );

      await repository.refresh(HolidayRegion.japan);
      await repository.refreshIfStale(HolidayRegion.japan);

      expect(fetchCount, 1);
    });

    test(
      'refreshIfStale refreshes again once staleAfter has elapsed',
      () async {
        var fetchCount = 0;
        var now = DateTime(2026, 1, 10);
        final repository = HolidayRepository(
          database: database,
          fetchIcs: (uri) async {
            fetchCount += 1;
            return _sampleIcs;
          },
          staleAfter: const Duration(days: 7),
          now: () => now,
        );

        await repository.refresh(HolidayRegion.japan);
        now = now.add(const Duration(days: 8));
        await repository.refreshIfStale(HolidayRegion.japan);

        expect(fetchCount, 2);
      },
    );

    test(
      'fails open on a database-layer error: holidaysFor stays empty, no throw',
      () async {
        final repository = HolidayRepository(
          database: database,
          fetchIcs: (uri) async => _sampleIcs,
        );
        await database.close();

        await expectLater(
          repository.holidaysFor(HolidayRegion.japan),
          completion(isEmpty),
        );
      },
    );

    test('refreshIfStale refreshes when never fetched before', () async {
      var fetchCount = 0;
      final repository = HolidayRepository(
        database: database,
        fetchIcs: (uri) async {
          fetchCount += 1;
          return _sampleIcs;
        },
      );

      await repository.refreshIfStale(HolidayRegion.japan);

      expect(fetchCount, 1);
    });
  });
}

Future<void> _drainMicrotasks() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
