import 'package:calarm/features/wake_plan/domain/wake_plan_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encodeHolidayRegions', () {
    test('returns null for an empty set', () {
      expect(encodeHolidayRegions(const {}), isNull);
    });

    test('encodes a single region as its code', () {
      expect(encodeHolidayRegions({HolidayRegion.japan}), 'JP');
    });
  });

  group('decodeHolidayRegions', () {
    test('returns an empty set for null', () {
      expect(decodeHolidayRegions(null), isEmpty);
    });

    test('returns an empty set for an empty string', () {
      expect(decodeHolidayRegions(''), isEmpty);
    });

    test('decodes a single known code', () {
      expect(decodeHolidayRegions('JP'), {HolidayRegion.japan});
    });

    test('drops unknown/stale codes instead of failing', () {
      expect(decodeHolidayRegions('JP,XX'), {HolidayRegion.japan});
      expect(decodeHolidayRegions('XX'), isEmpty);
    });
  });

  test('round-trips through encode then decode', () {
    const regions = {HolidayRegion.japan};
    expect(decodeHolidayRegions(encodeHolidayRegions(regions)), regions);
  });

  test('round-trips an empty set through encode then decode', () {
    expect(decodeHolidayRegions(encodeHolidayRegions(const {})), isEmpty);
  });
}
