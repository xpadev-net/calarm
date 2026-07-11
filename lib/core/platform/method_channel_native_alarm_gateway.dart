import 'package:flutter/services.dart';

import 'native_alarm_gateway.dart';

const int nativeAlarmChannelSchemaVersion = 1;
const String nativeAlarmChannelName = 'net.xpadev.calarm/native_alarm';

class MethodChannelNativeAlarmGateway implements NativeAlarmGateway {
  MethodChannelNativeAlarmGateway({
    MethodChannel channel = const MethodChannel(nativeAlarmChannelName),
  }) : this._(channel);

  MethodChannelNativeAlarmGateway._(this._channel);

  final MethodChannel _channel;

  @override
  Future<NativeAlarmCapability> getCapability() async {
    final response = await _invokeMap('getCapability', _basePayload());
    _verifySchemaVersion(response);
    return NativeAlarmCapability(
      permissionStatus: _permissionStatus(
        _requiredString(response, 'permissionStatus'),
      ),
      canScheduleAlarms: _requiredBool(response, 'canScheduleAlarms'),
      canRequestPermission: _requiredBool(response, 'canRequestPermission'),
      maxPendingAlarms: _optionalInt(response, 'maxPendingAlarms'),
      requiresExactAlarmPermission: _optionalBool(
        response,
        'requiresExactAlarmPermission',
      ),
      requiresNotificationPermission: _optionalBool(
        response,
        'requiresNotificationPermission',
      ),
      requiresFullScreenIntentPermission: _optionalBool(
        response,
        'requiresFullScreenIntentPermission',
      ),
      requiresNotificationChannelSetup: _optionalBool(
        response,
        'requiresNotificationChannelSetup',
      ),
      supportsTestAlarm: _optionalBool(
        response,
        'supportsTestAlarm',
        defaultValue: true,
      ),
      supportsInventory: _optionalBool(response, 'supportsInventory'),
    );
  }

  @override
  Future<NativeAlarmPermissionResult> requestPermission() async {
    final response = await _invokeMap(
      'requestPermissionIfNeeded',
      _basePayload(),
    );
    _verifySchemaVersion(response);
    return NativeAlarmPermissionResult(
      status: _permissionRequestStatus(_requiredString(response, 'status')),
      permissionStatus: _permissionStatus(
        _requiredString(response, 'permissionStatus'),
      ),
    );
  }

  @override
  Future<ScheduleResult> scheduleOccurrences(
    List<NativeAlarmScheduleRequest> occurrences,
  ) async {
    try {
      final response = await _invokeMap('scheduleOccurrences', {
        ..._basePayload(),
        'occurrences': occurrences.map(_scheduleRequestPayload).toList(),
      });
      _verifySchemaVersion(response);
      final results = _requiredList(
        response,
        'occurrences',
      ).map(_scheduleOccurrenceResult).toList();
      return ScheduleResult.fromRequestResults(
        requests: occurrences,
        results: results,
      );
    } on PlatformException catch (error) {
      return ScheduleResult.fromRequestResults(
        requests: occurrences,
        results: occurrences
            .map(
              (request) => ScheduleOccurrenceResult.failure(
                occurrenceId: request.occurrenceId,
                wakePlanId: request.wakePlanId,
                reason: _scheduleFailureReason(error.code),
                message: error.message,
                reservationId: request.reservationId,
              ),
            )
            .toList(),
      );
    }
  }

  @override
  Future<CancelResult> cancelOccurrences(
    List<NativeAlarmCancelRequest> alarms,
  ) async {
    return _cancel('cancelOccurrences', alarms);
  }

  @override
  Future<CancelResult> cancelPlan(List<NativeAlarmCancelRequest> alarms) async {
    return _cancel('cancelPlan', alarms);
  }

