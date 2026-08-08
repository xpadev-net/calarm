import '../../../core/platform/native_alarm_gateway.dart';
import '../domain/wake_plan_domain.dart';
import 'wake_plan_service_internal_models.dart';

enum AlarmOccurrenceToggleStatus {
  enabled,
  disabled,
  invalidState,
  cancelFailed,
  scheduleFailed,
  recoveryRequired,
}

class AlarmOccurrenceToggleResult {
  const AlarmOccurrenceToggleResult._({
    required this.status,
    required this.occurrence,
    required this.warning,
    required this.databaseState,
    required this.persistenceError,
    required this.scheduleResult,
    required this.cancelResult,
    required this.compensationScheduleResult,
    required this.compensationCancelResult,
  });

  factory AlarmOccurrenceToggleResult.success({
    required AlarmOccurrenceToggleStatus status,
    required AlarmOccurrence occurrence,
    ScheduleResult? scheduleResult,
    CancelResult? cancelResult,
  }) {
    return AlarmOccurrenceToggleResult._(
      status: status,
      occurrence: occurrence,
      warning: null,
      databaseState: WakePlanDatabaseState.persisted,
      persistenceError: null,
      scheduleResult: scheduleResult,
      cancelResult: cancelResult,
      compensationScheduleResult: null,
      compensationCancelResult: null,
    );
  }

  factory AlarmOccurrenceToggleResult.failure({
    required AlarmOccurrenceToggleStatus status,
    required String warning,
    AlarmOccurrence? occurrence,
    WakePlanDatabaseState databaseState = WakePlanDatabaseState.persisted,
    String? persistenceError,
    ScheduleResult? scheduleResult,
    CancelResult? cancelResult,
    ScheduleResult? compensationScheduleResult,
    CancelResult? compensationCancelResult,
  }) {
    return AlarmOccurrenceToggleResult._(
      status: status,
      occurrence: occurrence,
      warning: warning,
      databaseState: databaseState,
      persistenceError: persistenceError,
      scheduleResult: scheduleResult,
      cancelResult: cancelResult,
      compensationScheduleResult: compensationScheduleResult,
      compensationCancelResult: compensationCancelResult,
    );
  }

  final AlarmOccurrenceToggleStatus status;
  final AlarmOccurrence? occurrence;
  final String? warning;
  final WakePlanDatabaseState databaseState;
  final String? persistenceError;
  final ScheduleResult? scheduleResult;
  final CancelResult? cancelResult;
  final ScheduleResult? compensationScheduleResult;
  final CancelResult? compensationCancelResult;

  bool get isSuccess =>
      status == AlarmOccurrenceToggleStatus.enabled ||
      status == AlarmOccurrenceToggleStatus.disabled;
}

enum WakePlanSchedulingStatus {
  scheduled,
  scheduleFailed,
  cancelFailed,
  recoveryRequired,
  deleted,
}

enum WakePlanChangeState { pendingChange, committed, failed, recoveryRequired }

enum WakePlanDatabaseState { persisted, unknown }

class WakePlanSchedulingResult {
  WakePlanSchedulingResult({
    required this.wakePlanId,
    required this.status,
    required this.changeState,
    required this.scheduleResult,
    required List<AlarmOccurrence> occurrences,
    this.cancelResult,
    this.warning,
    this.compensationScheduleResult,
    this.compensationCancelResult,
    this.databaseState = WakePlanDatabaseState.persisted,
    this.persistenceError,
  }) : occurrences = List.unmodifiable(occurrences);

  final String wakePlanId;
  final WakePlanSchedulingStatus status;
  final WakePlanChangeState changeState;
  final ScheduleResult scheduleResult;
  final CancelResult? cancelResult;
  final List<AlarmOccurrence> occurrences;
  final WakePlanSchedulingWarning? warning;
  final ScheduleResult? compensationScheduleResult;
  final CancelResult? compensationCancelResult;
  final WakePlanDatabaseState databaseState;
  final String? persistenceError;

  bool get isSuccess => warning == null;
}

class WakePlanSchedulingWarning {
  const WakePlanSchedulingWarning({
    required this.kind,
    required this.message,
    this.scheduleStatus,
    this.cancelStatus,
    this.scheduleFailureReasons = const {},
    this.cancelFailureReasons = const {},
  });

  factory WakePlanSchedulingWarning.scheduleFailed(ScheduleResult result) {
    return WakePlanSchedulingWarning(
      kind: WakePlanSchedulingWarningKind.scheduleFailed,
      message: _scheduleWarningMessage(result.status),
      scheduleStatus: result.status,
      scheduleFailureReasons: result.occurrences
          .map((occurrence) => occurrence.failureReason)
          .whereType<ScheduleFailureReason>()
          .toSet(),
    );
  }

  factory WakePlanSchedulingWarning.emptySchedule() {
    return const WakePlanSchedulingWarning(
      kind: WakePlanSchedulingWarningKind.scheduleFailed,
      message: 'No future alarm occurrence could be scheduled.',
      scheduleStatus: ScheduleResultStatus.failure,
    );
  }

  factory WakePlanSchedulingWarning.cancelFailed(
    WakePlanCancelFutureResult result,
  ) {
    return WakePlanSchedulingWarning(
      kind: WakePlanSchedulingWarningKind.cancelFailed,
      message: 'Some existing alarms could not be cancelled.',
      cancelStatus: result.cancelResult.status,
      cancelFailureReasons: result.cancelResult.alarms
          .map((alarm) => alarm.failureReason)
          .whereType<CancelFailureReason>()
          .toSet(),
    );
  }

  factory WakePlanSchedulingWarning.recoveryRequired(String message) {
    return WakePlanSchedulingWarning(
      kind: WakePlanSchedulingWarningKind.recoveryRequired,
      message: message,
    );
  }

  final WakePlanSchedulingWarningKind kind;
  final String message;
  final ScheduleResultStatus? scheduleStatus;
  final CancelResultStatus? cancelStatus;
  final Set<ScheduleFailureReason> scheduleFailureReasons;
  final Set<CancelFailureReason> cancelFailureReasons;
}

enum WakePlanSchedulingWarningKind {
  scheduleFailed,
  cancelFailed,
  recoveryRequired,
}

String _scheduleWarningMessage(ScheduleResultStatus status) {
  return switch (status) {
    ScheduleResultStatus.permissionMissing =>
      'Alarm permission is required before alarms can be scheduled.',
    ScheduleResultStatus.osConstraint =>
      'The operating system blocked alarm scheduling.',
    ScheduleResultStatus.partialFailure =>
      'Some alarms could not be scheduled.',
    ScheduleResultStatus.failure => 'Alarms could not be scheduled.',
    ScheduleResultStatus.success => 'Alarms could not be scheduled.',
  };
}
