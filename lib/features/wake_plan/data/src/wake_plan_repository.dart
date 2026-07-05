import 'package:drift/drift.dart';

import '../../../../core/time/time.dart';
import '../../domain/wake_plan_domain.dart';
import 'wake_plan_database.dart';

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

    final plan = _wakePlanFromRow(row);
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
    final rows = await (_database.select(
      _database.wakePlanRows,
    )..orderBy([(row) => OrderingTerm.asc(row.targetTimeMinutes)])).get();

    return rows
        .map(_wakePlanFromRow)
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

    final rows = await _database.select(_database.wakePlanRows).get();
    return rows
        .map(_wakePlanFromRow)
        .where((plan) => includeDeleted || !plan.isDeleted)
        .where((plan) => includeDisabled || plan.isEnabled)
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

    return row == null ? null : _alarmOccurrenceFromRow(row);
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

    return rows.map(_alarmOccurrenceFromRow).toList(growable: false);
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

    return rows.map(_alarmOccurrenceFromRow).toList(growable: false);
  }

  Future<List<AlarmOccurrence>> fetchReservedOccurrencesForPlan(
    String wakePlanId,
  ) async {
    final rows =
        await (_database.select(_database.alarmOccurrenceRows)
              ..where(
                (row) =>
                    row.wakePlanId.equals(wakePlanId) &
                    row.platformAlarmId.isNotNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.scheduledAtDays),
                (row) => OrderingTerm.asc(row.scheduledAtMinutes),
              ]))
            .get();

    return rows.map(_alarmOccurrenceFromRow).toList(growable: false);
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

    return row == null ? null : _appSettingsFromRow(row);
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

  RepeatRule _repeatRuleFromRow(WakePlanRow row) {
    final repeatType = RepeatType.values.byName(row.repeatType);
    return switch (repeatType) {
      RepeatType.oneTime => RepeatRule.oneTime(
        _calendarDayFromEpochDays(row.oneTimeDateDays)!,
      ),
      RepeatType.weekly => RepeatRule.weekly(
        _decodeWeekdays(row.weekdaysMask ?? 0),
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
      status: AlarmOccurrenceStatus.values.byName(row.status),
      platformAlarmId: row.platformAlarmId,
      firedAt: row.firedAt,
      dismissedAt: row.dismissedAt,
      failureReason: row.failureReason,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
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

  CalendarDay? _calendarDayFromEpochDays(int? days) {
    if (days == null) {
      return null;
    }

    return CalendarDay.fromDateTime(
      DateTime.utc(1970).add(Duration(days: days)),
    );
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
}
