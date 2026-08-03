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
