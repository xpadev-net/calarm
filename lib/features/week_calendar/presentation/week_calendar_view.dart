import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../model/week_calendar_interaction.dart';

typedef WeekCalendarTapCallback = void Function(WeekCalendarTapTarget target);

class WeekCalendarView extends StatefulWidget {
  const WeekCalendarView({
    super.key,
    required this.now,
    this.initialWeek,
    this.onTargetTap,
    this.emptyStateText = 'No wake plans scheduled for this week',
    this.height = 420,
    this.hourHeight = 56,
  });

  final DateTime now;
  final WeekRange? initialWeek;
  final WeekCalendarTapCallback? onTargetTap;
  final String emptyStateText;
  final double height;
  final double hourHeight;

  @override
  State<WeekCalendarView> createState() => _WeekCalendarViewState();
}

class _WeekCalendarViewState extends State<WeekCalendarView> {
  static const int _initialPage = 10000;
  static const double _timeAxisWidth = 52;

  late final WeekCalendarPage _initialCalendarPage;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _initialCalendarPage = WeekCalendarPage(
      week: widget.initialWeek ?? visibleWeekRange(widget.now),
    );
    _pageController = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _pageController,
        itemBuilder: (context, index) {
          final week = _initialCalendarPage.addWeeks(index - _initialPage).week;
          return _WeekCalendarWeekPage(
            week: week,
            now: widget.now,
            onTargetTap: widget.onTargetTap,
            emptyStateText: widget.emptyStateText,
            hourHeight: widget.hourHeight,
            timeAxisWidth: _timeAxisWidth,
          );
        },
      ),
    );
  }
}

class _WeekCalendarWeekPage extends StatefulWidget {
  const _WeekCalendarWeekPage({
    required this.week,
    required this.now,
    required this.onTargetTap,
    required this.emptyStateText,
    required this.hourHeight,
    required this.timeAxisWidth,
  });

  final WeekRange week;
  final DateTime now;
  final WeekCalendarTapCallback? onTargetTap;
  final String emptyStateText;
  final double hourHeight;
  final double timeAxisWidth;

  @override
  State<_WeekCalendarWeekPage> createState() => _WeekCalendarWeekPageState();
}

class _WeekCalendarWeekPageState extends State<_WeekCalendarWeekPage> {
  late final ScrollController _scrollController;

  double get _pixelsPerMinute {
    return widget.hourHeight / TimeOfDayMinutes.minutesPerHour;
  }

  @override
  void initState() {
    super.initState();
    final target = initialWeekCalendarScrollTarget(
      week: widget.week,
      now: widget.now,
      pixelsPerMinute: _pixelsPerMinute,
    );
    _scrollController = ScrollController(initialScrollOffset: target.offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _DateHeader(
          week: widget.week,
          now: widget.now,
          timeAxisWidth: widget.timeAxisWidth,
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SizedBox(
                    height: widget.hourHeight * TimeOfDayMinutes.hoursPerDay,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: widget.timeAxisWidth,
                          child: _TimeAxis(hourHeight: widget.hourHeight),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (details) {
                                  final target =
                                      weekCalendarTapTargetFromPosition(
                                        week: widget.week,
                                        localX: details.localPosition.dx,
                                        localY: details.localPosition.dy,
                                        gridWidth: constraints.maxWidth,
                                        gridHeight:
                                            widget.hourHeight *
                                            TimeOfDayMinutes.hoursPerDay,
                                      );
                                  widget.onTargetTap?.call(target);
                                },
                                child: Stack(
                                  children: [
                                    _TimeGrid(
                                      week: widget.week,
                                      now: widget.now,
                                      hourHeight: widget.hourHeight,
                                    ),
                                    Center(
                                      child: _EmptyState(
                                        text: widget.emptyStateText,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.week,
    required this.now,
    required this.timeAxisWidth,
  });

  final WeekRange week;
  final DateTime now;
  final double timeAxisWidth;

  @override
  Widget build(BuildContext context) {
    final today = CalendarDay.fromDateTime(now);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(width: timeAxisWidth),
        for (final day in week.days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _weekdayLabel(day.weekday),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: day == today
                          ? colorScheme.primary
                          : Colors.transparent,
                    ),
                    child: Text(
                      '${day.day}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: day == today
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TimeAxis extends StatelessWidget {
  const _TimeAxis({required this.hourHeight});

  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var hour = 0; hour <= TimeOfDayMinutes.hoursPerDay; hour++)
          Positioned(
            top: hour * hourHeight,
            right: 8,
            child: Transform.translate(
              offset: const Offset(0, -8),
              child: Text(
                hour == TimeOfDayMinutes.hoursPerDay
                    ? '24:00'
                    : '${hour.toString().padLeft(2, '0')}:00',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
      ],
    );
  }
}

class _TimeGrid extends StatelessWidget {
  const _TimeGrid({
    required this.week,
    required this.now,
    required this.hourHeight,
  });

  final WeekRange week;
  final DateTime now;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = CalendarDay.fromDateTime(now);
    final currentMinute =
        now.hour * TimeOfDayMinutes.minutesPerHour + now.minute;

    return CustomPaint(
      painter: _TimeGridPainter(
        lineColor: colorScheme.outlineVariant,
        dayLineColor: colorScheme.outline,
        currentTimeColor: colorScheme.error,
        hourHeight: hourHeight,
        currentDayIndex: week.contains(today)
            ? today.differenceInDays(week.start)
            : null,
        currentMinute: currentMinute,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TimeGridPainter extends CustomPainter {
  const _TimeGridPainter({
    required this.lineColor,
    required this.dayLineColor,
    required this.currentTimeColor,
    required this.hourHeight,
    required this.currentDayIndex,
    required this.currentMinute,
  });

  final Color lineColor;
  final Color dayLineColor;
  final Color currentTimeColor;
  final double hourHeight;
  final int? currentDayIndex;
  final int currentMinute;

  @override
  void paint(Canvas canvas, Size size) {
    final hourPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    final dayPaint = Paint()
      ..color = dayLineColor
      ..strokeWidth = 1;

    for (var hour = 0; hour <= TimeOfDayMinutes.hoursPerDay; hour++) {
      final y = hour * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hourPaint);
    }

    final dayWidth = size.width / DateTime.daysPerWeek;
    for (var day = 0; day <= DateTime.daysPerWeek; day++) {
      final x = day * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dayPaint);
    }

    final currentDayIndex = this.currentDayIndex;
    if (currentDayIndex == null) {
      return;
    }

    final currentY =
        currentMinute * (hourHeight / TimeOfDayMinutes.minutesPerHour);
    final currentStartX = currentDayIndex * dayWidth;
    final currentEndX = currentStartX + dayWidth;
    final currentPaint = Paint()
      ..color = currentTimeColor
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(currentStartX, currentY),
      Offset(currentEndX, currentY),
      currentPaint,
    );
  }

  @override
  bool shouldRepaint(_TimeGridPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.dayLineColor != dayLineColor ||
        oldDelegate.currentTimeColor != currentTimeColor ||
        oldDelegate.hourHeight != hourHeight ||
        oldDelegate.currentDayIndex != currentDayIndex ||
        oldDelegate.currentMinute != currentMinute;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => throw RangeError.range(weekday, DateTime.monday, DateTime.sunday),
  };
}
