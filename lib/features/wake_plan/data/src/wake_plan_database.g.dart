// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wake_plan_database.dart';

// ignore_for_file: type=lint
class $WakePlanRowsTable extends WakePlanRows
    with TableInfo<$WakePlanRowsTable, WakePlanRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WakePlanRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetTimeMinutesMeta = const VerificationMeta(
    'targetTimeMinutes',
  );
  @override
  late final GeneratedColumn<int> targetTimeMinutes = GeneratedColumn<int>(
    'target_time_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startOffsetMinutesMeta =
      const VerificationMeta('startOffsetMinutes');
  @override
  late final GeneratedColumn<int> startOffsetMinutes = GeneratedColumn<int>(
    'start_offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intervalMinutesMeta = const VerificationMeta(
    'intervalMinutes',
  );
  @override
  late final GeneratedColumn<int> intervalMinutes = GeneratedColumn<int>(
    'interval_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repeatTypeMeta = const VerificationMeta(
    'repeatType',
  );
  @override
  late final GeneratedColumn<String> repeatType = GeneratedColumn<String>(
    'repeat_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _oneTimeDateDaysMeta = const VerificationMeta(
    'oneTimeDateDays',
  );
  @override
  late final GeneratedColumn<int> oneTimeDateDays = GeneratedColumn<int>(
    'one_time_date_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weekdaysMaskMeta = const VerificationMeta(
    'weekdaysMask',
  );
  @override
  late final GeneratedColumn<int> weekdaysMask = GeneratedColumn<int>(
    'weekdays_mask',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isEnabledMeta = const VerificationMeta(
    'isEnabled',
  );
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
    'is_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _skipNextDateDaysMeta = const VerificationMeta(
    'skipNextDateDays',
  );
  @override
  late final GeneratedColumn<int> skipNextDateDays = GeneratedColumn<int>(
    'skip_next_date_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _soundIdMeta = const VerificationMeta(
    'soundId',
  );
  @override
  late final GeneratedColumn<String> soundId = GeneratedColumn<String>(
    'sound_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vibrationEnabledMeta = const VerificationMeta(
    'vibrationEnabled',
  );
  @override
  late final GeneratedColumn<bool> vibrationEnabled = GeneratedColumn<bool>(
    'vibration_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("vibration_enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    targetTimeMinutes,
    startOffsetMinutes,
    intervalMinutes,
    repeatType,
    oneTimeDateDays,
    weekdaysMask,
    isEnabled,
    status,
    skipNextDateDays,
    soundId,
    vibrationEnabled,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wake_plan_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<WakePlanRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('target_time_minutes')) {
      context.handle(
        _targetTimeMinutesMeta,
        targetTimeMinutes.isAcceptableOrUnknown(
          data['target_time_minutes']!,
          _targetTimeMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetTimeMinutesMeta);
    }
    if (data.containsKey('start_offset_minutes')) {
      context.handle(
        _startOffsetMinutesMeta,
        startOffsetMinutes.isAcceptableOrUnknown(
          data['start_offset_minutes']!,
          _startOffsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startOffsetMinutesMeta);
    }
    if (data.containsKey('interval_minutes')) {
      context.handle(
        _intervalMinutesMeta,
        intervalMinutes.isAcceptableOrUnknown(
          data['interval_minutes']!,
          _intervalMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_intervalMinutesMeta);
    }
    if (data.containsKey('repeat_type')) {
      context.handle(
        _repeatTypeMeta,
        repeatType.isAcceptableOrUnknown(data['repeat_type']!, _repeatTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_repeatTypeMeta);
    }
    if (data.containsKey('one_time_date_days')) {
      context.handle(
        _oneTimeDateDaysMeta,
        oneTimeDateDays.isAcceptableOrUnknown(
          data['one_time_date_days']!,
          _oneTimeDateDaysMeta,
        ),
      );
    }
    if (data.containsKey('weekdays_mask')) {
      context.handle(
        _weekdaysMaskMeta,
        weekdaysMask.isAcceptableOrUnknown(
          data['weekdays_mask']!,
          _weekdaysMaskMeta,
        ),
      );
    }
    if (data.containsKey('is_enabled')) {
      context.handle(
        _isEnabledMeta,
        isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta),
      );
    } else if (isInserting) {
      context.missing(_isEnabledMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('skip_next_date_days')) {
      context.handle(
        _skipNextDateDaysMeta,
        skipNextDateDays.isAcceptableOrUnknown(
          data['skip_next_date_days']!,
          _skipNextDateDaysMeta,
        ),
      );
    }
    if (data.containsKey('sound_id')) {
      context.handle(
        _soundIdMeta,
        soundId.isAcceptableOrUnknown(data['sound_id']!, _soundIdMeta),
      );
    } else if (isInserting) {
      context.missing(_soundIdMeta);
    }
    if (data.containsKey('vibration_enabled')) {
      context.handle(
        _vibrationEnabledMeta,
        vibrationEnabled.isAcceptableOrUnknown(
          data['vibration_enabled']!,
          _vibrationEnabledMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_vibrationEnabledMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WakePlanRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WakePlanRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      targetTimeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_time_minutes'],
      )!,
      startOffsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_offset_minutes'],
      )!,
      intervalMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interval_minutes'],
      )!,
      repeatType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repeat_type'],
      )!,
      oneTimeDateDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}one_time_date_days'],
      ),
      weekdaysMask: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekdays_mask'],
      ),
      isEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_enabled'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      skipNextDateDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}skip_next_date_days'],
      ),
      soundId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sound_id'],
      )!,
      vibrationEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}vibration_enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WakePlanRowsTable createAlias(String alias) {
    return $WakePlanRowsTable(attachedDatabase, alias);
  }
}

