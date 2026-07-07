import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../../wake_plan/domain/wake_plan_domain.dart';
import '../model/week_calendar_interaction.dart';

typedef WeekCalendarTapCallback = void Function(WeekCalendarTapTarget target);
typedef WeekCalendarWakePlanTapCallback =
    void Function(WeekCalendarWakePlanTapTarget target);

class WeekCalendarView extends StatefulWidget {
  const WeekCalendarView({
    super.key,
    required this.now,
    this.initialWeek,
    this.wakePlans = const [],
    this.onTargetTap,
    this.onWakePlanTap,
    this.emptyStateText = 'No wake plans scheduled for this week',
    this.height = 420,
    this.hourHeight = 56,
  });

  final DateTime now;
  final WeekRange? initialWeek;
  final List<WakePlan> wakePlans;
  final WeekCalendarTapCallback? onTargetTap;
  final WeekCalendarWakePlanTapCallback? onWakePlanTap;
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
            wakePlans: widget.wakePlans,
            onTargetTap: widget.onTargetTap,
            onWakePlanTap: widget.onWakePlanTap,
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
    required this.wakePlans,
    required this.onTargetTap,
    required this.onWakePlanTap,
    required this.emptyStateText,
    required this.hourHeight,
    required this.timeAxisWidth,
  });

  final WeekRange week;
  final DateTime now;
  final List<WakePlan> wakePlans;
  final WeekCalendarTapCallback? onTargetTap;
  final WeekCalendarWakePlanTapCallback? onWakePlanTap;
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
    final blocks = weekCalendarWakePlanBlocks(
      week: widget.week,
      wakePlans: widget.wakePlans,
    );

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
                                    for (final block in blocks)
                                      _WakePlanBlock(
                                        block: block,
                                        pixelsPerMinute: _pixelsPerMinute,
                                        dayWidth:
                                            constraints.maxWidth /
                                            DateTime.daysPerWeek,
                                        onTap: widget.onWakePlanTap,
                                      ),
                                    if (blocks.isEmpty)
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

class _WakePlanBlock extends StatelessWidget {
  const _WakePlanBlock({
    required this.block,
    required this.pixelsPerMinute,
    required this.dayWidth,
    required this.onTap,
  });

  static const double _gap = 2;

  final WeekCalendarWakePlanBlock block;
  final double pixelsPerMinute;
  final double dayWidth;
  final WeekCalendarWakePlanTapCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final laneWidth = dayWidth / block.laneCount;
    final left = (block.dayIndex * dayWidth) + (block.laneIndex * laneWidth);
    final top = block.topMinute * pixelsPerMinute;
    final height = block.durationMinutes * pixelsPerMinute;

    return Positioned(
      left: left + _gap,
      top: top + _gap,
      width: (laneWidth - (_gap * 2)).clamp(18, double.infinity),
      height: (height - (_gap * 2)).clamp(18, double.infinity),
      child: _WakePlanBlockCard(block: block, onTap: onTap),
    );
  }
}

class _WakePlanBlockCard extends StatelessWidget {
  const _WakePlanBlockCard({required this.block, required this.onTap});

  final WeekCalendarWakePlanBlock block;
  final WeekCalendarWakePlanTapCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final targetColor = block.containsTarget
        ? colorScheme.tertiary
        : colorScheme.primary;
    final labelColor = colorScheme.onPrimaryContainer;
    final label = _wakePlanBlockLabel(block);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: colorScheme.primaryContainer.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap?.call(block.tapTarget),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 7),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      label,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: labelColor,
                        height: 1.12,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: block.containsTarget
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                child: Container(height: 5, color: targetColor),
              ),
            ],
          ),
        ),
      ),
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

String _wakePlanBlockLabel(WeekCalendarWakePlanBlock block) {
  return '${block.wakePlan.targetTime}\n'
      '${_timeLabel(block.startAt)}-${_timeLabel(block.targetAt)}\n'
      'Every ${block.wakePlan.interval.inMinutes} min\n'
      '${block.occurrenceCount} alarms';
}

String _timeLabel(DateTime dateTime) {
  return '${dateTime.hour.toString().padLeft(2, '0')}:'
      '${dateTime.minute.toString().padLeft(2, '0')}';
}
