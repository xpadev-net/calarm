import 'package:drift/drift.dart';

part 'wake_plan_database.g.dart';

@DataClassName('WakePlanRow')
class WakePlanRows extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get targetTimeMinutes => integer()();
  IntColumn get startOffsetMinutes => integer()();
  IntColumn get intervalMinutes => integer()();
  TextColumn get repeatType => text()();
  IntColumn get oneTimeDateDays => integer().nullable()();
  IntColumn get weekdaysMask => integer().nullable()();
  BoolColumn get isEnabled => boolean()();
  TextColumn get status => text()();
  BoolColumn get skipHolidays => boolean().withDefault(const Constant(false))();
  IntColumn get repeatUntilDays => integer().nullable()();
  TextColumn get soundId => text()();
  BoolColumn get vibrationEnabled => boolean()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AlarmOccurrenceRow')
@TableIndex(name: 'alarm_occurrence_wake_plan_id', columns: {#wakePlanId})
class AlarmOccurrenceRows extends Table {
  TextColumn get id => text()();
  TextColumn get wakePlanId => text().references(WakePlanRows, #id)();
  IntColumn get scheduledAtDays => integer()();
  IntColumn get scheduledAtMinutes => integer()();
  TextColumn get status => text()();
  TextColumn get platformAlarmId => text().nullable()();
  DateTimeColumn get firedAt => dateTime().nullable()();
  DateTimeColumn get dismissedAt => dateTime().nullable()();
  TextColumn get failureReason => text().nullable()();
  TextColumn get reservationId => text().nullable()();
  IntColumn get reservationGeneration =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get dismissalRequestedAt => dateTime().nullable()();
  TextColumn get dismissalPlatformAlarmId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WakePlanOccurrenceExceptionRow')
@TableIndex(
  name: 'wake_plan_occurrence_exception_wake_plan_id',
  columns: {#wakePlanId},
)
class WakePlanOccurrenceExceptionRows extends Table {
  TextColumn get id => text()();
  TextColumn get wakePlanId => text().references(WakePlanRows, #id)();
  IntColumn get originalDayDays => integer()();
  TextColumn get type => text()();
  IntColumn get movedToDayDays => integer().nullable()();
  IntColumn get movedToTargetTimeMinutes => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AppSettingsRow')
class AppSettingsRows extends Table {
  IntColumn get id => integer()();
  IntColumn get defaultStartOffsetMinutes => integer()();
  IntColumn get defaultIntervalMinutes => integer()();
  TextColumn get defaultSoundId => text()();
  BoolColumn get defaultVibrationEnabled => boolean()();
  TextColumn get defaultRepeatType => text()();
  IntColumn get defaultTargetTimeMinutes => integer().nullable()();
  TextColumn get holidayRegion => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('HolidayCacheRow')
class HolidayCacheRows extends Table {
  TextColumn get region => text()();
  IntColumn get dateDays => integer()();
  TextColumn get name => text()();

  @override
  Set<Column<Object>> get primaryKey => {region, dateDays};
}

@DataClassName('HolidayFetchMetadataRow')
class HolidayFetchMetadataRows extends Table {
  TextColumn get region => text()();
  DateTimeColumn get lastFetchedAt => dateTime().nullable()();
  DateTimeColumn get lastSuccessAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {region};
}

@DriftDatabase(
  tables: [
    WakePlanRows,
    AlarmOccurrenceRows,
    WakePlanOccurrenceExceptionRows,
    AppSettingsRows,
    HolidayCacheRows,
    HolidayFetchMetadataRows,
  ],
)
class WakePlanDatabase extends _$WakePlanDatabase {
  WakePlanDatabase(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) => migrator.createAll(),
      onUpgrade: (migrator, from, to) async {
        if (from < 1) {
          await migrator.createAll();
          return;
        }
        if (from < 2) {
          final existingColumns = await customSelect(
            'PRAGMA table_info(alarm_occurrence_rows)',
          ).get();
          final existingColumnNames = existingColumns
              .map((row) => row.read<String>('name'))
              .toSet();
          if (!existingColumnNames.contains('dismissal_requested_at')) {
            await migrator.addColumn(
              alarmOccurrenceRows,
              alarmOccurrenceRows.dismissalRequestedAt,
            );
          }
          if (!existingColumnNames.contains('dismissal_platform_alarm_id')) {
            await migrator.addColumn(
              alarmOccurrenceRows,
              alarmOccurrenceRows.dismissalPlatformAlarmId,
            );
          }
        }
        if (from < 3) {
          final existingColumns = await customSelect(
            'PRAGMA table_info(alarm_occurrence_rows)',
          ).get();
          final existingColumnNames = existingColumns
              .map((row) => row.read<String>('name'))
              .toSet();
          if (!existingColumnNames.contains('reservation_id')) {
            await migrator.addColumn(
              alarmOccurrenceRows,
              alarmOccurrenceRows.reservationId,
            );
          }
          if (!existingColumnNames.contains('reservation_generation')) {
            await migrator.addColumn(
              alarmOccurrenceRows,
              alarmOccurrenceRows.reservationGeneration,
            );
          }
        }
        if (from < 4) {
          final existingTables = await customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          ).get();
          final existingTableNames = existingTables
              .map((row) => row.read<String>('name'))
              .toSet();

          if (existingTableNames.contains('wake_plan_rows')) {
            final existingWakePlanColumns = await customSelect(
              'PRAGMA table_info(wake_plan_rows)',
            ).get();
            final existingWakePlanColumnNames = existingWakePlanColumns
                .map((row) => row.read<String>('name'))
                .toSet();
            if (!existingWakePlanColumnNames.contains('skip_holidays')) {
              await migrator.addColumn(wakePlanRows, wakePlanRows.skipHolidays);
            }
          }

          if (existingTableNames.contains('app_settings_rows')) {
            final existingAppSettingsColumns = await customSelect(
              'PRAGMA table_info(app_settings_rows)',
            ).get();
            final existingAppSettingsColumnNames = existingAppSettingsColumns
                .map((row) => row.read<String>('name'))
                .toSet();
            if (!existingAppSettingsColumnNames.contains('holiday_region')) {
              await migrator.addColumn(
                appSettingsRows,
                appSettingsRows.holidayRegion,
              );
            }
          }

          if (!existingTableNames.contains('holiday_cache_rows')) {
            await migrator.createTable(holidayCacheRows);
          }
          if (!existingTableNames.contains('holiday_fetch_metadata_rows')) {
            await migrator.createTable(holidayFetchMetadataRows);
          }
        }
        if (from < 5) {
          final existingTables = await customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          ).get();
          final existingTableNames = existingTables
              .map((row) => row.read<String>('name'))
              .toSet();

          if (existingTableNames.contains('wake_plan_rows')) {
            final existingWakePlanColumns = await customSelect(
              'PRAGMA table_info(wake_plan_rows)',
            ).get();
            final existingWakePlanColumnNames = existingWakePlanColumns
                .map((row) => row.read<String>('name'))
                .toSet();
            if (!existingWakePlanColumnNames.contains('repeat_until_days')) {
              await migrator.addColumn(
                wakePlanRows,
                wakePlanRows.repeatUntilDays,
              );
            }

            if (!existingTableNames.contains(
              'wake_plan_occurrence_exception_rows',
            )) {
              await migrator.createTable(wakePlanOccurrenceExceptionRows);
            }

            if (existingWakePlanColumnNames.contains('skip_next_date_days')) {
              final skippedPlans = await customSelect(
                'SELECT id, skip_next_date_days FROM wake_plan_rows '
                'WHERE skip_next_date_days IS NOT NULL',
              ).get();
              final now = DateTime.now();
              for (final row in skippedPlans) {
                final wakePlanId = row.read<String>('id');
                final originalDayDays = row.read<int>('skip_next_date_days');
                await into(
                  wakePlanOccurrenceExceptionRows,
                ).insertOnConflictUpdate(
                  WakePlanOccurrenceExceptionRowsCompanion.insert(
                    id: '$wakePlanId:$originalDayDays',
                    wakePlanId: wakePlanId,
                    originalDayDays: originalDayDays,
                    type: 'skipped',
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
              }
            }
          } else if (!existingTableNames.contains(
            'wake_plan_occurrence_exception_rows',
          )) {
            await migrator.createTable(wakePlanOccurrenceExceptionRows);
          }
        }
      },
    );
  }
}
