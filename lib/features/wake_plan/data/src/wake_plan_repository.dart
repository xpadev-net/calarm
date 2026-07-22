import 'package:drift/drift.dart';

import '../../../../core/time/time.dart';
import '../../domain/wake_plan_domain.dart';
import 'wake_plan_database.dart';

class WakePlanReconciliationSnapshot {
  WakePlanReconciliationSnapshot({
    required List<WakePlan> plans,
    required List<AlarmOccurrence> occurrences,
    Set<String> corruptPlanIds = const {},
    Set<String> corruptOccurrenceIds = const {},
    Set<String> corruptOccurrenceWakePlanIds = const {},
  }) : plans = List.unmodifiable(plans),
       occurrences = List.unmodifiable(occurrences),
       corruptPlanIds = Set.unmodifiable(corruptPlanIds),
       corruptOccurrenceIds = Set.unmodifiable(corruptOccurrenceIds),
       corruptOccurrenceWakePlanIds = Set.unmodifiable(
         corruptOccurrenceWakePlanIds,
       );

  final List<WakePlan> plans;
  final List<AlarmOccurrence> occurrences;
  final Set<String> corruptPlanIds;
  final Set<String> corruptOccurrenceIds;
  final Set<String> corruptOccurrenceWakePlanIds;
}

class AlarmOccurrencePlatformMatchSnapshot {
  AlarmOccurrencePlatformMatchSnapshot({
    required List<AlarmOccurrence> occurrences,
    required Set<String> corruptPlatformAlarmIds,
  }) : occurrences = List.unmodifiable(occurrences),
       corruptPlatformAlarmIds = Set.unmodifiable(corruptPlatformAlarmIds);

  final List<AlarmOccurrence> occurrences;
  final Set<String> corruptPlatformAlarmIds;
}

class AlarmOccurrenceDismissalIntent {
  const AlarmOccurrenceDismissalIntent({
    required this.occurrence,
    required this.requestedAt,
    required this.platformAlarmId,
  });

  final AlarmOccurrence occurrence;
  final DateTime requestedAt;
  final String? platformAlarmId;
}

enum AlarmOccurrenceDismissalPreparationStatus {
  ready,
  notFound,
  alreadyDismissed,
  noLongerEligible,
}

class AlarmOccurrenceDismissalPreparation {
  const AlarmOccurrenceDismissalPreparation._({
    required this.status,
    this.intent,
  });

  const AlarmOccurrenceDismissalPreparation.ready(
    AlarmOccurrenceDismissalIntent intent,
  ) : this._(
        status: AlarmOccurrenceDismissalPreparationStatus.ready,
        intent: intent,
      );

  const AlarmOccurrenceDismissalPreparation.notFound()
    : this._(status: AlarmOccurrenceDismissalPreparationStatus.notFound);

  const AlarmOccurrenceDismissalPreparation.alreadyDismissed()
    : this._(
        status: AlarmOccurrenceDismissalPreparationStatus.alreadyDismissed,
      );

  const AlarmOccurrenceDismissalPreparation.noLongerEligible()
    : this._(
        status: AlarmOccurrenceDismissalPreparationStatus.noLongerEligible,
      );

  final AlarmOccurrenceDismissalPreparationStatus status;
  final AlarmOccurrenceDismissalIntent? intent;
}

class WakePlanRepository {
  WakePlanRepository(this._database);

  static const Duration oneTimeHistoryRetention = Duration(minutes: 30);
  static const int _appSettingsId = 1;

  final WakePlanDatabase _database;

  Future<void> saveWakePlan(WakePlan plan) {
    return _database
        .into(_database.wakePlanRows)
        .insertOnConflictUpdate(_wakePlanCompanion(plan));
  }

  Future<WakePlan?> fetchWakePlan(
    String id, {
    bool includeDeleted = false,
  }) async {
    final query = _database.select(_database.wakePlanRows)
      ..where((row) => row.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }

    final plan = _tryWakePlanFromRow(row);
    if (plan == null) {
      return null;
    }
    if (!includeDeleted && plan.isDeleted) {
      return null;
    }

    return plan;
  }