  @override
  Future<TestAlarmScheduleResult> scheduleTestAlarm(
    NativeTestAlarmScheduleRequest request,
  ) async {
    try {
      final response = await _invokeMap('scheduleTestAlarm', {
        ..._basePayload(),
        'fireAfterMillis': request.fireAfter.inMilliseconds,
        'soundId': request.soundId,
        'vibrationEnabled': request.vibrationEnabled,
      });
      _verifySchemaVersion(response);
      final status = _scheduleResultStatus(_requiredString(response, 'status'));
      if (status == ScheduleResultStatus.success) {
        return TestAlarmScheduleResult.success(
          platformAlarmId: _requiredString(response, 'platformAlarmId'),
        );
      }
      return TestAlarmScheduleResult.failure(
        reason: _scheduleFailureReason(
          _requiredString(response, 'failureReason'),
        ),
        message: _optionalString(response, 'failureMessage'),
      );
    } on PlatformException catch (error) {
      return TestAlarmScheduleResult.failure(
        reason: _scheduleFailureReason(error.code),
        message: error.message,
      );
    }
  }

  @override
  Future<NativeAlarmInventoryResult> getInventory() async {
    try {
      final response = await _invokeMap('getInventory', _basePayload());
      _verifySchemaVersion(response);
      final rows = _requiredList(
        response,
        'reservations',
      ).map(_inventoryRow).toList();
      return NativeAlarmInventoryResult.success(rows: rows);
    } on MissingPluginException catch (error) {
      return NativeAlarmInventoryResult.failure(
        reason: NativeAlarmInventoryFailureReason.unavailable,
        message: error.message,
      );
    } on PlatformException catch (error) {
      return NativeAlarmInventoryResult.failure(
        reason: _inventoryFailureReason(error.code),
        message: error.message,
      );
    } on FormatException catch (error) {
      return NativeAlarmInventoryResult.failure(
        reason: NativeAlarmInventoryFailureReason.corrupt,
        message: error.message,
      );
    } on ArgumentError catch (error) {
      return NativeAlarmInventoryResult.failure(
        reason: NativeAlarmInventoryFailureReason.corrupt,
        message: error.message,
      );
    } on TypeError catch (error) {
      return NativeAlarmInventoryResult.failure(
        reason: NativeAlarmInventoryFailureReason.corrupt,
        message: error.toString(),
      );
    }
  }

  Future<CancelResult> _cancel(
    String method,
    List<NativeAlarmCancelRequest> alarms,
  ) async {
    try {
      final response = await _invokeMap(method, {
        ..._basePayload(),
        'alarms': alarms.map(_cancelRequestPayload).toList(),
      });
      _verifySchemaVersion(response);
      final results = _requiredList(
        response,
        'alarms',
      ).map(_cancelAlarmResult).toList();
      return CancelResult.fromRequestResults(
        requests: alarms,
        results: results,
      );
    } on PlatformException catch (error) {
      return CancelResult.fromRequestResults(
        requests: alarms,
        results: alarms
            .map(
              (alarm) => CancelAlarmResult.failure(
                occurrenceId: alarm.occurrenceId,
                platformAlarmId: alarm.platformAlarmId,
                reason: _cancelFailureReason(error.code),
                message: error.message,
                reservationId: alarm.reservationId,
              ),
            )
            .toList(),
      );
    }
  }

  Future<Map<String, Object?>> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final response = await _channel.invokeMethod<Object?>(method, arguments);
    return _asMap(response, '$method result');
  }
}

Map<String, Object?> _basePayload() {
  return <String, Object?>{'schemaVersion': nativeAlarmChannelSchemaVersion};
}

Map<String, Object?> _scheduleRequestPayload(
  NativeAlarmScheduleRequest request,
) {
  return <String, Object?>{
    'occurrenceId': request.occurrenceId,
    'reservationId': request.reservationId,
    'wakePlanId': request.wakePlanId,
    'scheduledAt': request.scheduledAt.toUtc().toIso8601String(),
    'targetAt': request.targetAt.toUtc().toIso8601String(),
    'indexInPlan': request.indexInPlan,
    'totalInPlan': request.totalInPlan,
    'soundId': request.soundId,
    'vibrationEnabled': request.vibrationEnabled,
  };
}

Map<String, Object?> _cancelRequestPayload(NativeAlarmCancelRequest request) {
  return <String, Object?>{
    'occurrenceId': request.occurrenceId,
    'reservationId': request.reservationId,
    'platformAlarmId': request.platformAlarmId,
  };
}