class WakePlanRow extends DataClass implements Insertable<WakePlanRow> {
  final String id;
  final String title;
  final int targetTimeMinutes;
  final int startOffsetMinutes;
  final int intervalMinutes;
  final String repeatType;
  final int? oneTimeDateDays;
  final int? weekdaysMask;
  final bool isEnabled;
  final String status;
  final int? skipNextDateDays;
  final String soundId;
  final bool vibrationEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const WakePlanRow({
    required this.id,
    required this.title,
    required this.targetTimeMinutes,
    required this.startOffsetMinutes,
    required this.intervalMinutes,
    required this.repeatType,
    this.oneTimeDateDays,
    this.weekdaysMask,
    required this.isEnabled,
    required this.status,
    this.skipNextDateDays,
    required this.soundId,
    required this.vibrationEnabled,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['target_time_minutes'] = Variable<int>(targetTimeMinutes);
    map['start_offset_minutes'] = Variable<int>(startOffsetMinutes);
    map['interval_minutes'] = Variable<int>(intervalMinutes);
    map['repeat_type'] = Variable<String>(repeatType);
    if (!nullToAbsent || oneTimeDateDays != null) {
      map['one_time_date_days'] = Variable<int>(oneTimeDateDays);
    }
    if (!nullToAbsent || weekdaysMask != null) {
      map['weekdays_mask'] = Variable<int>(weekdaysMask);
    }
    map['is_enabled'] = Variable<bool>(isEnabled);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || skipNextDateDays != null) {
      map['skip_next_date_days'] = Variable<int>(skipNextDateDays);
    }
    map['sound_id'] = Variable<String>(soundId);
    map['vibration_enabled'] = Variable<bool>(vibrationEnabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WakePlanRowsCompanion toCompanion(bool nullToAbsent) {
    return WakePlanRowsCompanion(
      id: Value(id),
      title: Value(title),
      targetTimeMinutes: Value(targetTimeMinutes),
      startOffsetMinutes: Value(startOffsetMinutes),
      intervalMinutes: Value(intervalMinutes),
      repeatType: Value(repeatType),
      oneTimeDateDays: oneTimeDateDays == null && nullToAbsent
          ? const Value.absent()
          : Value(oneTimeDateDays),
      weekdaysMask: weekdaysMask == null && nullToAbsent
          ? const Value.absent()
          : Value(weekdaysMask),
      isEnabled: Value(isEnabled),
      status: Value(status),
      skipNextDateDays: skipNextDateDays == null && nullToAbsent
          ? const Value.absent()
          : Value(skipNextDateDays),
      soundId: Value(soundId),
      vibrationEnabled: Value(vibrationEnabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory WakePlanRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WakePlanRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      targetTimeMinutes: serializer.fromJson<int>(json['targetTimeMinutes']),
      startOffsetMinutes: serializer.fromJson<int>(json['startOffsetMinutes']),
      intervalMinutes: serializer.fromJson<int>(json['intervalMinutes']),
      repeatType: serializer.fromJson<String>(json['repeatType']),
      oneTimeDateDays: serializer.fromJson<int?>(json['oneTimeDateDays']),
      weekdaysMask: serializer.fromJson<int?>(json['weekdaysMask']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      status: serializer.fromJson<String>(json['status']),
      skipNextDateDays: serializer.fromJson<int?>(json['skipNextDateDays']),
      soundId: serializer.fromJson<String>(json['soundId']),
      vibrationEnabled: serializer.fromJson<bool>(json['vibrationEnabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'targetTimeMinutes': serializer.toJson<int>(targetTimeMinutes),
      'startOffsetMinutes': serializer.toJson<int>(startOffsetMinutes),
      'intervalMinutes': serializer.toJson<int>(intervalMinutes),
      'repeatType': serializer.toJson<String>(repeatType),
      'oneTimeDateDays': serializer.toJson<int?>(oneTimeDateDays),
      'weekdaysMask': serializer.toJson<int?>(weekdaysMask),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'status': serializer.toJson<String>(status),
      'skipNextDateDays': serializer.toJson<int?>(skipNextDateDays),
      'soundId': serializer.toJson<String>(soundId),
      'vibrationEnabled': serializer.toJson<bool>(vibrationEnabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WakePlanRow copyWith({
    String? id,
    String? title,
    int? targetTimeMinutes,
    int? startOffsetMinutes,
    int? intervalMinutes,
    String? repeatType,
    Value<int?> oneTimeDateDays = const Value.absent(),
    Value<int?> weekdaysMask = const Value.absent(),
    bool? isEnabled,
    String? status,
    Value<int?> skipNextDateDays = const Value.absent(),
    String? soundId,
    bool? vibrationEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WakePlanRow(
    id: id ?? this.id,
    title: title ?? this.title,
    targetTimeMinutes: targetTimeMinutes ?? this.targetTimeMinutes,
    startOffsetMinutes: startOffsetMinutes ?? this.startOffsetMinutes,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    repeatType: repeatType ?? this.repeatType,
    oneTimeDateDays: oneTimeDateDays.present
        ? oneTimeDateDays.value
        : this.oneTimeDateDays,
    weekdaysMask: weekdaysMask.present ? weekdaysMask.value : this.weekdaysMask,
    isEnabled: isEnabled ?? this.isEnabled,
    status: status ?? this.status,
    skipNextDateDays: skipNextDateDays.present
        ? skipNextDateDays.value
        : this.skipNextDateDays,
    soundId: soundId ?? this.soundId,
    vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WakePlanRow copyWithCompanion(WakePlanRowsCompanion data) {
    return WakePlanRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      targetTimeMinutes: data.targetTimeMinutes.present
          ? data.targetTimeMinutes.value
          : this.targetTimeMinutes,
      startOffsetMinutes: data.startOffsetMinutes.present
          ? data.startOffsetMinutes.value
          : this.startOffsetMinutes,
      intervalMinutes: data.intervalMinutes.present
          ? data.intervalMinutes.value
          : this.intervalMinutes,
      repeatType: data.repeatType.present
          ? data.repeatType.value
          : this.repeatType,
      oneTimeDateDays: data.oneTimeDateDays.present
          ? data.oneTimeDateDays.value
          : this.oneTimeDateDays,
      weekdaysMask: data.weekdaysMask.present
          ? data.weekdaysMask.value
          : this.weekdaysMask,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      status: data.status.present ? data.status.value : this.status,
      skipNextDateDays: data.skipNextDateDays.present
          ? data.skipNextDateDays.value
          : this.skipNextDateDays,
      soundId: data.soundId.present ? data.soundId.value : this.soundId,
      vibrationEnabled: data.vibrationEnabled.present
          ? data.vibrationEnabled.value
          : this.vibrationEnabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WakePlanRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('targetTimeMinutes: $targetTimeMinutes, ')
          ..write('startOffsetMinutes: $startOffsetMinutes, ')
          ..write('intervalMinutes: $intervalMinutes, ')
          ..write('repeatType: $repeatType, ')
          ..write('oneTimeDateDays: $oneTimeDateDays, ')
          ..write('weekdaysMask: $weekdaysMask, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('status: $status, ')
          ..write('skipNextDateDays: $skipNextDateDays, ')
          ..write('soundId: $soundId, ')
          ..write('vibrationEnabled: $vibrationEnabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    targetTimeMinutes,
    startOffsetMinutes,
    intervalMinutes,
    repeatType,
    oneTimeDateDays,
    weekdaysMask,
    isEnabled,
    status,
    skipNextDateDays,
    soundId,
    vibrationEnabled,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WakePlanRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.targetTimeMinutes == this.targetTimeMinutes &&
          other.startOffsetMinutes == this.startOffsetMinutes &&
          other.intervalMinutes == this.intervalMinutes &&
          other.repeatType == this.repeatType &&
          other.oneTimeDateDays == this.oneTimeDateDays &&
          other.weekdaysMask == this.weekdaysMask &&
          other.isEnabled == this.isEnabled &&
          other.status == this.status &&
          other.skipNextDateDays == this.skipNextDateDays &&
          other.soundId == this.soundId &&
          other.vibrationEnabled == this.vibrationEnabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class WakePlanRowsCompanion extends UpdateCompanion<WakePlanRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<int> targetTimeMinutes;
  final Value<int> startOffsetMinutes;
  final Value<int> intervalMinutes;
  final Value<String> repeatType;
  final Value<int?> oneTimeDateDays;
  final Value<int?> weekdaysMask;
  final Value<bool> isEnabled;
  final Value<String> status;
  final Value<int?> skipNextDateDays;
  final Value<String> soundId;
  final Value<bool> vibrationEnabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const WakePlanRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.targetTimeMinutes = const Value.absent(),
    this.startOffsetMinutes = const Value.absent(),
    this.intervalMinutes = const Value.absent(),
    this.repeatType = const Value.absent(),
    this.oneTimeDateDays = const Value.absent(),
    this.weekdaysMask = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.status = const Value.absent(),
    this.skipNextDateDays = const Value.absent(),
    this.soundId = const Value.absent(),
    this.vibrationEnabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WakePlanRowsCompanion.insert({
    required String id,
    required String title,
    required int targetTimeMinutes,
    required int startOffsetMinutes,
    required int intervalMinutes,
    required String repeatType,
    this.oneTimeDateDays = const Value.absent(),
    this.weekdaysMask = const Value.absent(),
    required bool isEnabled,
    required String status,
    this.skipNextDateDays = const Value.absent(),
    required String soundId,
    required bool vibrationEnabled,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       targetTimeMinutes = Value(targetTimeMinutes),
       startOffsetMinutes = Value(startOffsetMinutes),
       intervalMinutes = Value(intervalMinutes),
       repeatType = Value(repeatType),
       isEnabled = Value(isEnabled),
       status = Value(status),
       soundId = Value(soundId),
       vibrationEnabled = Value(vibrationEnabled),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<WakePlanRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<int>? targetTimeMinutes,
    Expression<int>? startOffsetMinutes,
    Expression<int>? intervalMinutes,
    Expression<String>? repeatType,
    Expression<int>? oneTimeDateDays,
    Expression<int>? weekdaysMask,
    Expression<bool>? isEnabled,
    Expression<String>? status,
    Expression<int>? skipNextDateDays,
    Expression<String>? soundId,
    Expression<bool>? vibrationEnabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (targetTimeMinutes != null) 'target_time_minutes': targetTimeMinutes,
      if (startOffsetMinutes != null)
        'start_offset_minutes': startOffsetMinutes,
      if (intervalMinutes != null) 'interval_minutes': intervalMinutes,
      if (repeatType != null) 'repeat_type': repeatType,
      if (oneTimeDateDays != null) 'one_time_date_days': oneTimeDateDays,
      if (weekdaysMask != null) 'weekdays_mask': weekdaysMask,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (status != null) 'status': status,
      if (skipNextDateDays != null) 'skip_next_date_days': skipNextDateDays,
      if (soundId != null) 'sound_id': soundId,
      if (vibrationEnabled != null) 'vibration_enabled': vibrationEnabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WakePlanRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<int>? targetTimeMinutes,
    Value<int>? startOffsetMinutes,
    Value<int>? intervalMinutes,
    Value<String>? repeatType,
    Value<int?>? oneTimeDateDays,
    Value<int?>? weekdaysMask,
    Value<bool>? isEnabled,
    Value<String>? status,
    Value<int?>? skipNextDateDays,
    Value<String>? soundId,
    Value<bool>? vibrationEnabled,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return WakePlanRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      targetTimeMinutes: targetTimeMinutes ?? this.targetTimeMinutes,
      startOffsetMinutes: startOffsetMinutes ?? this.startOffsetMinutes,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      repeatType: repeatType ?? this.repeatType,
      oneTimeDateDays: oneTimeDateDays ?? this.oneTimeDateDays,
      weekdaysMask: weekdaysMask ?? this.weekdaysMask,
      isEnabled: isEnabled ?? this.isEnabled,
      status: status ?? this.status,
      skipNextDateDays: skipNextDateDays ?? this.skipNextDateDays,
      soundId: soundId ?? this.soundId,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (targetTimeMinutes.present) {
      map['target_time_minutes'] = Variable<int>(targetTimeMinutes.value);
    }
    if (startOffsetMinutes.present) {
      map['start_offset_minutes'] = Variable<int>(startOffsetMinutes.value);
    }
    if (intervalMinutes.present) {
      map['interval_minutes'] = Variable<int>(intervalMinutes.value);
    }
    if (repeatType.present) {
      map['repeat_type'] = Variable<String>(repeatType.value);
    }
    if (oneTimeDateDays.present) {
      map['one_time_date_days'] = Variable<int>(oneTimeDateDays.value);
    }
    if (weekdaysMask.present) {
      map['weekdays_mask'] = Variable<int>(weekdaysMask.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (skipNextDateDays.present) {
      map['skip_next_date_days'] = Variable<int>(skipNextDateDays.value);
    }
    if (soundId.present) {
      map['sound_id'] = Variable<String>(soundId.value);
    }
    if (vibrationEnabled.present) {
      map['vibration_enabled'] = Variable<bool>(vibrationEnabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WakePlanRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('targetTimeMinutes: $targetTimeMinutes, ')
          ..write('startOffsetMinutes: $startOffsetMinutes, ')
          ..write('intervalMinutes: $intervalMinutes, ')
          ..write('repeatType: $repeatType, ')
          ..write('oneTimeDateDays: $oneTimeDateDays, ')
          ..write('weekdaysMask: $weekdaysMask, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('status: $status, ')
          ..write('skipNextDateDays: $skipNextDateDays, ')
          ..write('soundId: $soundId, ')
          ..write('vibrationEnabled: $vibrationEnabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlarmOccurrenceRowsTable extends AlarmOccurrenceRows
    with TableInfo<$AlarmOccurrenceRowsTable, AlarmOccurrenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlarmOccurrenceRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wakePlanIdMeta = const VerificationMeta(
    'wakePlanId',
  );
  @override
  late final GeneratedColumn<String> wakePlanId = GeneratedColumn<String>(
    'wake_plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES wake_plan_rows (id)',
    ),
  );
  static const VerificationMeta _scheduledAtDaysMeta = const VerificationMeta(
    'scheduledAtDays',
  );
  @override
  late final GeneratedColumn<int> scheduledAtDays = GeneratedColumn<int>(
    'scheduled_at_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledAtMinutesMeta =
      const VerificationMeta('scheduledAtMinutes');
  @override
  late final GeneratedColumn<int> scheduledAtMinutes = GeneratedColumn<int>(
    'scheduled_at_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformAlarmIdMeta = const VerificationMeta(
    'platformAlarmId',
  );
  @override
  late final GeneratedColumn<String> platformAlarmId = GeneratedColumn<String>(
    'platform_alarm_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firedAtMeta = const VerificationMeta(
    'firedAt',
  );
  @override
  late final GeneratedColumn<DateTime> firedAt = GeneratedColumn<DateTime>(
    'fired_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dismissedAtMeta = const VerificationMeta(
    'dismissedAt',
  );
  @override
  late final GeneratedColumn<DateTime> dismissedAt = GeneratedColumn<DateTime>(
    'dismissed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reservationIdMeta = const VerificationMeta(
    'reservationId',
  );
  @override
  late final GeneratedColumn<String> reservationId = GeneratedColumn<String>(
    'reservation_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reservationGenerationMeta =
      const VerificationMeta('reservationGeneration');
  @override
  late final GeneratedColumn<int> reservationGeneration = GeneratedColumn<int>(
    'reservation_generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dismissalRequestedAtMeta =
      const VerificationMeta('dismissalRequestedAt');
  @override
  late final GeneratedColumn<DateTime> dismissalRequestedAt =
      GeneratedColumn<DateTime>(
        'dismissal_requested_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dismissalPlatformAlarmIdMeta =
      const VerificationMeta('dismissalPlatformAlarmId');
  @override
  late final GeneratedColumn<String> dismissalPlatformAlarmId =
      GeneratedColumn<String>(
        'dismissal_platform_alarm_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    wakePlanId,
    scheduledAtDays,
    scheduledAtMinutes,
    status,
    platformAlarmId,
    firedAt,
    dismissedAt,
    failureReason,
    reservationId,
    reservationGeneration,
    dismissalRequestedAt,
    dismissalPlatformAlarmId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alarm_occurrence_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlarmOccurrenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('wake_plan_id')) {
      context.handle(
        _wakePlanIdMeta,
        wakePlanId.isAcceptableOrUnknown(
          data['wake_plan_id']!,
          _wakePlanIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wakePlanIdMeta);
    }
    if (data.containsKey('scheduled_at_days')) {
      context.handle(
        _scheduledAtDaysMeta,
        scheduledAtDays.isAcceptableOrUnknown(
          data['scheduled_at_days']!,
          _scheduledAtDaysMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtDaysMeta);
    }
    if (data.containsKey('scheduled_at_minutes')) {
      context.handle(
        _scheduledAtMinutesMeta,
        scheduledAtMinutes.isAcceptableOrUnknown(
          data['scheduled_at_minutes']!,
          _scheduledAtMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtMinutesMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('platform_alarm_id')) {
      context.handle(
        _platformAlarmIdMeta,
        platformAlarmId.isAcceptableOrUnknown(
          data['platform_alarm_id']!,
          _platformAlarmIdMeta,
        ),
      );
    }
    if (data.containsKey('fired_at')) {
      context.handle(
        _firedAtMeta,
        firedAt.isAcceptableOrUnknown(data['fired_at']!, _firedAtMeta),
      );
    }
    if (data.containsKey('dismissed_at')) {
      context.handle(
        _dismissedAtMeta,
        dismissedAt.isAcceptableOrUnknown(
          data['dismissed_at']!,
          _dismissedAtMeta,
        ),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    if (data.containsKey('reservation_id')) {
      context.handle(
        _reservationIdMeta,
        reservationId.isAcceptableOrUnknown(
          data['reservation_id']!,
          _reservationIdMeta,
        ),
      );
    }
    if (data.containsKey('reservation_generation')) {
      context.handle(
        _reservationGenerationMeta,
        reservationGeneration.isAcceptableOrUnknown(
          data['reservation_generation']!,
          _reservationGenerationMeta,
        ),
      );
    }
    if (data.containsKey('dismissal_requested_at')) {
      context.handle(
        _dismissalRequestedAtMeta,
        dismissalRequestedAt.isAcceptableOrUnknown(
          data['dismissal_requested_at']!,
          _dismissalRequestedAtMeta,
        ),
      );
    }
    if (data.containsKey('dismissal_platform_alarm_id')) {
      context.handle(
        _dismissalPlatformAlarmIdMeta,
        dismissalPlatformAlarmId.isAcceptableOrUnknown(
          data['dismissal_platform_alarm_id']!,
          _dismissalPlatformAlarmIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlarmOccurrenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlarmOccurrenceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      wakePlanId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wake_plan_id'],
      )!,
      scheduledAtDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_at_days'],
      )!,
      scheduledAtMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_at_minutes'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      platformAlarmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform_alarm_id'],
      ),
      firedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fired_at'],
      ),
      dismissedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}dismissed_at'],
      ),
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      reservationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reservation_id'],
      ),
      reservationGeneration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reservation_generation'],
      )!,
      dismissalRequestedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}dismissal_requested_at'],
      ),
      dismissalPlatformAlarmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dismissal_platform_alarm_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AlarmOccurrenceRowsTable createAlias(String alias) {
    return $AlarmOccurrenceRowsTable(attachedDatabase, alias);
  }
}

class AlarmOccurrenceRow extends DataClass
    implements Insertable<AlarmOccurrenceRow> {
  final String id;
  final String wakePlanId;
  final int scheduledAtDays;
  final int scheduledAtMinutes;
  final String status;
  final String? platformAlarmId;
  final DateTime? firedAt;
  final DateTime? dismissedAt;
  final String? failureReason;
  final String? reservationId;
  final int reservationGeneration;
  final DateTime? dismissalRequestedAt;
  final String? dismissalPlatformAlarmId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const AlarmOccurrenceRow({
    required this.id,
    required this.wakePlanId,
    required this.scheduledAtDays,
    required this.scheduledAtMinutes,
    required this.status,
    this.platformAlarmId,
    this.firedAt,
    this.dismissedAt,
    this.failureReason,
    this.reservationId,
    required this.reservationGeneration,
    this.dismissalRequestedAt,
    this.dismissalPlatformAlarmId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['wake_plan_id'] = Variable<String>(wakePlanId);
    map['scheduled_at_days'] = Variable<int>(scheduledAtDays);
    map['scheduled_at_minutes'] = Variable<int>(scheduledAtMinutes);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || platformAlarmId != null) {
      map['platform_alarm_id'] = Variable<String>(platformAlarmId);
    }
    if (!nullToAbsent || firedAt != null) {
      map['fired_at'] = Variable<DateTime>(firedAt);
    }
    if (!nullToAbsent || dismissedAt != null) {
      map['dismissed_at'] = Variable<DateTime>(dismissedAt);
    }
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    if (!nullToAbsent || reservationId != null) {
      map['reservation_id'] = Variable<String>(reservationId);
    }
    map['reservation_generation'] = Variable<int>(reservationGeneration);
    if (!nullToAbsent || dismissalRequestedAt != null) {
      map['dismissal_requested_at'] = Variable<DateTime>(dismissalRequestedAt);
    }
    if (!nullToAbsent || dismissalPlatformAlarmId != null) {
      map['dismissal_platform_alarm_id'] = Variable<String>(
        dismissalPlatformAlarmId,
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AlarmOccurrenceRowsCompanion toCompanion(bool nullToAbsent) {
    return AlarmOccurrenceRowsCompanion(
      id: Value(id),
      wakePlanId: Value(wakePlanId),
      scheduledAtDays: Value(scheduledAtDays),
      scheduledAtMinutes: Value(scheduledAtMinutes),
      status: Value(status),
      platformAlarmId: platformAlarmId == null && nullToAbsent
          ? const Value.absent()
          : Value(platformAlarmId),
      firedAt: firedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(firedAt),
      dismissedAt: dismissedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dismissedAt),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      reservationId: reservationId == null && nullToAbsent
          ? const Value.absent()
          : Value(reservationId),
      reservationGeneration: Value(reservationGeneration),
      dismissalRequestedAt: dismissalRequestedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dismissalRequestedAt),
      dismissalPlatformAlarmId: dismissalPlatformAlarmId == null && nullToAbsent
          ? const Value.absent()
          : Value(dismissalPlatformAlarmId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AlarmOccurrenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlarmOccurrenceRow(
      id: serializer.fromJson<String>(json['id']),
      wakePlanId: serializer.fromJson<String>(json['wakePlanId']),
      scheduledAtDays: serializer.fromJson<int>(json['scheduledAtDays']),
      scheduledAtMinutes: serializer.fromJson<int>(json['scheduledAtMinutes']),
      status: serializer.fromJson<String>(json['status']),
      platformAlarmId: serializer.fromJson<String?>(json['platformAlarmId']),
      firedAt: serializer.fromJson<DateTime?>(json['firedAt']),
      dismissedAt: serializer.fromJson<DateTime?>(json['dismissedAt']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      reservationId: serializer.fromJson<String?>(json['reservationId']),
      reservationGeneration: serializer.fromJson<int>(
        json['reservationGeneration'],
      ),
      dismissalRequestedAt: serializer.fromJson<DateTime?>(
        json['dismissalRequestedAt'],
      ),
      dismissalPlatformAlarmId: serializer.fromJson<String?>(
        json['dismissalPlatformAlarmId'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'wakePlanId': serializer.toJson<String>(wakePlanId),
      'scheduledAtDays': serializer.toJson<int>(scheduledAtDays),
      'scheduledAtMinutes': serializer.toJson<int>(scheduledAtMinutes),
      'status': serializer.toJson<String>(status),
      'platformAlarmId': serializer.toJson<String?>(platformAlarmId),
      'firedAt': serializer.toJson<DateTime?>(firedAt),
      'dismissedAt': serializer.toJson<DateTime?>(dismissedAt),
      'failureReason': serializer.toJson<String?>(failureReason),
      'reservationId': serializer.toJson<String?>(reservationId),
      'reservationGeneration': serializer.toJson<int>(reservationGeneration),
      'dismissalRequestedAt': serializer.toJson<DateTime?>(
        dismissalRequestedAt,
      ),
      'dismissalPlatformAlarmId': serializer.toJson<String?>(
        dismissalPlatformAlarmId,
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AlarmOccurrenceRow copyWith({
    String? id,
    String? wakePlanId,
    int? scheduledAtDays,
    int? scheduledAtMinutes,
    String? status,
    Value<String?> platformAlarmId = const Value.absent(),
    Value<DateTime?> firedAt = const Value.absent(),
    Value<DateTime?> dismissedAt = const Value.absent(),
    Value<String?> failureReason = const Value.absent(),
    Value<String?> reservationId = const Value.absent(),
    int? reservationGeneration,
    Value<DateTime?> dismissalRequestedAt = const Value.absent(),
    Value<String?> dismissalPlatformAlarmId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AlarmOccurrenceRow(
    id: id ?? this.id,
    wakePlanId: wakePlanId ?? this.wakePlanId,
    scheduledAtDays: scheduledAtDays ?? this.scheduledAtDays,
    scheduledAtMinutes: scheduledAtMinutes ?? this.scheduledAtMinutes,
    status: status ?? this.status,
    platformAlarmId: platformAlarmId.present
        ? platformAlarmId.value
        : this.platformAlarmId,
    firedAt: firedAt.present ? firedAt.value : this.firedAt,
    dismissedAt: dismissedAt.present ? dismissedAt.value : this.dismissedAt,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    reservationId: reservationId.present
        ? reservationId.value
        : this.reservationId,
    reservationGeneration: reservationGeneration ?? this.reservationGeneration,
    dismissalRequestedAt: dismissalRequestedAt.present
        ? dismissalRequestedAt.value
        : this.dismissalRequestedAt,
    dismissalPlatformAlarmId: dismissalPlatformAlarmId.present
        ? dismissalPlatformAlarmId.value
        : this.dismissalPlatformAlarmId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AlarmOccurrenceRow copyWithCompanion(AlarmOccurrenceRowsCompanion data) {
    return AlarmOccurrenceRow(
      id: data.id.present ? data.id.value : this.id,
      wakePlanId: data.wakePlanId.present
          ? data.wakePlanId.value
          : this.wakePlanId,
      scheduledAtDays: data.scheduledAtDays.present
          ? data.scheduledAtDays.value
          : this.scheduledAtDays,
      scheduledAtMinutes: data.scheduledAtMinutes.present
          ? data.scheduledAtMinutes.value
          : this.scheduledAtMinutes,
      status: data.status.present ? data.status.value : this.status,
      platformAlarmId: data.platformAlarmId.present
          ? data.platformAlarmId.value
          : this.platformAlarmId,
      firedAt: data.firedAt.present ? data.firedAt.value : this.firedAt,
      dismissedAt: data.dismissedAt.present
          ? data.dismissedAt.value
          : this.dismissedAt,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      reservationId: data.reservationId.present
          ? data.reservationId.value
          : this.reservationId,
      reservationGeneration: data.reservationGeneration.present
          ? data.reservationGeneration.value
          : this.reservationGeneration,
      dismissalRequestedAt: data.dismissalRequestedAt.present
          ? data.dismissalRequestedAt.value
          : this.dismissalRequestedAt,
      dismissalPlatformAlarmId: data.dismissalPlatformAlarmId.present
          ? data.dismissalPlatformAlarmId.value
          : this.dismissalPlatformAlarmId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlarmOccurrenceRow(')
          ..write('id: $id, ')
          ..write('wakePlanId: $wakePlanId, ')
          ..write('scheduledAtDays: $scheduledAtDays, ')
          ..write('scheduledAtMinutes: $scheduledAtMinutes, ')
          ..write('status: $status, ')
          ..write('platformAlarmId: $platformAlarmId, ')
          ..write('firedAt: $firedAt, ')
          ..write('dismissedAt: $dismissedAt, ')
          ..write('failureReason: $failureReason, ')
          ..write('reservationId: $reservationId, ')
          ..write('reservationGeneration: $reservationGeneration, ')
          ..write('dismissalRequestedAt: $dismissalRequestedAt, ')
          ..write('dismissalPlatformAlarmId: $dismissalPlatformAlarmId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    wakePlanId,
    scheduledAtDays,
    scheduledAtMinutes,
    status,
    platformAlarmId,
    firedAt,
    dismissedAt,
    failureReason,
    reservationId,
    reservationGeneration,
    dismissalRequestedAt,
    dismissalPlatformAlarmId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlarmOccurrenceRow &&
          other.id == this.id &&
          other.wakePlanId == this.wakePlanId &&
          other.scheduledAtDays == this.scheduledAtDays &&
          other.scheduledAtMinutes == this.scheduledAtMinutes &&
          other.status == this.status &&
          other.platformAlarmId == this.platformAlarmId &&
          other.firedAt == this.firedAt &&
          other.dismissedAt == this.dismissedAt &&
          other.failureReason == this.failureReason &&
          other.reservationId == this.reservationId &&
          other.reservationGeneration == this.reservationGeneration &&
          other.dismissalRequestedAt == this.dismissalRequestedAt &&
          other.dismissalPlatformAlarmId == this.dismissalPlatformAlarmId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AlarmOccurrenceRowsCompanion extends UpdateCompanion<AlarmOccurrenceRow> {
  final Value<String> id;
  final Value<String> wakePlanId;
  final Value<int> scheduledAtDays;
  final Value<int> scheduledAtMinutes;
  final Value<String> status;
  final Value<String?> platformAlarmId;
  final Value<DateTime?> firedAt;
  final Value<DateTime?> dismissedAt;
  final Value<String?> failureReason;
  final Value<String?> reservationId;
  final Value<int> reservationGeneration;
  final Value<DateTime?> dismissalRequestedAt;
  final Value<String?> dismissalPlatformAlarmId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AlarmOccurrenceRowsCompanion({
    this.id = const Value.absent(),
    this.wakePlanId = const Value.absent(),
    this.scheduledAtDays = const Value.absent(),
    this.scheduledAtMinutes = const Value.absent(),
    this.status = const Value.absent(),
    this.platformAlarmId = const Value.absent(),
    this.firedAt = const Value.absent(),
    this.dismissedAt = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.reservationId = const Value.absent(),
    this.reservationGeneration = const Value.absent(),
    this.dismissalRequestedAt = const Value.absent(),
    this.dismissalPlatformAlarmId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlarmOccurrenceRowsCompanion.insert({
    required String id,
    required String wakePlanId,
    required int scheduledAtDays,
    required int scheduledAtMinutes,
    required String status,
    this.platformAlarmId = const Value.absent(),
    this.firedAt = const Value.absent(),
    this.dismissedAt = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.reservationId = const Value.absent(),
    this.reservationGeneration = const Value.absent(),
    this.dismissalRequestedAt = const Value.absent(),
    this.dismissalPlatformAlarmId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       wakePlanId = Value(wakePlanId),
       scheduledAtDays = Value(scheduledAtDays),
       scheduledAtMinutes = Value(scheduledAtMinutes),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AlarmOccurrenceRow> custom({
    Expression<String>? id,
    Expression<String>? wakePlanId,
    Expression<int>? scheduledAtDays,
    Expression<int>? scheduledAtMinutes,
    Expression<String>? status,
    Expression<String>? platformAlarmId,
    Expression<DateTime>? firedAt,
    Expression<DateTime>? dismissedAt,
    Expression<String>? failureReason,
    Expression<String>? reservationId,
    Expression<int>? reservationGeneration,
    Expression<DateTime>? dismissalRequestedAt,
    Expression<String>? dismissalPlatformAlarmId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (wakePlanId != null) 'wake_plan_id': wakePlanId,
      if (scheduledAtDays != null) 'scheduled_at_days': scheduledAtDays,
      if (scheduledAtMinutes != null)
        'scheduled_at_minutes': scheduledAtMinutes,
      if (status != null) 'status': status,
      if (platformAlarmId != null) 'platform_alarm_id': platformAlarmId,
      if (firedAt != null) 'fired_at': firedAt,
      if (dismissedAt != null) 'dismissed_at': dismissedAt,
      if (failureReason != null) 'failure_reason': failureReason,
      if (reservationId != null) 'reservation_id': reservationId,
      if (reservationGeneration != null)
        'reservation_generation': reservationGeneration,
      if (dismissalRequestedAt != null)
        'dismissal_requested_at': dismissalRequestedAt,
      if (dismissalPlatformAlarmId != null)
        'dismissal_platform_alarm_id': dismissalPlatformAlarmId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlarmOccurrenceRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? wakePlanId,
    Value<int>? scheduledAtDays,
    Value<int>? scheduledAtMinutes,
    Value<String>? status,
    Value<String?>? platformAlarmId,
    Value<DateTime?>? firedAt,
    Value<DateTime?>? dismissedAt,
    Value<String?>? failureReason,
    Value<String?>? reservationId,
    Value<int>? reservationGeneration,
    Value<DateTime?>? dismissalRequestedAt,
    Value<String?>? dismissalPlatformAlarmId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AlarmOccurrenceRowsCompanion(
      id: id ?? this.id,
      wakePlanId: wakePlanId ?? this.wakePlanId,
      scheduledAtDays: scheduledAtDays ?? this.scheduledAtDays,
      scheduledAtMinutes: scheduledAtMinutes ?? this.scheduledAtMinutes,
      status: status ?? this.status,
      platformAlarmId: platformAlarmId ?? this.platformAlarmId,
      firedAt: firedAt ?? this.firedAt,
      dismissedAt: dismissedAt ?? this.dismissedAt,
      failureReason: failureReason ?? this.failureReason,
      reservationId: reservationId ?? this.reservationId,
      reservationGeneration:
          reservationGeneration ?? this.reservationGeneration,
      dismissalRequestedAt: dismissalRequestedAt ?? this.dismissalRequestedAt,
      dismissalPlatformAlarmId:
          dismissalPlatformAlarmId ?? this.dismissalPlatformAlarmId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (wakePlanId.present) {
      map['wake_plan_id'] = Variable<String>(wakePlanId.value);
    }
    if (scheduledAtDays.present) {
      map['scheduled_at_days'] = Variable<int>(scheduledAtDays.value);
    }
    if (scheduledAtMinutes.present) {
      map['scheduled_at_minutes'] = Variable<int>(scheduledAtMinutes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (platformAlarmId.present) {
      map['platform_alarm_id'] = Variable<String>(platformAlarmId.value);
    }
    if (firedAt.present) {
      map['fired_at'] = Variable<DateTime>(firedAt.value);
    }
    if (dismissedAt.present) {
      map['dismissed_at'] = Variable<DateTime>(dismissedAt.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (reservationId.present) {
      map['reservation_id'] = Variable<String>(reservationId.value);
    }
    if (reservationGeneration.present) {
      map['reservation_generation'] = Variable<int>(
        reservationGeneration.value,
      );
    }
    if (dismissalRequestedAt.present) {
      map['dismissal_requested_at'] = Variable<DateTime>(
        dismissalRequestedAt.value,
      );
    }
    if (dismissalPlatformAlarmId.present) {
      map['dismissal_platform_alarm_id'] = Variable<String>(
        dismissalPlatformAlarmId.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlarmOccurrenceRowsCompanion(')
          ..write('id: $id, ')
          ..write('wakePlanId: $wakePlanId, ')
          ..write('scheduledAtDays: $scheduledAtDays, ')
          ..write('scheduledAtMinutes: $scheduledAtMinutes, ')
          ..write('status: $status, ')
          ..write('platformAlarmId: $platformAlarmId, ')
          ..write('firedAt: $firedAt, ')
          ..write('dismissedAt: $dismissedAt, ')
          ..write('failureReason: $failureReason, ')
          ..write('reservationId: $reservationId, ')
          ..write('reservationGeneration: $reservationGeneration, ')
          ..write('dismissalRequestedAt: $dismissalRequestedAt, ')
          ..write('dismissalPlatformAlarmId: $dismissalPlatformAlarmId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsRowsTable extends AppSettingsRows
    with TableInfo<$AppSettingsRowsTable, AppSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultStartOffsetMinutesMeta =
      const VerificationMeta('defaultStartOffsetMinutes');
  @override
  late final GeneratedColumn<int> defaultStartOffsetMinutes =
      GeneratedColumn<int>(
        'default_start_offset_minutes',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _defaultIntervalMinutesMeta =
      const VerificationMeta('defaultIntervalMinutes');
  @override
  late final GeneratedColumn<int> defaultIntervalMinutes = GeneratedColumn<int>(
    'default_interval_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _defaultSoundIdMeta = const VerificationMeta(
    'defaultSoundId',
  );
  @override
  late final GeneratedColumn<String> defaultSoundId = GeneratedColumn<String>(
    'default_sound_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _defaultVibrationEnabledMeta =
      const VerificationMeta('defaultVibrationEnabled');
  @override
  late final GeneratedColumn<bool> defaultVibrationEnabled =
      GeneratedColumn<bool>(
        'default_vibration_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("default_vibration_enabled" IN (0, 1))',
        ),
      );
  static const VerificationMeta _defaultRepeatTypeMeta = const VerificationMeta(
    'defaultRepeatType',
  );
  @override
  late final GeneratedColumn<String> defaultRepeatType =
      GeneratedColumn<String>(
        'default_repeat_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _defaultTargetTimeMinutesMeta =
      const VerificationMeta('defaultTargetTimeMinutes');
  @override
  late final GeneratedColumn<int> defaultTargetTimeMinutes =
      GeneratedColumn<int>(
        'default_target_time_minutes',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    defaultStartOffsetMinutes,
    defaultIntervalMinutes,
    defaultSoundId,
    defaultVibrationEnabled,
    defaultRepeatType,
    defaultTargetTimeMinutes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('default_start_offset_minutes')) {
      context.handle(
        _defaultStartOffsetMinutesMeta,
        defaultStartOffsetMinutes.isAcceptableOrUnknown(
          data['default_start_offset_minutes']!,
          _defaultStartOffsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_defaultStartOffsetMinutesMeta);
    }
    if (data.containsKey('default_interval_minutes')) {
      context.handle(
        _defaultIntervalMinutesMeta,
        defaultIntervalMinutes.isAcceptableOrUnknown(
          data['default_interval_minutes']!,
          _defaultIntervalMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_defaultIntervalMinutesMeta);
    }
    if (data.containsKey('default_sound_id')) {
      context.handle(
        _defaultSoundIdMeta,
        defaultSoundId.isAcceptableOrUnknown(
          data['default_sound_id']!,
          _defaultSoundIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_defaultSoundIdMeta);
    }
    if (data.containsKey('default_vibration_enabled')) {
      context.handle(
        _defaultVibrationEnabledMeta,
        defaultVibrationEnabled.isAcceptableOrUnknown(
          data['default_vibration_enabled']!,
          _defaultVibrationEnabledMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_defaultVibrationEnabledMeta);
    }
    if (data.containsKey('default_repeat_type')) {
      context.handle(
        _defaultRepeatTypeMeta,
        defaultRepeatType.isAcceptableOrUnknown(
          data['default_repeat_type']!,
          _defaultRepeatTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_defaultRepeatTypeMeta);
    }
    if (data.containsKey('default_target_time_minutes')) {
      context.handle(
        _defaultTargetTimeMinutesMeta,
        defaultTargetTimeMinutes.isAcceptableOrUnknown(
          data['default_target_time_minutes']!,
          _defaultTargetTimeMinutesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      defaultStartOffsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_start_offset_minutes'],
      )!,
      defaultIntervalMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_interval_minutes'],
      )!,
      defaultSoundId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_sound_id'],
      )!,
      defaultVibrationEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}default_vibration_enabled'],
      )!,
      defaultRepeatType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_repeat_type'],
      )!,
      defaultTargetTimeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_target_time_minutes'],
      ),
    );
  }

  @override
  $AppSettingsRowsTable createAlias(String alias) {
    return $AppSettingsRowsTable(attachedDatabase, alias);
  }
}

class AppSettingsRow extends DataClass implements Insertable<AppSettingsRow> {
  final int id;
  final int defaultStartOffsetMinutes;
  final int defaultIntervalMinutes;
  final String defaultSoundId;
  final bool defaultVibrationEnabled;
  final String defaultRepeatType;
  final int? defaultTargetTimeMinutes;
  const AppSettingsRow({
    required this.id,
    required this.defaultStartOffsetMinutes,
    required this.defaultIntervalMinutes,
    required this.defaultSoundId,
    required this.defaultVibrationEnabled,
    required this.defaultRepeatType,
    this.defaultTargetTimeMinutes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['default_start_offset_minutes'] = Variable<int>(
      defaultStartOffsetMinutes,
    );
    map['default_interval_minutes'] = Variable<int>(defaultIntervalMinutes);
    map['default_sound_id'] = Variable<String>(defaultSoundId);
    map['default_vibration_enabled'] = Variable<bool>(defaultVibrationEnabled);
    map['default_repeat_type'] = Variable<String>(defaultRepeatType);
    if (!nullToAbsent || defaultTargetTimeMinutes != null) {
      map['default_target_time_minutes'] = Variable<int>(
        defaultTargetTimeMinutes,
      );
    }
    return map;
  }

  AppSettingsRowsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsRowsCompanion(
      id: Value(id),
      defaultStartOffsetMinutes: Value(defaultStartOffsetMinutes),
      defaultIntervalMinutes: Value(defaultIntervalMinutes),
      defaultSoundId: Value(defaultSoundId),
      defaultVibrationEnabled: Value(defaultVibrationEnabled),
      defaultRepeatType: Value(defaultRepeatType),
      defaultTargetTimeMinutes: defaultTargetTimeMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultTargetTimeMinutes),
    );
  }

  factory AppSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingsRow(
      id: serializer.fromJson<int>(json['id']),
      defaultStartOffsetMinutes: serializer.fromJson<int>(
        json['defaultStartOffsetMinutes'],
      ),
      defaultIntervalMinutes: serializer.fromJson<int>(
        json['defaultIntervalMinutes'],
      ),
      defaultSoundId: serializer.fromJson<String>(json['defaultSoundId']),
      defaultVibrationEnabled: serializer.fromJson<bool>(
        json['defaultVibrationEnabled'],
      ),
      defaultRepeatType: serializer.fromJson<String>(json['defaultRepeatType']),
      defaultTargetTimeMinutes: serializer.fromJson<int?>(
        json['defaultTargetTimeMinutes'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'defaultStartOffsetMinutes': serializer.toJson<int>(
        defaultStartOffsetMinutes,
      ),
      'defaultIntervalMinutes': serializer.toJson<int>(defaultIntervalMinutes),
      'defaultSoundId': serializer.toJson<String>(defaultSoundId),
      'defaultVibrationEnabled': serializer.toJson<bool>(
        defaultVibrationEnabled,
      ),
      'defaultRepeatType': serializer.toJson<String>(defaultRepeatType),
      'defaultTargetTimeMinutes': serializer.toJson<int?>(
        defaultTargetTimeMinutes,
      ),
    };
  }

  AppSettingsRow copyWith({
    int? id,
    int? defaultStartOffsetMinutes,
    int? defaultIntervalMinutes,
    String? defaultSoundId,
    bool? defaultVibrationEnabled,
    String? defaultRepeatType,
    Value<int?> defaultTargetTimeMinutes = const Value.absent(),
  }) => AppSettingsRow(
    id: id ?? this.id,
    defaultStartOffsetMinutes:
        defaultStartOffsetMinutes ?? this.defaultStartOffsetMinutes,
    defaultIntervalMinutes:
        defaultIntervalMinutes ?? this.defaultIntervalMinutes,
    defaultSoundId: defaultSoundId ?? this.defaultSoundId,
    defaultVibrationEnabled:
        defaultVibrationEnabled ?? this.defaultVibrationEnabled,
    defaultRepeatType: defaultRepeatType ?? this.defaultRepeatType,
    defaultTargetTimeMinutes: defaultTargetTimeMinutes.present
        ? defaultTargetTimeMinutes.value
        : this.defaultTargetTimeMinutes,
  );
  AppSettingsRow copyWithCompanion(AppSettingsRowsCompanion data) {
    return AppSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      defaultStartOffsetMinutes: data.defaultStartOffsetMinutes.present
          ? data.defaultStartOffsetMinutes.value
          : this.defaultStartOffsetMinutes,
      defaultIntervalMinutes: data.defaultIntervalMinutes.present
          ? data.defaultIntervalMinutes.value
          : this.defaultIntervalMinutes,
      defaultSoundId: data.defaultSoundId.present
          ? data.defaultSoundId.value
          : this.defaultSoundId,
      defaultVibrationEnabled: data.defaultVibrationEnabled.present
          ? data.defaultVibrationEnabled.value
          : this.defaultVibrationEnabled,
      defaultRepeatType: data.defaultRepeatType.present
          ? data.defaultRepeatType.value
          : this.defaultRepeatType,
      defaultTargetTimeMinutes: data.defaultTargetTimeMinutes.present
          ? data.defaultTargetTimeMinutes.value
          : this.defaultTargetTimeMinutes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsRow(')
          ..write('id: $id, ')
          ..write('defaultStartOffsetMinutes: $defaultStartOffsetMinutes, ')
          ..write('defaultIntervalMinutes: $defaultIntervalMinutes, ')
          ..write('defaultSoundId: $defaultSoundId, ')
          ..write('defaultVibrationEnabled: $defaultVibrationEnabled, ')
          ..write('defaultRepeatType: $defaultRepeatType, ')
          ..write('defaultTargetTimeMinutes: $defaultTargetTimeMinutes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    defaultStartOffsetMinutes,
    defaultIntervalMinutes,
    defaultSoundId,
    defaultVibrationEnabled,
    defaultRepeatType,
    defaultTargetTimeMinutes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingsRow &&
          other.id == this.id &&
          other.defaultStartOffsetMinutes == this.defaultStartOffsetMinutes &&
          other.defaultIntervalMinutes == this.defaultIntervalMinutes &&
          other.defaultSoundId == this.defaultSoundId &&
          other.defaultVibrationEnabled == this.defaultVibrationEnabled &&
          other.defaultRepeatType == this.defaultRepeatType &&
          other.defaultTargetTimeMinutes == this.defaultTargetTimeMinutes);
}

class AppSettingsRowsCompanion extends UpdateCompanion<AppSettingsRow> {
  final Value<int> id;
  final Value<int> defaultStartOffsetMinutes;
  final Value<int> defaultIntervalMinutes;
  final Value<String> defaultSoundId;
  final Value<bool> defaultVibrationEnabled;
  final Value<String> defaultRepeatType;
  final Value<int?> defaultTargetTimeMinutes;
  const AppSettingsRowsCompanion({
    this.id = const Value.absent(),
    this.defaultStartOffsetMinutes = const Value.absent(),
    this.defaultIntervalMinutes = const Value.absent(),
    this.defaultSoundId = const Value.absent(),
    this.defaultVibrationEnabled = const Value.absent(),
    this.defaultRepeatType = const Value.absent(),
    this.defaultTargetTimeMinutes = const Value.absent(),
  });
  AppSettingsRowsCompanion.insert({
    this.id = const Value.absent(),
    required int defaultStartOffsetMinutes,
    required int defaultIntervalMinutes,
    required String defaultSoundId,
    required bool defaultVibrationEnabled,
    required String defaultRepeatType,
    this.defaultTargetTimeMinutes = const Value.absent(),
  }) : defaultStartOffsetMinutes = Value(defaultStartOffsetMinutes),
       defaultIntervalMinutes = Value(defaultIntervalMinutes),
       defaultSoundId = Value(defaultSoundId),
       defaultVibrationEnabled = Value(defaultVibrationEnabled),
       defaultRepeatType = Value(defaultRepeatType);
  static Insertable<AppSettingsRow> custom({
    Expression<int>? id,
    Expression<int>? defaultStartOffsetMinutes,
    Expression<int>? defaultIntervalMinutes,
    Expression<String>? defaultSoundId,
    Expression<bool>? defaultVibrationEnabled,
    Expression<String>? defaultRepeatType,
    Expression<int>? defaultTargetTimeMinutes,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (defaultStartOffsetMinutes != null)
        'default_start_offset_minutes': defaultStartOffsetMinutes,
      if (defaultIntervalMinutes != null)
        'default_interval_minutes': defaultIntervalMinutes,
      if (defaultSoundId != null) 'default_sound_id': defaultSoundId,
      if (defaultVibrationEnabled != null)
        'default_vibration_enabled': defaultVibrationEnabled,
      if (defaultRepeatType != null) 'default_repeat_type': defaultRepeatType,
      if (defaultTargetTimeMinutes != null)
        'default_target_time_minutes': defaultTargetTimeMinutes,
    });
  }

  AppSettingsRowsCompanion copyWith({
    Value<int>? id,
    Value<int>? defaultStartOffsetMinutes,
    Value<int>? defaultIntervalMinutes,
    Value<String>? defaultSoundId,
    Value<bool>? defaultVibrationEnabled,
    Value<String>? defaultRepeatType,
    Value<int?>? defaultTargetTimeMinutes,
  }) {
    return AppSettingsRowsCompanion(
      id: id ?? this.id,
      defaultStartOffsetMinutes:
          defaultStartOffsetMinutes ?? this.defaultStartOffsetMinutes,
      defaultIntervalMinutes:
          defaultIntervalMinutes ?? this.defaultIntervalMinutes,
      defaultSoundId: defaultSoundId ?? this.defaultSoundId,
      defaultVibrationEnabled:
          defaultVibrationEnabled ?? this.defaultVibrationEnabled,
      defaultRepeatType: defaultRepeatType ?? this.defaultRepeatType,
      defaultTargetTimeMinutes:
          defaultTargetTimeMinutes ?? this.defaultTargetTimeMinutes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (defaultStartOffsetMinutes.present) {
      map['default_start_offset_minutes'] = Variable<int>(
        defaultStartOffsetMinutes.value,
      );
    }
    if (defaultIntervalMinutes.present) {
      map['default_interval_minutes'] = Variable<int>(
        defaultIntervalMinutes.value,
      );
    }
    if (defaultSoundId.present) {
      map['default_sound_id'] = Variable<String>(defaultSoundId.value);
    }
    if (defaultVibrationEnabled.present) {
      map['default_vibration_enabled'] = Variable<bool>(
        defaultVibrationEnabled.value,
      );
    }
    if (defaultRepeatType.present) {
      map['default_repeat_type'] = Variable<String>(defaultRepeatType.value);
    }
    if (defaultTargetTimeMinutes.present) {
      map['default_target_time_minutes'] = Variable<int>(
        defaultTargetTimeMinutes.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsRowsCompanion(')
          ..write('id: $id, ')
          ..write('defaultStartOffsetMinutes: $defaultStartOffsetMinutes, ')
          ..write('defaultIntervalMinutes: $defaultIntervalMinutes, ')
          ..write('defaultSoundId: $defaultSoundId, ')
          ..write('defaultVibrationEnabled: $defaultVibrationEnabled, ')
          ..write('defaultRepeatType: $defaultRepeatType, ')
          ..write('defaultTargetTimeMinutes: $defaultTargetTimeMinutes')
          ..write(')'))
        .toString();
  }
}

abstract class _$WakePlanDatabase extends GeneratedDatabase {
  _$WakePlanDatabase(QueryExecutor e) : super(e);
  $WakePlanDatabaseManager get managers => $WakePlanDatabaseManager(this);
  late final $WakePlanRowsTable wakePlanRows = $WakePlanRowsTable(this);
  late final $AlarmOccurrenceRowsTable alarmOccurrenceRows =
      $AlarmOccurrenceRowsTable(this);
  late final $AppSettingsRowsTable appSettingsRows = $AppSettingsRowsTable(
    this,
  );
  late final Index alarmOccurrenceWakePlanId = Index(
    'alarm_occurrence_wake_plan_id',
    'CREATE INDEX alarm_occurrence_wake_plan_id ON alarm_occurrence_rows (wake_plan_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    wakePlanRows,
    alarmOccurrenceRows,
    appSettingsRows,
    alarmOccurrenceWakePlanId,
  ];
}

typedef $$WakePlanRowsTableCreateCompanionBuilder =
    WakePlanRowsCompanion Function({
      required String id,
      required String title,
      required int targetTimeMinutes,
      required int startOffsetMinutes,
      required int intervalMinutes,
      required String repeatType,
      Value<int?> oneTimeDateDays,
      Value<int?> weekdaysMask,
      required bool isEnabled,
      required String status,
      Value<int?> skipNextDateDays,
      required String soundId,
      required bool vibrationEnabled,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$WakePlanRowsTableUpdateCompanionBuilder =
    WakePlanRowsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<int> targetTimeMinutes,
      Value<int> startOffsetMinutes,
      Value<int> intervalMinutes,
      Value<String> repeatType,
      Value<int?> oneTimeDateDays,
      Value<int?> weekdaysMask,
      Value<bool> isEnabled,
      Value<String> status,
      Value<int?> skipNextDateDays,
      Value<String> soundId,
      Value<bool> vibrationEnabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$WakePlanRowsTableReferences
    extends
        BaseReferences<_$WakePlanDatabase, $WakePlanRowsTable, WakePlanRow> {
  $$WakePlanRowsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $AlarmOccurrenceRowsTable,
    List<AlarmOccurrenceRow>
  >
  _alarmOccurrenceRowsRefsTable(_$WakePlanDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.alarmOccurrenceRows,
        aliasName: $_aliasNameGenerator(
          db.wakePlanRows.id,
          db.alarmOccurrenceRows.wakePlanId,
        ),
      );

  $$AlarmOccurrenceRowsTableProcessedTableManager get alarmOccurrenceRowsRefs {
    final manager = $$AlarmOccurrenceRowsTableTableManager(
      $_db,
      $_db.alarmOccurrenceRows,
    ).filter((f) => f.wakePlanId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _alarmOccurrenceRowsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$WakePlanRowsTableFilterComposer
    extends Composer<_$WakePlanDatabase, $WakePlanRowsTable> {
  $$WakePlanRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetTimeMinutes => $composableBuilder(
    column: $table.targetTimeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startOffsetMinutes => $composableBuilder(
    column: $table.startOffsetMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intervalMinutes => $composableBuilder(
    column: $table.intervalMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repeatType => $composableBuilder(
    column: $table.repeatType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get oneTimeDateDays => $composableBuilder(
    column: $table.oneTimeDateDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekdaysMask => $composableBuilder(
    column: $table.weekdaysMask,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get skipNextDateDays => $composableBuilder(
    column: $table.skipNextDateDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get soundId => $composableBuilder(
    column: $table.soundId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get vibrationEnabled => $composableBuilder(
    column: $table.vibrationEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> alarmOccurrenceRowsRefs(
    Expression<bool> Function($$AlarmOccurrenceRowsTableFilterComposer f) f,
  ) {
    final $$AlarmOccurrenceRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.alarmOccurrenceRows,
      getReferencedColumn: (t) => t.wakePlanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AlarmOccurrenceRowsTableFilterComposer(
            $db: $db,
            $table: $db.alarmOccurrenceRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WakePlanRowsTableOrderingComposer
    extends Composer<_$WakePlanDatabase, $WakePlanRowsTable> {
  $$WakePlanRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetTimeMinutes => $composableBuilder(
    column: $table.targetTimeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startOffsetMinutes => $composableBuilder(
    column: $table.startOffsetMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intervalMinutes => $composableBuilder(
    column: $table.intervalMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repeatType => $composableBuilder(
    column: $table.repeatType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get oneTimeDateDays => $composableBuilder(
    column: $table.oneTimeDateDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekdaysMask => $composableBuilder(
    column: $table.weekdaysMask,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get skipNextDateDays => $composableBuilder(
    column: $table.skipNextDateDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get soundId => $composableBuilder(
    column: $table.soundId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get vibrationEnabled => $composableBuilder(
    column: $table.vibrationEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WakePlanRowsTableAnnotationComposer
    extends Composer<_$WakePlanDatabase, $WakePlanRowsTable> {
  $$WakePlanRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get targetTimeMinutes => $composableBuilder(
    column: $table.targetTimeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startOffsetMinutes => $composableBuilder(
    column: $table.startOffsetMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get intervalMinutes => $composableBuilder(
    column: $table.intervalMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get repeatType => $composableBuilder(
    column: $table.repeatType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get oneTimeDateDays => $composableBuilder(
    column: $table.oneTimeDateDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get weekdaysMask => $composableBuilder(
    column: $table.weekdaysMask,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get skipNextDateDays => $composableBuilder(
    column: $table.skipNextDateDays,
    builder: (column) => column,
  );

  GeneratedColumn<String> get soundId =>
      $composableBuilder(column: $table.soundId, builder: (column) => column);

  GeneratedColumn<bool> get vibrationEnabled => $composableBuilder(
    column: $table.vibrationEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> alarmOccurrenceRowsRefs<T extends Object>(
    Expression<T> Function($$AlarmOccurrenceRowsTableAnnotationComposer a) f,
  ) {
    final $$AlarmOccurrenceRowsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.alarmOccurrenceRows,
          getReferencedColumn: (t) => t.wakePlanId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AlarmOccurrenceRowsTableAnnotationComposer(
                $db: $db,
                $table: $db.alarmOccurrenceRows,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$WakePlanRowsTableTableManager
    extends
        RootTableManager<
          _$WakePlanDatabase,
          $WakePlanRowsTable,
          WakePlanRow,
          $$WakePlanRowsTableFilterComposer,
          $$WakePlanRowsTableOrderingComposer,
          $$WakePlanRowsTableAnnotationComposer,
          $$WakePlanRowsTableCreateCompanionBuilder,
          $$WakePlanRowsTableUpdateCompanionBuilder,
          (WakePlanRow, $$WakePlanRowsTableReferences),
          WakePlanRow,
          PrefetchHooks Function({bool alarmOccurrenceRowsRefs})
        > {
  $$WakePlanRowsTableTableManager(
    _$WakePlanDatabase db,
    $WakePlanRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WakePlanRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WakePlanRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WakePlanRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> targetTimeMinutes = const Value.absent(),
                Value<int> startOffsetMinutes = const Value.absent(),
                Value<int> intervalMinutes = const Value.absent(),
                Value<String> repeatType = const Value.absent(),
                Value<int?> oneTimeDateDays = const Value.absent(),
                Value<int?> weekdaysMask = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> skipNextDateDays = const Value.absent(),
                Value<String> soundId = const Value.absent(),
                Value<bool> vibrationEnabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WakePlanRowsCompanion(
                id: id,
                title: title,
                targetTimeMinutes: targetTimeMinutes,
                startOffsetMinutes: startOffsetMinutes,
                intervalMinutes: intervalMinutes,
                repeatType: repeatType,
                oneTimeDateDays: oneTimeDateDays,
                weekdaysMask: weekdaysMask,
                isEnabled: isEnabled,
                status: status,
                skipNextDateDays: skipNextDateDays,
                soundId: soundId,
                vibrationEnabled: vibrationEnabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required int targetTimeMinutes,
                required int startOffsetMinutes,
                required int intervalMinutes,
                required String repeatType,
                Value<int?> oneTimeDateDays = const Value.absent(),
                Value<int?> weekdaysMask = const Value.absent(),
                required bool isEnabled,
                required String status,
                Value<int?> skipNextDateDays = const Value.absent(),
                required String soundId,
                required bool vibrationEnabled,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => WakePlanRowsCompanion.insert(
                id: id,
                title: title,
                targetTimeMinutes: targetTimeMinutes,
                startOffsetMinutes: startOffsetMinutes,
                intervalMinutes: intervalMinutes,
                repeatType: repeatType,
                oneTimeDateDays: oneTimeDateDays,
                weekdaysMask: weekdaysMask,
                isEnabled: isEnabled,
                status: status,
                skipNextDateDays: skipNextDateDays,
                soundId: soundId,
                vibrationEnabled: vibrationEnabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$WakePlanRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({alarmOccurrenceRowsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (alarmOccurrenceRowsRefs) db.alarmOccurrenceRows,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (alarmOccurrenceRowsRefs)
                    await $_getPrefetchedData<
                      WakePlanRow,
                      $WakePlanRowsTable,
                      AlarmOccurrenceRow
                    >(
                      currentTable: table,
                      referencedTable: $$WakePlanRowsTableReferences
                          ._alarmOccurrenceRowsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$WakePlanRowsTableReferences(
                            db,
                            table,
                            p0,
                          ).alarmOccurrenceRowsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.wakePlanId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$WakePlanRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$WakePlanDatabase,
      $WakePlanRowsTable,
      WakePlanRow,
      $$WakePlanRowsTableFilterComposer,
      $$WakePlanRowsTableOrderingComposer,
      $$WakePlanRowsTableAnnotationComposer,
      $$WakePlanRowsTableCreateCompanionBuilder,
      $$WakePlanRowsTableUpdateCompanionBuilder,
      (WakePlanRow, $$WakePlanRowsTableReferences),
      WakePlanRow,
      PrefetchHooks Function({bool alarmOccurrenceRowsRefs})
    >;
typedef $$AlarmOccurrenceRowsTableCreateCompanionBuilder =
    AlarmOccurrenceRowsCompanion Function({
      required String id,
      required String wakePlanId,
      required int scheduledAtDays,
      required int scheduledAtMinutes,
      required String status,
      Value<String?> platformAlarmId,
      Value<DateTime?> firedAt,
      Value<DateTime?> dismissedAt,
      Value<String?> failureReason,
      Value<String?> reservationId,
      Value<int> reservationGeneration,
      Value<DateTime?> dismissalRequestedAt,
      Value<String?> dismissalPlatformAlarmId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AlarmOccurrenceRowsTableUpdateCompanionBuilder =
    AlarmOccurrenceRowsCompanion Function({
      Value<String> id,
      Value<String> wakePlanId,
      Value<int> scheduledAtDays,
      Value<int> scheduledAtMinutes,
      Value<String> status,
      Value<String?> platformAlarmId,
      Value<DateTime?> firedAt,
      Value<DateTime?> dismissedAt,
      Value<String?> failureReason,
      Value<String?> reservationId,
      Value<int> reservationGeneration,
      Value<DateTime?> dismissalRequestedAt,
      Value<String?> dismissalPlatformAlarmId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$AlarmOccurrenceRowsTableReferences
    extends
        BaseReferences<
          _$WakePlanDatabase,
          $AlarmOccurrenceRowsTable,
          AlarmOccurrenceRow
        > {
  $$AlarmOccurrenceRowsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WakePlanRowsTable _wakePlanIdTable(_$WakePlanDatabase db) =>
      db.wakePlanRows.createAlias(
        $_aliasNameGenerator(
          db.alarmOccurrenceRows.wakePlanId,
          db.wakePlanRows.id,
        ),
      );

  $$WakePlanRowsTableProcessedTableManager get wakePlanId {
    final $_column = $_itemColumn<String>('wake_plan_id')!;

    final manager = $$WakePlanRowsTableTableManager(
      $_db,
      $_db.wakePlanRows,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wakePlanIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AlarmOccurrenceRowsTableFilterComposer
    extends Composer<_$WakePlanDatabase, $AlarmOccurrenceRowsTable> {
  $$AlarmOccurrenceRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scheduledAtDays => $composableBuilder(
    column: $table.scheduledAtDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scheduledAtMinutes => $composableBuilder(
    column: $table.scheduledAtMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platformAlarmId => $composableBuilder(
    column: $table.platformAlarmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firedAt => $composableBuilder(
    column: $table.firedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );
  ColumnFilters<String> get reservationId => $composableBuilder(
    column: $table.reservationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reservationGeneration => $composableBuilder(
    column: $table.reservationGeneration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dismissalRequestedAt => $composableBuilder(
    column: $table.dismissalRequestedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dismissalPlatformAlarmId => $composableBuilder(
    column: $table.dismissalPlatformAlarmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WakePlanRowsTableFilterComposer get wakePlanId {
    final $$WakePlanRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wakePlanId,
      referencedTable: $db.wakePlanRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WakePlanRowsTableFilterComposer(
            $db: $db,
            $table: $db.wakePlanRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AlarmOccurrenceRowsTableOrderingComposer
    extends Composer<_$WakePlanDatabase, $AlarmOccurrenceRowsTable> {
  $$AlarmOccurrenceRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledAtDays => $composableBuilder(
    column: $table.scheduledAtDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledAtMinutes => $composableBuilder(
    column: $table.scheduledAtMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platformAlarmId => $composableBuilder(
    column: $table.platformAlarmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firedAt => $composableBuilder(
    column: $table.firedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );
  ColumnOrderings<String> get reservationId => $composableBuilder(
    column: $table.reservationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reservationGeneration => $composableBuilder(
    column: $table.reservationGeneration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dismissalRequestedAt => $composableBuilder(
    column: $table.dismissalRequestedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dismissalPlatformAlarmId => $composableBuilder(
    column: $table.dismissalPlatformAlarmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WakePlanRowsTableOrderingComposer get wakePlanId {
    final $$WakePlanRowsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wakePlanId,
      referencedTable: $db.wakePlanRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WakePlanRowsTableOrderingComposer(
            $db: $db,
            $table: $db.wakePlanRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AlarmOccurrenceRowsTableAnnotationComposer
    extends Composer<_$WakePlanDatabase, $AlarmOccurrenceRowsTable> {
  $$AlarmOccurrenceRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get scheduledAtDays => $composableBuilder(
    column: $table.scheduledAtDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scheduledAtMinutes => $composableBuilder(
    column: $table.scheduledAtMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get platformAlarmId => $composableBuilder(
    column: $table.platformAlarmId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get firedAt =>
      $composableBuilder(column: $table.firedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );
  GeneratedColumn<String> get reservationId => $composableBuilder(
    column: $table.reservationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reservationGeneration => $composableBuilder(
    column: $table.reservationGeneration,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dismissalRequestedAt => $composableBuilder(
    column: $table.dismissalRequestedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dismissalPlatformAlarmId => $composableBuilder(
    column: $table.dismissalPlatformAlarmId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$WakePlanRowsTableAnnotationComposer get wakePlanId {
    final $$WakePlanRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wakePlanId,
      referencedTable: $db.wakePlanRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WakePlanRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.wakePlanRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AlarmOccurrenceRowsTableTableManager
    extends
        RootTableManager<
          _$WakePlanDatabase,
          $AlarmOccurrenceRowsTable,
          AlarmOccurrenceRow,
          $$AlarmOccurrenceRowsTableFilterComposer,
          $$AlarmOccurrenceRowsTableOrderingComposer,
          $$AlarmOccurrenceRowsTableAnnotationComposer,
          $$AlarmOccurrenceRowsTableCreateCompanionBuilder,
          $$AlarmOccurrenceRowsTableUpdateCompanionBuilder,
          (AlarmOccurrenceRow, $$AlarmOccurrenceRowsTableReferences),
          AlarmOccurrenceRow,
          PrefetchHooks Function({bool wakePlanId})
        > {
  $$AlarmOccurrenceRowsTableTableManager(
    _$WakePlanDatabase db,
    $AlarmOccurrenceRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlarmOccurrenceRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlarmOccurrenceRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AlarmOccurrenceRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> wakePlanId = const Value.absent(),
                Value<int> scheduledAtDays = const Value.absent(),
                Value<int> scheduledAtMinutes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> platformAlarmId = const Value.absent(),
                Value<DateTime?> firedAt = const Value.absent(),
                Value<DateTime?> dismissedAt = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String?> reservationId = const Value.absent(),
                Value<int> reservationGeneration = const Value.absent(),
                Value<DateTime?> dismissalRequestedAt = const Value.absent(),
                Value<String?> dismissalPlatformAlarmId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlarmOccurrenceRowsCompanion(
                id: id,
                wakePlanId: wakePlanId,
                scheduledAtDays: scheduledAtDays,
                scheduledAtMinutes: scheduledAtMinutes,
                status: status,
                platformAlarmId: platformAlarmId,
                firedAt: firedAt,
                dismissedAt: dismissedAt,
                failureReason: failureReason,
                reservationId: reservationId,
                reservationGeneration: reservationGeneration,
                dismissalRequestedAt: dismissalRequestedAt,
                dismissalPlatformAlarmId: dismissalPlatformAlarmId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String wakePlanId,
                required int scheduledAtDays,
                required int scheduledAtMinutes,
                required String status,
                Value<String?> platformAlarmId = const Value.absent(),
                Value<DateTime?> firedAt = const Value.absent(),
                Value<DateTime?> dismissedAt = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String?> reservationId = const Value.absent(),
                Value<int> reservationGeneration = const Value.absent(),
                Value<DateTime?> dismissalRequestedAt = const Value.absent(),
                Value<String?> dismissalPlatformAlarmId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AlarmOccurrenceRowsCompanion.insert(
                id: id,
                wakePlanId: wakePlanId,
                scheduledAtDays: scheduledAtDays,
                scheduledAtMinutes: scheduledAtMinutes,
                status: status,
                platformAlarmId: platformAlarmId,
                firedAt: firedAt,
                dismissedAt: dismissedAt,
                failureReason: failureReason,
                reservationId: reservationId,
                reservationGeneration: reservationGeneration,
                dismissalRequestedAt: dismissalRequestedAt,
                dismissalPlatformAlarmId: dismissalPlatformAlarmId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AlarmOccurrenceRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({wakePlanId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (wakePlanId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.wakePlanId,
                                referencedTable:
                                    $$AlarmOccurrenceRowsTableReferences
                                        ._wakePlanIdTable(db),
                                referencedColumn:
                                    $$AlarmOccurrenceRowsTableReferences
                                        ._wakePlanIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AlarmOccurrenceRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$WakePlanDatabase,
      $AlarmOccurrenceRowsTable,
      AlarmOccurrenceRow,
      $$AlarmOccurrenceRowsTableFilterComposer,
      $$AlarmOccurrenceRowsTableOrderingComposer,
      $$AlarmOccurrenceRowsTableAnnotationComposer,
      $$AlarmOccurrenceRowsTableCreateCompanionBuilder,
      $$AlarmOccurrenceRowsTableUpdateCompanionBuilder,
      (AlarmOccurrenceRow, $$AlarmOccurrenceRowsTableReferences),
      AlarmOccurrenceRow,
      PrefetchHooks Function({bool wakePlanId})
    >;
typedef $$AppSettingsRowsTableCreateCompanionBuilder =
    AppSettingsRowsCompanion Function({
      Value<int> id,
      required int defaultStartOffsetMinutes,
      required int defaultIntervalMinutes,
      required String defaultSoundId,
      required bool defaultVibrationEnabled,
      required String defaultRepeatType,
      Value<int?> defaultTargetTimeMinutes,
    });
typedef $$AppSettingsRowsTableUpdateCompanionBuilder =
    AppSettingsRowsCompanion Function({
      Value<int> id,
      Value<int> defaultStartOffsetMinutes,
      Value<int> defaultIntervalMinutes,
      Value<String> defaultSoundId,
      Value<bool> defaultVibrationEnabled,
      Value<String> defaultRepeatType,
      Value<int?> defaultTargetTimeMinutes,
    });

class $$AppSettingsRowsTableFilterComposer
    extends Composer<_$WakePlanDatabase, $AppSettingsRowsTable> {
  $$AppSettingsRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get defaultStartOffsetMinutes => $composableBuilder(
    column: $table.defaultStartOffsetMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get defaultIntervalMinutes => $composableBuilder(
    column: $table.defaultIntervalMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultSoundId => $composableBuilder(
    column: $table.defaultSoundId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get defaultVibrationEnabled => $composableBuilder(
    column: $table.defaultVibrationEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultRepeatType => $composableBuilder(
    column: $table.defaultRepeatType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get defaultTargetTimeMinutes => $composableBuilder(
    column: $table.defaultTargetTimeMinutes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsRowsTableOrderingComposer
    extends Composer<_$WakePlanDatabase, $AppSettingsRowsTable> {
  $$AppSettingsRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultStartOffsetMinutes => $composableBuilder(
    column: $table.defaultStartOffsetMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultIntervalMinutes => $composableBuilder(
    column: $table.defaultIntervalMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultSoundId => $composableBuilder(
    column: $table.defaultSoundId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get defaultVibrationEnabled => $composableBuilder(
    column: $table.defaultVibrationEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultRepeatType => $composableBuilder(
    column: $table.defaultRepeatType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultTargetTimeMinutes => $composableBuilder(
    column: $table.defaultTargetTimeMinutes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsRowsTableAnnotationComposer
    extends Composer<_$WakePlanDatabase, $AppSettingsRowsTable> {
  $$AppSettingsRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get defaultStartOffsetMinutes => $composableBuilder(
    column: $table.defaultStartOffsetMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get defaultIntervalMinutes => $composableBuilder(
    column: $table.defaultIntervalMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get defaultSoundId => $composableBuilder(
    column: $table.defaultSoundId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get defaultVibrationEnabled => $composableBuilder(
    column: $table.defaultVibrationEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get defaultRepeatType => $composableBuilder(
    column: $table.defaultRepeatType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get defaultTargetTimeMinutes => $composableBuilder(
    column: $table.defaultTargetTimeMinutes,
    builder: (column) => column,
  );
}

class $$AppSettingsRowsTableTableManager
    extends
        RootTableManager<
          _$WakePlanDatabase,
          $AppSettingsRowsTable,
          AppSettingsRow,
          $$AppSettingsRowsTableFilterComposer,
          $$AppSettingsRowsTableOrderingComposer,
          $$AppSettingsRowsTableAnnotationComposer,
          $$AppSettingsRowsTableCreateCompanionBuilder,
          $$AppSettingsRowsTableUpdateCompanionBuilder,
          (
            AppSettingsRow,
            BaseReferences<
              _$WakePlanDatabase,
              $AppSettingsRowsTable,
              AppSettingsRow
            >,
          ),
          AppSettingsRow,
          PrefetchHooks Function()
        > {
  $$AppSettingsRowsTableTableManager(
    _$WakePlanDatabase db,
    $AppSettingsRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> defaultStartOffsetMinutes = const Value.absent(),
                Value<int> defaultIntervalMinutes = const Value.absent(),
                Value<String> defaultSoundId = const Value.absent(),
                Value<bool> defaultVibrationEnabled = const Value.absent(),
                Value<String> defaultRepeatType = const Value.absent(),
                Value<int?> defaultTargetTimeMinutes = const Value.absent(),
              }) => AppSettingsRowsCompanion(
                id: id,
                defaultStartOffsetMinutes: defaultStartOffsetMinutes,
                defaultIntervalMinutes: defaultIntervalMinutes,
                defaultSoundId: defaultSoundId,
                defaultVibrationEnabled: defaultVibrationEnabled,
                defaultRepeatType: defaultRepeatType,
                defaultTargetTimeMinutes: defaultTargetTimeMinutes,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int defaultStartOffsetMinutes,
                required int defaultIntervalMinutes,
                required String defaultSoundId,
                required bool defaultVibrationEnabled,
                required String defaultRepeatType,
                Value<int?> defaultTargetTimeMinutes = const Value.absent(),
              }) => AppSettingsRowsCompanion.insert(
                id: id,
                defaultStartOffsetMinutes: defaultStartOffsetMinutes,
                defaultIntervalMinutes: defaultIntervalMinutes,
                defaultSoundId: defaultSoundId,
                defaultVibrationEnabled: defaultVibrationEnabled,
                defaultRepeatType: defaultRepeatType,
                defaultTargetTimeMinutes: defaultTargetTimeMinutes,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$WakePlanDatabase,
      $AppSettingsRowsTable,
      AppSettingsRow,
      $$AppSettingsRowsTableFilterComposer,
      $$AppSettingsRowsTableOrderingComposer,
      $$AppSettingsRowsTableAnnotationComposer,
      $$AppSettingsRowsTableCreateCompanionBuilder,
      $$AppSettingsRowsTableUpdateCompanionBuilder,
      (
        AppSettingsRow,
        BaseReferences<
          _$WakePlanDatabase,
          $AppSettingsRowsTable,
          AppSettingsRow
        >,
      ),
      AppSettingsRow,
      PrefetchHooks Function()
    >;

class $WakePlanDatabaseManager {
  final _$WakePlanDatabase _db;
  $WakePlanDatabaseManager(this._db);
  $$WakePlanRowsTableTableManager get wakePlanRows =>
      $$WakePlanRowsTableTableManager(_db, _db.wakePlanRows);
  $$AlarmOccurrenceRowsTableTableManager get alarmOccurrenceRows =>
      $$AlarmOccurrenceRowsTableTableManager(_db, _db.alarmOccurrenceRows);
  $$AppSettingsRowsTableTableManager get appSettingsRows =>
      $$AppSettingsRowsTableTableManager(_db, _db.appSettingsRows);
}