  Future<List<WakePlan>> fetchWakePlans({
    required DateTime now,
    bool includeDeleted = false,
    bool includeExpiredOneTimeHistory = false,
  }) async {
    final query = _database.select(_database.wakePlanRows);
    if (!includeDeleted) {
      query.where((row) => row.status.isNotValue(WakePlanStatus.deleted.name));
    }
    if (!includeExpiredOneTimeHistory) {
      query.where((row) => _notExpiredOneTimeExpression(row, now));
    }
    query.orderBy([(row) => OrderingTerm.asc(row.targetTimeMinutes)]);
    final rows = await query.get();

    return rows
        .map(_tryWakePlanFromRow)
        .whereType<WakePlan>()
        .where((plan) => includeDeleted || !plan.isDeleted)
        .where(
          (plan) =>
              includeExpiredOneTimeHistory ||
              !_isExpiredOneTimePlan(plan: plan, now: now),
        )
        .toList(growable: false);
  }

  Future<List<WakePlan>> fetchWakePlansForCalendarRange({
    required CalendarDay start,
    required CalendarDay end,
    bool includeDisabled = false,
    bool includeDeleted = false,
  }) async {
    if (end.compareTo(start) < 0) {
      throw ArgumentError.value(end, 'end', 'must not be before start');
    }

    final query = _database.select(_database.wakePlanRows);
    if (!includeDeleted) {
      query.where((row) => row.status.isNotValue(WakePlanStatus.deleted.name));
    }
    if (!includeDisabled) {
      query.where((row) => row.isEnabled.equals(true));
    }
    final rows = await query.get();
    return rows
        .map(_tryWakePlanFromRow)
        .whereType<WakePlan>()
        .where((plan) => _planIntersectsRange(plan, start, end))
        .toList(growable: false);
  }

  Future<void> softDeleteWakePlan({
    required String id,
    required DateTime updatedAt,
  }) async {
    final rowsUpdated =
        await (_database.update(
          _database.wakePlanRows,
        )..where((row) => row.id.equals(id))).write(
          WakePlanRowsCompanion(
            isEnabled: const Value(false),
            status: Value(WakePlanStatus.deleted.name),
            skipNextDateDays: const Value(null),
            updatedAt: Value(updatedAt),
          ),
        );
    if (rowsUpdated == 0) {
      throw StateError('WakePlan not found: $id');
    }
  }

