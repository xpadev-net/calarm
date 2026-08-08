/// A region whose public holidays can be fetched and used to skip wake plan
/// occurrences. `code` follows ISO 3166-1 alpha-2 so it can be matched
/// directly against a device locale's country code. Add more entries here as
/// more `holidays/<code>.ics` sources become available upstream — every
/// other layer (storage, settings UI, locale-based defaulting) is written
/// against `HolidayRegion.values` and needs no further changes.
enum HolidayRegion {
  japan(code: 'JP', displayName: 'Japan');

  const HolidayRegion({required this.code, required this.displayName});

  final String code;
  final String displayName;

  static HolidayRegion? fromCode(String? code) {
    if (code == null) {
      return null;
    }
    for (final region in HolidayRegion.values) {
      if (region.code == code) {
        return region;
      }
    }
    return null;
  }
}

const _holidayRegionCodesSeparator = ',';

/// Encodes a set of regions as a comma-separated list of codes for storage
/// in a single nullable text column. Returns null for an empty set.
String? encodeHolidayRegions(Set<HolidayRegion> regions) {
  if (regions.isEmpty) {
    return null;
  }
  return regions
      .map((region) => region.code)
      .join(_holidayRegionCodesSeparator);
}

/// Inverse of [encodeHolidayRegions]. Unknown/stale codes are dropped rather
/// than failing, so removing a region from [HolidayRegion] never breaks
/// loading a previously-saved settings row.
Set<HolidayRegion> decodeHolidayRegions(String? value) {
  if (value == null || value.isEmpty) {
    return const {};
  }
  return value
      .split(_holidayRegionCodesSeparator)
      .map(HolidayRegion.fromCode)
      .whereType<HolidayRegion>()
      .toSet();
}
