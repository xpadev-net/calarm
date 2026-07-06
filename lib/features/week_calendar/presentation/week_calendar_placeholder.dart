import 'package:flutter/material.dart';

import '../week_calendar.dart';

class WeekCalendarPlaceholder extends StatelessWidget {
  const WeekCalendarPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Week calendar', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        WeekCalendarView(now: DateTime.now(), height: 220, hourHeight: 44),
      ],
    );
  }
}
