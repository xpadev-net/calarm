import 'package:flutter/material.dart';

import '../week_calendar.dart';

class WeekCalendarPlaceholder extends StatelessWidget {
  const WeekCalendarPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return WeekCalendarView(now: DateTime.now());
  }
}
