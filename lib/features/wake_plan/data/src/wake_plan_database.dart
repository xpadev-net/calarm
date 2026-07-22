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
  IntColumn get skipNextDateDays => integer().nullable()();
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
  DateTimeColumn get dismissalRequestedAt => dateTime().nullable()();
  TextColumn get dismissalPlatformAlarmId => text().nullable()();
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

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [WakePlanRows, AlarmOccurrenceRows, AppSettingsRows])
class WakePlanDatabase extends _$WakePlanDatabase {
  WakePlanDatabase(super.executor);

  @override
  int get schemaVersion => 2;

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
          await migrator.addColumn(
            alarmOccurrenceRows,
            alarmOccurrenceRows.dismissalRequestedAt,
          );
          await migrator.addColumn(
            alarmOccurrenceRows,
            alarmOccurrenceRows.dismissalPlatformAlarmId,
          );
        }
      },
    );
  }
}