  Future<void> saveAlarmOccurrences(Iterable<AlarmOccurrence> occurrences) {
    return _database.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _database.alarmOccurrenceRows,
        occurrences.map(_alarmOccurrenceCompanion).toList(growable: false),
      );
    });
  }

  Future<AlarmOccurrence?> fetchAlarmOccurrence(String id) async {
    final row = await (_database.select(
      _database.alarmOccurrenceRows,
    )..where((row) => row.id.equals(id))).getSingleOrNull();

    return row == null ? null : _tryAlarmOccurrenceFromRow(row);
  }

  Future<List<AlarmOccurrenceDismissalIntent>>
  fetchPendingAlarmOccurrenceDismissals() async {
    final rows =
        await (_database.select(_database.alarmOccurrenceRows)
              ..where((row) => row.dismissalRequestedAt.isNotNull())
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();

    return rows
        .map(_dismissalIntentFromRow)
        .whereType<AlarmOccurrenceDismissalIntent>()
        .toList(growable: false);
  }

  Future<AlarmOccurrenceDismissalIntent?> fetchPendingAlarmOccurrenceDismissal(
    String occurrenceId,
  ) async {
    final row =
        await (_database.select(_database.alarmOccurrenceRows)..where(
              (row) =>
                  row.id.equals(occurrenceId) &
                  row.dismissalRequestedAt.isNotNull(),
            ))
            .getSingleOrNull();
    return row == null ? null : _dismissalIntentFromRow(row);
  }

  Future<AlarmOccurrenceDismissalPreparation> prepareAlarmOccurrenceDismissal({
    required String occurrenceId,
    required String? expectedPlatformAlarmId,
    required DateTime requestedAt,
  }) {
    return _database.transaction(() async {
      final row = await (_database.select(
        _database.alarmOccurrenceRows,
      )..where((row) => row.id.equals(occurrenceId))).getSingleOrNull();
      if (row == null) {
        return const AlarmOccurrenceDismissalPreparation.notFound();
      }

      final existingIntent = _dismissalIntentFromRow(row);
      if (existingIntent != null) {
        return AlarmOccurrenceDismissalPreparation.ready(existingIntent);
      }
      if (row.status == AlarmOccurrenceStatus.dismissed.name) {
        return const AlarmOccurrenceDismissalPreparation.alreadyDismissed();
      }
      final occurrence = _tryAlarmOccurrenceFromRow(row);
      if (occurrence == null ||
          (occurrence.status != AlarmOccurrenceStatus.scheduled &&
              occurrence.status != AlarmOccurrenceStatus.ringing) ||
          occurrence.platformAlarmId != expectedPlatformAlarmId) {
        return const AlarmOccurrenceDismissalPreparation.noLongerEligible();
      }

      await (_database.update(
        _database.alarmOccurrenceRows,
      )..where((candidate) => candidate.id.equals(occurrenceId))).write(
        AlarmOccurrenceRowsCompanion(
          dismissalRequestedAt: Value(requestedAt),
          dismissalPlatformAlarmId: Value(expectedPlatformAlarmId),
          updatedAt: Value(
            requestedAt.isAfter(row.updatedAt) ? requestedAt : row.updatedAt,
          ),
        ),
      );
      return AlarmOccurrenceDismissalPreparation.ready(
        AlarmOccurrenceDismissalIntent(
          occurrence: occurrence.copyWith(
            updatedAt: requestedAt.isAfter(row.updatedAt)
                ? requestedAt
                : row.updatedAt,
          ),
          requestedAt: requestedAt,
          platformAlarmId: expectedPlatformAlarmId,
        ),
      );
    });
  }

  Future<void> completeAlarmOccurrenceDismissal({
    required AlarmOccurrenceDismissalIntent intent,
    required DateTime dismissedAt,
  }) {
    return _database.transaction(() async {
      final row = await (_database.select(
        _database.alarmOccurrenceRows,
      )..where((row) => row.id.equals(intent.occurrence.id))).getSingleOrNull();
      if (row == null) {
        throw StateError('AlarmOccurrence not found: ${intent.occurrence.id}');
      }
      if (row.dismissalRequestedAt == null) {
        if (row.status == AlarmOccurrenceStatus.dismissed.name) {
          return;
        }
        throw StateError(
          'AlarmOccurrence dismissal is not pending: ${intent.occurrence.id}',
        );
      }
      if (row.dismissalRequestedAt != intent.requestedAt ||
          row.dismissalPlatformAlarmId != intent.platformAlarmId ||
          (row.platformAlarmId != null &&
              row.platformAlarmId != intent.platformAlarmId)) {
        throw StateError(
          'AlarmOccurrence dismissal identity changed: ${intent.occurrence.id}',
        );
      }

      final firedAt = row.firedAt ?? intent.requestedAt;
      final effectiveDismissedAt = dismissedAt.isBefore(firedAt)
          ? firedAt
          : dismissedAt;
      final effectiveUpdatedAt = effectiveDismissedAt.isAfter(row.updatedAt)
          ? effectiveDismissedAt
          : row.updatedAt;
      await (_database.update(
        _database.alarmOccurrenceRows,
      )..where((candidate) => candidate.id.equals(intent.occurrence.id))).write(
        AlarmOccurrenceRowsCompanion(
          status: Value(AlarmOccurrenceStatus.dismissed.name),
          platformAlarmId: const Value(null),
          firedAt: Value(firedAt),
          dismissedAt: Value(effectiveDismissedAt),
          dismissalRequestedAt: const Value(null),
          dismissalPlatformAlarmId: const Value(null),
          updatedAt: Value(effectiveUpdatedAt),
        ),
      );
    });
  }

  Future<AlarmOccurrencePlatformMatchSnapshot>
  fetchAlarmOccurrencesByPlatformAlarmIds(Set<String> platformAlarmIds) async {
    if (platformAlarmIds.isEmpty) {
      return AlarmOccurrencePlatformMatchSnapshot(
        occurrences: const [],
        corruptPlatformAlarmIds: const {},
      );
    }
    final rows =
        await (_database.select(_database.alarmOccurrenceRows)
              ..where((row) => row.platformAlarmId.isIn(platformAlarmIds))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    final occurrences = <AlarmOccurrence>[];
    final corruptPlatformAlarmIds = <String>{};
    for (final row in rows) {
      final occurrence = _tryAlarmOccurrenceFromRow(row);
      if (occurrence == null) {
        final platformAlarmId = row.platformAlarmId;
        if (platformAlarmId != null) {
          corruptPlatformAlarmIds.add(platformAlarmId);
        }
      } else {
        occurrences.add(occurrence);
      }
    }
    return AlarmOccurrencePlatformMatchSnapshot(
      occurrences: occurrences,
      corruptPlatformAlarmIds: corruptPlatformAlarmIds,
    );
  }

  Future<List<AlarmOccurrence>> fetchOccurrencesForPlan(
    String wakePlanId,
  ) async {
    final rows =
        await (_database.select(_database.alarmOccurrenceRows)
              ..where((row) => row.wakePlanId.equals(wakePlanId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.scheduledAtDays),
                (row) => OrderingTerm.asc(row.scheduledAtMinutes),
              ]))
            .get();

    return rows
        .map(_tryAlarmOccurrenceFromRow)
        .whereType<AlarmOccurrence>()
        .toList(growable: false);
  }

  Future<WakePlanReconciliationSnapshot> fetchReconciliationSnapshot({
    required DateTime now,
  }) async {
    return _database.transaction(() async {
      final planRows = await (_database.select(
        _database.wakePlanRows,
      )..orderBy([(row) => OrderingTerm.asc(row.targetTimeMinutes)])).get();
      final occurrenceRows =
          await (_database.select(_database.alarmOccurrenceRows)..orderBy([
                (row) => OrderingTerm.asc(row.wakePlanId),
                (row) => OrderingTerm.asc(row.scheduledAtDays),
                (row) => OrderingTerm.asc(row.scheduledAtMinutes),
              ]))
              .get();

      final plans = <WakePlan>[];
      final corruptPlanIds = <String>{};
      final expiredOneTimePlanIds = <String>{};
      for (final row in planRows) {
        final plan = _tryWakePlanFromRow(row);
        if (plan == null) {
          corruptPlanIds.add(row.id);
        } else if (_isExpiredOneTimePlan(plan: plan, now: now)) {
          expiredOneTimePlanIds.add(plan.id);
        } else {
          plans.add(plan);
        }
      }

      final occurrences = <AlarmOccurrence>[];
      final corruptOccurrenceIds = <String>{};
      final corruptOccurrenceWakePlanIds = <String>{};
      for (final row in occurrenceRows) {
        if (expiredOneTimePlanIds.contains(row.wakePlanId)) {
          continue;
        }
        final occurrence = _tryAlarmOccurrenceFromRow(row);
        if (occurrence == null) {
          corruptOccurrenceIds.add(row.id);
          corruptOccurrenceWakePlanIds.add(row.wakePlanId);
        } else {
          occurrences.add(occurrence);
        }
      }

      return WakePlanReconciliationSnapshot(
        plans: plans,
        occurrences: occurrences,
        corruptPlanIds: corruptPlanIds,
        corruptOccurrenceIds: corruptOccurrenceIds,
        corruptOccurrenceWakePlanIds: corruptOccurrenceWakePlanIds,
      );
    });
  }

  Future<List<AlarmOccurrence>> fetchOccurrencesForCalendarRange({
    required CalendarDay start,
    required CalendarDay end,
  }) async {
    if (end.compareTo(start) < 0) {
      throw ArgumentError.value(end, 'end', 'must not be before start');
    }

    final rows =
        await (_database.select(_database.alarmOccurrenceRows)
              ..where(
                (row) =>
                    row.scheduledAtDays.isBiggerOrEqualValue(
                      start.daysSinceUnixEpoch,
                    ) &
                    row.scheduledAtDays.isSmallerOrEqualValue(
                      end.daysSinceUnixEpoch,
                    ),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.scheduledAtDays),
                (row) => OrderingTerm.asc(row.scheduledAtMinutes),
              ]))
            .get();

    return rows
        .map(_tryAlarmOccurrenceFromRow)
        .whereType<AlarmOccurrence>()
        .toList(growable: false);
  }

  Future<List<AlarmOccurrence>> fetchReservedOccurrencesForPlan(
    String wakePlanId,
  ) async {
    final rows =
        await (_database.select(_database.alarmOccurrenceRows)
              ..where((row) => row.wakePlanId.equals(wakePlanId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.scheduledAtDays),
                (row) => OrderingTerm.asc(row.scheduledAtMinutes),
              ]))
            .get();

    return rows
        .map(_tryAlarmOccurrenceFromRow)
        .whereType<AlarmOccurrence>()
        .where(
          (occurrence) => switch (occurrence.status) {
            AlarmOccurrenceStatus.scheduled ||
            AlarmOccurrenceStatus.ringing => occurrence.hasNativeReservation,
            AlarmOccurrenceStatus.userDisablePending ||
            AlarmOccurrenceStatus.userEnablePending ||
            AlarmOccurrenceStatus.unknownPersisted => true,
            _ => false,
          },
        )
        .toList(growable: false);
  }

  Future<void> updateOccurrencePlatformAlarmId({
    required String occurrenceId,
    required String? platformAlarmId,
    required DateTime updatedAt,
  }) async {
    if (platformAlarmId != null && platformAlarmId.trim().isEmpty) {
      throw ArgumentError.value(
        platformAlarmId,
        'platformAlarmId',
        'must be null or non-blank',
      );
    }

    final rowsUpdated =
        await (_database.update(
          _database.alarmOccurrenceRows,
        )..where((row) => row.id.equals(occurrenceId))).write(
          AlarmOccurrenceRowsCompanion(
            platformAlarmId: Value(platformAlarmId),
            updatedAt: Value(updatedAt),
          ),
        );
    if (rowsUpdated == 0) {
      throw StateError('AlarmOccurrence not found: $occurrenceId');
    }
  }

  Future<void> saveAppSettings(AppSettings settings) {
    return _database
        .into(_database.appSettingsRows)
        .insertOnConflictUpdate(_appSettingsCompanion(settings));
  }

  Future<AppSettings?> fetchAppSettings() async {
    final row = await (_database.select(
      _database.appSettingsRows,
    )..where((row) => row.id.equals(_appSettingsId))).getSingleOrNull();

    return row == null ? null : _tryAppSettingsFromRow(row);
  }

  Future<AppSettings> fetchEffectiveAppSettings() async {
    return await fetchAppSettings() ?? AppSettings.initial();
  }

  Expression<bool> _notExpiredOneTimeExpression(
    $WakePlanRowsTable row,
    DateTime now,
  ) {
    final retentionThreshold = now.subtract(oneTimeHistoryRetention);
    final thresholdDay = CalendarDay.fromDateTime(
      retentionThreshold,
    ).daysSinceUnixEpoch;
    final thresholdTime = TimeOfDayMinutes.fromDateTime(
      retentionThreshold,
    ).minutesSinceMidnight;

    final expiredOneTime =
        row.repeatType.equals(RepeatType.oneTime.name) &
        (row.oneTimeDateDays.isSmallerThanValue(thresholdDay) |
            (row.oneTimeDateDays.equals(thresholdDay) &
                row.targetTimeMinutes.isSmallerOrEqualValue(thresholdTime)));

    return expiredOneTime.not();
  }

  bool _isExpiredOneTimePlan({required WakePlan plan, required DateTime now}) {
    if (plan.repeatRule.type != RepeatType.oneTime) {
      return false;
    }
    final oneTimeDate = plan.repeatRule.oneTimeDate;
    if (oneTimeDate == null) {
      return false;
    }

    final finalAlarmAt = plan.targetAt(oneTimeDate);
    return !now.isBefore(finalAlarmAt.add(oneTimeHistoryRetention));
  }

  bool _planIntersectsRange(WakePlan plan, CalendarDay start, CalendarDay end) {
    switch (plan.repeatRule.type) {
      case RepeatType.oneTime:
        final oneTimeDate = plan.repeatRule.oneTimeDate;
        return oneTimeDate != null &&
            oneTimeDate.compareTo(start) >= 0 &&
            oneTimeDate.compareTo(end) <= 0;
      case RepeatType.weekly:
        for (var day = start; day.compareTo(end) <= 0; day = day.addDays(1)) {
          if (plan.repeatRule.includes(day)) {
            return true;
          }
        }
        return false;
    }
  }

  WakePlanRowsCompanion _wakePlanCompanion(WakePlan plan) {
    return WakePlanRowsCompanion.insert(
      id: plan.id,
      title: plan.title,
      targetTimeMinutes: plan.targetTime.minutesSinceMidnight,
      startOffsetMinutes: plan.startOffset.inMinutes,
      intervalMinutes: plan.interval.inMinutes,
      repeatType: plan.repeatRule.type.name,
      oneTimeDateDays: Value(plan.repeatRule.oneTimeDate?.daysSinceUnixEpoch),
      weekdaysMask: Value(_encodeWeekdays(plan.repeatRule.weekdays)),
      isEnabled: plan.isEnabled,
      status: plan.status.name,
      skipNextDateDays: Value(plan.skipNextDate?.daysSinceUnixEpoch),
      soundId: plan.soundId,
      vibrationEnabled: plan.vibrationEnabled,
      createdAt: plan.createdAt,
      updatedAt: plan.updatedAt,
    );
  }

  WakePlan _wakePlanFromRow(WakePlanRow row) {
    return WakePlan(
      id: row.id,
      title: row.title,
      targetTime: TimeOfDayMinutes.fromMinutesSinceMidnight(
        row.targetTimeMinutes,
      ),
      startOffset: Duration(minutes: row.startOffsetMinutes),
      interval: Duration(minutes: row.intervalMinutes),
      repeatRule: _repeatRuleFromRow(row),
      isEnabled: row.isEnabled,
      status: WakePlanStatus.values.byName(row.status),
      skipNextDate: _calendarDayFromEpochDays(row.skipNextDateDays),
      soundId: row.soundId,
      vibrationEnabled: row.vibrationEnabled,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  WakePlan? _tryWakePlanFromRow(WakePlanRow row) {
    try {
      return _wakePlanFromRow(row);
    } on StateError {
      return null;
    } on RangeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  RepeatRule _repeatRuleFromRow(WakePlanRow row) {
    final repeatType = RepeatType.values.byName(row.repeatType);
    return switch (repeatType) {
      RepeatType.oneTime => RepeatRule.oneTime(
        _requiredCalendarDayFromEpochDays(
          row.oneTimeDateDays,
          row.id,
          'oneTimeDateDays',
        ),
      ),
      RepeatType.weekly => RepeatRule.weekly(
        _requiredWeekdaysFromMask(row.weekdaysMask, row.id),
      ),
    };
  }

  AlarmOccurrenceRowsCompanion _alarmOccurrenceCompanion(
    AlarmOccurrence occurrence,
  ) {
    return AlarmOccurrenceRowsCompanion.insert(
      id: occurrence.id,
      wakePlanId: occurrence.wakePlanId,
      scheduledAtDays: occurrence.scheduledAt.day.daysSinceUnixEpoch,
      scheduledAtMinutes: occurrence.scheduledAt.time.minutesSinceMidnight,
      status: occurrence.status.name,
      platformAlarmId: Value(occurrence.platformAlarmId),
      firedAt: Value(occurrence.firedAt),
      dismissedAt: Value(occurrence.dismissedAt),
      failureReason: Value(occurrence.failureReason),
      createdAt: occurrence.createdAt,
      updatedAt: occurrence.updatedAt,
    );
  }

  AlarmOccurrence _alarmOccurrenceFromRow(AlarmOccurrenceRow row) {
    return AlarmOccurrence(
      id: row.id,
      wakePlanId: row.wakePlanId,
      scheduledAt: DateMinute(
        day: _calendarDayFromEpochDays(row.scheduledAtDays)!,
        time: TimeOfDayMinutes.fromMinutesSinceMidnight(row.scheduledAtMinutes),
      ),
      status: _decodeAlarmOccurrenceStatus(row.status),
      platformAlarmId: row.platformAlarmId,
      firedAt: row.firedAt,
      dismissedAt: row.dismissedAt,
      failureReason: row.failureReason,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  AlarmOccurrence? _tryAlarmOccurrenceFromRow(AlarmOccurrenceRow row) {
    try {
      return _alarmOccurrenceFromRow(row);
    } on StateError {
      return null;
    } on RangeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  AlarmOccurrenceDismissalIntent? _dismissalIntentFromRow(
    AlarmOccurrenceRow row,
  ) {
    final requestedAt = row.dismissalRequestedAt;
    final occurrence = _tryAlarmOccurrenceFromRow(row);
    if (requestedAt == null || occurrence == null) {
      return null;
    }
    return AlarmOccurrenceDismissalIntent(
      occurrence: occurrence,
      requestedAt: requestedAt,
      platformAlarmId: row.dismissalPlatformAlarmId,
    );
  }

  AlarmOccurrenceStatus _decodeAlarmOccurrenceStatus(String value) {
    for (final status in AlarmOccurrenceStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
    return AlarmOccurrenceStatus.unknownPersisted;
  }

  AppSettingsRowsCompanion _appSettingsCompanion(AppSettings settings) {
    return AppSettingsRowsCompanion.insert(
      id: const Value(_appSettingsId),
      defaultStartOffsetMinutes: settings.defaultStartOffset.inMinutes,
      defaultIntervalMinutes: settings.defaultInterval.inMinutes,
      defaultSoundId: settings.defaultSoundId,
      defaultVibrationEnabled: settings.defaultVibrationEnabled,
      defaultRepeatType: settings.defaultRepeatType.name,
      defaultTargetTimeMinutes: Value(
        settings.defaultTargetTime?.minutesSinceMidnight,
      ),
    );
  }

  AppSettings _appSettingsFromRow(AppSettingsRow row) {
    return AppSettings(
      defaultStartOffset: Duration(minutes: row.defaultStartOffsetMinutes),
      defaultInterval: Duration(minutes: row.defaultIntervalMinutes),
      defaultSoundId: row.defaultSoundId,
      defaultVibrationEnabled: row.defaultVibrationEnabled,
      defaultRepeatType: RepeatType.values.byName(row.defaultRepeatType),
      defaultTargetTime: row.defaultTargetTimeMinutes == null
          ? null
          : TimeOfDayMinutes.fromMinutesSinceMidnight(
              row.defaultTargetTimeMinutes!,
            ),
    );
  }

  AppSettings? _tryAppSettingsFromRow(AppSettingsRow row) {
    try {
      return _appSettingsFromRow(row);
    } on StateError {
      return null;
    } on RangeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  CalendarDay? _calendarDayFromEpochDays(int? days) {
    if (days == null) {
      return null;
    }

    return CalendarDay.fromDateTime(
      DateTime.utc(1970).add(Duration(days: days)),
    );
  }

  CalendarDay _requiredCalendarDayFromEpochDays(
    int? days,
    String wakePlanId,
    String fieldName,
  ) {
    final day = _calendarDayFromEpochDays(days);
    if (day == null) {
      throw StateError('Malformed WakePlan $wakePlanId: missing $fieldName');
    }

    return day;
  }

  int? _encodeWeekdays(Set<Weekday> weekdays) {
    if (weekdays.isEmpty) {
      return null;
    }

    var mask = 0;
    for (final weekday in weekdays) {
      mask |= 1 << (weekday.dateTimeValue - 1);
    }
    return mask;
  }

  Set<Weekday> _decodeWeekdays(int mask) {
    return Weekday.values
        .where((weekday) => mask & (1 << (weekday.dateTimeValue - 1)) != 0)
        .toSet();
  }

  Set<Weekday> _requiredWeekdaysFromMask(int? mask, String wakePlanId) {
    if (mask == null) {
      throw StateError('Malformed WakePlan $wakePlanId: missing weekdaysMask');
    }

    final weekdays = _decodeWeekdays(mask);
    if (weekdays.isEmpty) {
      throw StateError('Malformed WakePlan $wakePlanId: empty weekdaysMask');
    }

    return weekdays;
  }
}