ScheduleOccurrenceResult _scheduleOccurrenceResult(Object? value) {
  final map = _asMap(value, 'schedule occurrence result');
  final status = _scheduleOccurrenceStatus(_requiredString(map, 'status'));
  if (status == ScheduleOccurrenceStatus.success) {
    return ScheduleOccurrenceResult.success(
      occurrenceId: _requiredString(map, 'occurrenceId'),
      wakePlanId: _requiredString(map, 'wakePlanId'),
      platformAlarmId: _requiredString(map, 'platformAlarmId'),
      reservationId: _optionalString(map, 'reservationId'),
    );
  }
  return ScheduleOccurrenceResult.failure(
    occurrenceId: _requiredString(map, 'occurrenceId'),
    wakePlanId: _requiredString(map, 'wakePlanId'),
    reason: _scheduleFailureReason(_requiredString(map, 'failureReason')),
    message: _optionalString(map, 'failureMessage'),
    platformAlarmId: _optionalString(map, 'platformAlarmId'),
    reservationId: _optionalString(map, 'reservationId'),
  );
}

CancelAlarmResult _cancelAlarmResult(Object? value) {
  final map = _asMap(value, 'cancel alarm result');
  final status = _cancelAlarmStatus(_requiredString(map, 'status'));
  if (status == CancelAlarmStatus.success) {
    return CancelAlarmResult.success(
      occurrenceId: _requiredString(map, 'occurrenceId'),
      platformAlarmId: _requiredString(map, 'platformAlarmId'),
      reservationId: _optionalString(map, 'reservationId'),
    );
  }
  return CancelAlarmResult.failure(
    occurrenceId: _requiredString(map, 'occurrenceId'),
    platformAlarmId: _requiredString(map, 'platformAlarmId'),
    reason: _cancelFailureReason(_requiredString(map, 'failureReason')),
    message: _optionalString(map, 'failureMessage'),
    reservationId: _optionalString(map, 'reservationId'),
  );
}

NativeAlarmInventoryRow _inventoryRow(Object? value) {
  final map = _asMap(value, 'native inventory row');
  return NativeAlarmInventoryRow.create(
    reservationId: _requiredString(map, 'reservationId'),
    occurrenceId: _requiredString(map, 'occurrenceId'),
    wakePlanId: _requiredString(map, 'wakePlanId'),
    platformAlarmId: _requiredString(map, 'platformAlarmId'),
    status: _inventoryReservationStatus(_requiredString(map, 'status')),
  );
}

void _verifySchemaVersion(Map<String, Object?> map) {
  final schemaVersion = map['schemaVersion'];
  if (schemaVersion != nativeAlarmChannelSchemaVersion) {
    throw FormatException(
      'Unsupported native alarm schemaVersion: $schemaVersion',
    );
  }
}

Map<String, Object?> _asMap(Object? value, String name) {
  if (value is! Map) {
    throw FormatException('$name must be a Map.');
  }
  return value.cast<String, Object?>();
}

List<Object?> _requiredList(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List) {
    throw FormatException('$key must be a List.');
  }
  return value.cast<Object?>();
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty String.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be null or a non-empty String.');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw FormatException('$key must be a bool.');
  }
  return value;
}

bool _optionalBool(
  Map<String, Object?> map,
  String key, {
  bool defaultValue = false,
}) {
  final value = map[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is! bool) {
    throw FormatException('$key must be a bool.');
  }
  return value;
}

int? _optionalInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw FormatException('$key must be an int.');
  }
  return value;
}

NativeAlarmPermissionStatus _permissionStatus(String value) {
  return switch (value) {
    'unknown' => NativeAlarmPermissionStatus.unknown,
    'notDetermined' => NativeAlarmPermissionStatus.notDetermined,
    'authorized' => NativeAlarmPermissionStatus.authorized,
    'denied' => NativeAlarmPermissionStatus.denied,
    'restricted' => NativeAlarmPermissionStatus.restricted,
    'unavailable' => NativeAlarmPermissionStatus.unavailable,
    _ => throw FormatException('Unknown permissionStatus: $value'),
  };
}

