import 'dart:ui' as ui;

import '../../wake_plan/domain/wake_plan_domain.dart';

/// Best-effort default holiday regions derived from the device's configured
/// locales, used only to seed a first-run default — it never overrides an
/// explicit user choice. Matches each locale's country code directly against
/// [HolidayRegion.code], so this stays correct with no changes as more
/// regions are added to [HolidayRegion].
Set<HolidayRegion> detectDefaultHolidayRegions({List<ui.Locale>? locales}) {
  final effectiveLocales = locales ?? ui.PlatformDispatcher.instance.locales;
  final regions = <HolidayRegion>{};
  for (final locale in effectiveLocales) {
    final region = HolidayRegion.fromCode(locale.countryCode);
    if (region != null) {
      regions.add(region);
    }
  }
  return regions;
}
