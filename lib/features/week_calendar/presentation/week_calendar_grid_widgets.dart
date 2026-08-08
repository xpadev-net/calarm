import 'package:flutter/material.dart';

import '../../../core/time/time.dart';
import '../model/week_calendar_interaction.dart';
import 'week_calendar_format.dart';
import 'week_calendar_view.dart';

class WeekCalendarWakePlanBlockView extends StatelessWidget {
  const WeekCalendarWakePlanBlockView({
    super.key,
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
    final horizontalGap = laneWidth > (_gap * 2) ? _gap : laneWidth / 8;
    final blockWidth = (laneWidth - (horizontalGap * 2))
        .clamp(0, laneWidth)
        .toDouble();

    return Positioned(
      left: left + horizontalGap,
      top: top + _gap,
      width: blockWidth,
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
    final label = weekCalendarWakePlanBlockLabel(block);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        key: ValueKey(
          'week-calendar-wake-plan-block-'
          '${block.wakePlan.id}-${block.day}-${block.laneIndex}',
        ),
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

class WeekCalendarDateHeader extends StatelessWidget {
  const WeekCalendarDateHeader({
    super.key,
    required this.week,
    required this.now,
    this.holidays = const {},
  });

  final WeekRange week;
  final DateTime now;
  final Set<CalendarDay> holidays;

  @override
  Widget build(BuildContext context) {
    final today = CalendarDay.fromDateTime(now);

    return Row(
      children: [
        for (final day in week.days)
          Expanded(
            child: WeekCalendarDateHeaderCell(
              weekdayLabel: weekCalendarWeekdayLabel(day.weekday),
              dayLabel: '${day.day}',
              highlighted: day == today,
              dayKind: weekCalendarDateHeaderDayKind(day, holidays),
            ),
          ),
      ],
    );
  }
}

/// Reserves exactly the height a real [WeekCalendarDateHeader] cell takes, without
/// rendering any real weekday/day-number text, so it can size the fixed time
/// axis's header spacer without also being matched by `find.text('Mon')`
/// (etc.) finders in tests.
class WeekCalendarDateHeaderSizingProbe extends StatelessWidget {
  const WeekCalendarDateHeaderSizingProbe({super.key});

  @override
  Widget build(BuildContext context) {
    return const WeekCalendarDateHeaderCell(
      weekdayLabel: '',
      dayLabel: '',
      highlighted: false,
    );
  }
}

class WeekCalendarDateHeaderCell extends StatelessWidget {
  const WeekCalendarDateHeaderCell({
    super.key,
    required this.weekdayLabel,
    required this.dayLabel,
    required this.highlighted,
    this.dayKind = WeekCalendarDateHeaderDayKind.normal,
  });

  final String weekdayLabel;
  final String dayLabel;
  final bool highlighted;
  final WeekCalendarDateHeaderDayKind dayKind;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dayKindColor = weekCalendarDateHeaderDayKindColor(dayKind);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              weekdayLabel,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: dayKindColor),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlighted ? colorScheme.primary : Colors.transparent,
            ),
            child: Text(
              dayLabel,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: highlighted
                    ? colorScheme.onPrimary
                    : (dayKindColor ?? colorScheme.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WeekCalendarTimeAxis extends StatelessWidget {
  const WeekCalendarTimeAxis({super.key, required this.hourHeight});

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

class WeekCalendarTimeGrid extends StatelessWidget {
  const WeekCalendarTimeGrid({
    super.key,
    required this.week,
    required this.now,
    required this.hourHeight,
    required this.snapIntervalMinutes,
  });

  final WeekRange week;
  final DateTime now;
  final double hourHeight;
  final int snapIntervalMinutes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = CalendarDay.fromDateTime(now);
    final currentMinute =
        now.hour * TimeOfDayMinutes.minutesPerHour + now.minute;

    return CustomPaint(
      key: const ValueKey('week-calendar-time-grid'),
      painter: _TimeGridPainter(
        lineColor: colorScheme.outlineVariant,
        subIntervalLineColor: colorScheme.outlineVariant.withValues(alpha: 0.4),
        dayLineColor: colorScheme.outline,
        currentTimeColor: colorScheme.error,
        hourHeight: hourHeight,
        visibleDays: week.visibleDays,
        snapIntervalMinutes: snapIntervalMinutes,
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
    required this.subIntervalLineColor,
    required this.dayLineColor,
    required this.currentTimeColor,
    required this.hourHeight,
    required this.visibleDays,
    required this.snapIntervalMinutes,
    required this.currentDayIndex,
    required this.currentMinute,
  });

  final Color lineColor;
  final Color subIntervalLineColor;
  final Color dayLineColor;
  final Color currentTimeColor;
  final double hourHeight;
  final int visibleDays;
  final int snapIntervalMinutes;
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

    if (snapIntervalMinutes < TimeOfDayMinutes.minutesPerHour) {
      final subIntervalPaint = Paint()
        ..color = subIntervalLineColor
        ..strokeWidth = 1;
      final pixelsPerMinute = hourHeight / TimeOfDayMinutes.minutesPerHour;
      for (
        var minute = snapIntervalMinutes;
        minute < TimeOfDayMinutes.minutesPerDay;
        minute += snapIntervalMinutes
      ) {
        if (minute % TimeOfDayMinutes.minutesPerHour == 0) {
          continue;
        }
        final y = minute * pixelsPerMinute;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), subIntervalPaint);
      }
    }

    for (var hour = 0; hour <= TimeOfDayMinutes.hoursPerDay; hour++) {
      final y = hour * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hourPaint);
    }

    final dayWidth = size.width / visibleDays;
    for (var day = 0; day <= visibleDays; day++) {
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
        oldDelegate.subIntervalLineColor != subIntervalLineColor ||
        oldDelegate.dayLineColor != dayLineColor ||
        oldDelegate.currentTimeColor != currentTimeColor ||
        oldDelegate.hourHeight != hourHeight ||
        oldDelegate.visibleDays != visibleDays ||
        oldDelegate.snapIntervalMinutes != snapIntervalMinutes ||
        oldDelegate.currentDayIndex != currentDayIndex ||
        oldDelegate.currentMinute != currentMinute;
  }
}