NativeAlarmPermissionRequestStatus _permissionRequestStatus(String value) {
  return switch (value) {
    'granted' => NativeAlarmPermissionRequestStatus.granted,
    'denied' => NativeAlarmPermissionRequestStatus.denied,
    'unavailable' => NativeAlarmPermissionRequestStatus.unavailable,
    _ => throw FormatException('Unknown permission request status: $value'),
  };
}

ScheduleResultStatus _scheduleResultStatus(String value) {
  return switch (value) {
    'success' => ScheduleResultStatus.success,
    'permissionMissing' => ScheduleResultStatus.permissionMissing,
    'osConstraint' => ScheduleResultStatus.osConstraint,
    'partialFailure' => ScheduleResultStatus.partialFailure,
    'failure' => ScheduleResultStatus.failure,
    _ => throw FormatException('Unknown schedule result status: $value'),
  };
}

ScheduleOccurrenceStatus _scheduleOccurrenceStatus(String value) {
  return switch (value) {
    'success' => ScheduleOccurrenceStatus.success,
    'failure' => ScheduleOccurrenceStatus.failure,
    _ => throw FormatException('Unknown schedule occurrence status: $value'),
  };
}

ScheduleFailureReason _scheduleFailureReason(String value) {
  return switch (value) {
    'permissionMissing' ||
    'PERMISSION_MISSING' => ScheduleFailureReason.permissionMissing,
    'osConstraint' || 'OS_CONSTRAINT' => ScheduleFailureReason.osConstraint,
    'invalidRequest' ||
    'INVALID_REQUEST' => ScheduleFailureReason.invalidRequest,
    'nativeError' || 'NATIVE_ERROR' => ScheduleFailureReason.nativeError,
    'unavailable' || 'UNAVAILABLE' => ScheduleFailureReason.unavailable,
    'unknown' || 'UNKNOWN' => ScheduleFailureReason.unknown,
    _ => ScheduleFailureReason.nativeError,
  };
}

CancelAlarmStatus _cancelAlarmStatus(String value) {
  return switch (value) {
    'success' => CancelAlarmStatus.success,
    'failure' => CancelAlarmStatus.failure,
    _ => throw FormatException('Unknown cancel alarm status: $value'),
  };
}

CancelFailureReason _cancelFailureReason(String value) {
  return switch (value) {
    'missingPlatformAlarmId' ||
    'MISSING_PLATFORM_ALARM_ID' => CancelFailureReason.missingPlatformAlarmId,
    'invalidRequest' || 'INVALID_REQUEST' => CancelFailureReason.invalidRequest,
    'nativeError' || 'NATIVE_ERROR' => CancelFailureReason.nativeError,
    'unavailable' || 'UNAVAILABLE' => CancelFailureReason.unavailable,
    'unknown' || 'UNKNOWN' => CancelFailureReason.unknown,
    _ => CancelFailureReason.nativeError,
  };
}

NativeAlarmReservationStatus _inventoryReservationStatus(String value) {
  return switch (value) {
    'scheduled' => NativeAlarmReservationStatus.scheduled,
    'ringing' => NativeAlarmReservationStatus.ringing,
    'stopped' => NativeAlarmReservationStatus.stopped,
    'unknown' => NativeAlarmReservationStatus.unknown,
    _ => throw FormatException('Unknown native inventory status: $value'),
  };
}

NativeAlarmInventoryFailureReason _inventoryFailureReason(String value) {
  return switch (value) {
    'unavailable' ||
    'UNAVAILABLE' => NativeAlarmInventoryFailureReason.unavailable,
    'corrupt' || 'CORRUPT' => NativeAlarmInventoryFailureReason.corrupt,
    // `unknown` is a row/status classification, not a read outcome. Keep
    // native read failures on the failure path so reconciliation emits the
    // explicit `readFailure` issue rather than conflating the two.
    'unknown' || 'UNKNOWN' => NativeAlarmInventoryFailureReason.nativeError,
    _ => NativeAlarmInventoryFailureReason.nativeError,
  };
}
