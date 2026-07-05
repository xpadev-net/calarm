import '../../../core/time/time.dart';
import '../domain/wake_plan_domain.dart';

class OccurrencePlanner {
  const OccurrencePlanner();

  OccurrencePlan plan({
    required WakePlan wakePlan,
    required CalendarDay startDay,
    required CalendarDay endExclusive,
    required DateTime now,
  }) {
    if (endExclusive.compareTo(startDay) < 0) {
      throw ArgumentError.value(
        endExclusive,
        'endExclusive',
        'must be on or after startDay',
      );
    }

    final wakeInstances = <WakeInstanceDraft>[];
    final previewOccurrences = <AlarmOccurrenceDraft>[];
    final schedulingCandidates = <AlarmOccurrenceDraft>[];

    for (
      var day = startDay;
      day.compareTo(endExclusive) < 0;
      day = day.addDays(1)
    ) {
      if (!wakePlan.occursOn(day)) {
        continue;
      }

      final wakeInstance = _buildWakeInstance(wakePlan, day);
      wakeInstances.add(wakeInstance);
      previewOccurrences.addAll(wakeInstance.occurrences);
      schedulingCandidates.addAll(
        wakeInstance.occurrences.where((occurrence) {
          return !occurrence.scheduledAt.toDateTime().isBefore(now);
        }),
      );
    }

    return OccurrencePlan(
      wakeInstances: wakeInstances,
      previewOccurrences: previewOccurrences,
      schedulingCandidates: schedulingCandidates,
    );
  }

  WakeInstanceDraft _buildWakeInstance(WakePlan wakePlan, CalendarDay day) {
    final targetAt = DateMinute.fromDateTime(wakePlan.targetAt(day));
    final startsAt = DateMinute.fromDateTime(wakePlan.startAt(day));
    final intervalMinutes = wakePlan.interval.inMinutes;
    final occurrences = <AlarmOccurrenceDraft>[];

    for (
      var scheduledAt = startsAt;
      scheduledAt.compareTo(targetAt) < 0;
      scheduledAt = scheduledAt.addMinutes(intervalMinutes)
    ) {
      occurrences.add(
        AlarmOccurrenceDraft(wakePlanId: wakePlan.id, scheduledAt: scheduledAt),
      );
    }

    if (occurrences.isEmpty || occurrences.last.scheduledAt != targetAt) {
      occurrences.add(
        AlarmOccurrenceDraft(wakePlanId: wakePlan.id, scheduledAt: targetAt),
      );
    }

    return WakeInstanceDraft(
      wakePlanId: wakePlan.id,
      targetDay: day,
      startsAt: startsAt,
      targetAt: targetAt,
      occurrences: occurrences,
    );
  }
}

class OccurrencePlan {
  OccurrencePlan({
    required Iterable<WakeInstanceDraft> wakeInstances,
    required Iterable<AlarmOccurrenceDraft> previewOccurrences,
    required Iterable<AlarmOccurrenceDraft> schedulingCandidates,
  }) : wakeInstances = List.unmodifiable(wakeInstances),
       previewOccurrences = List.unmodifiable(previewOccurrences),
       schedulingCandidates = List.unmodifiable(schedulingCandidates);

  final List<WakeInstanceDraft> wakeInstances;
  final List<AlarmOccurrenceDraft> previewOccurrences;
  final List<AlarmOccurrenceDraft> schedulingCandidates;

  int get previewCount => previewOccurrences.length;

  int get schedulingCandidateCount => schedulingCandidates.length;
}

class WakeInstanceDraft {
  WakeInstanceDraft({
    required this.wakePlanId,
    required this.targetDay,
    required this.startsAt,
    required this.targetAt,
    required Iterable<AlarmOccurrenceDraft> occurrences,
  }) : occurrences = List.unmodifiable(occurrences);

  final String wakePlanId;
  final CalendarDay targetDay;
  final DateMinute startsAt;
  final DateMinute targetAt;
  final List<AlarmOccurrenceDraft> occurrences;
}

class AlarmOccurrenceDraft {
  const AlarmOccurrenceDraft({
    required this.wakePlanId,
    required this.scheduledAt,
  });

  final String wakePlanId;
  final DateMinute scheduledAt;
}
