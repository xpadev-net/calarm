@_weakLinked import AlarmKit
import Foundation
import SwiftUI

@available(iOS 26.0, *)
private struct CalarmAlarmMetadata: AlarmMetadata {
  let occurrenceId: String
  let wakePlanId: String
  let targetAt: Date
  let soundId: String
  let vibrationEnabled: Bool
}

struct ScheduleRequest {
  let occurrenceId: String
  let reservationId: String
  let reservationGeneration: Int
  let wakePlanId: String
  let scheduledAt: Date
  let targetAt: Date
  let soundId: String
  let vibrationEnabled: Bool

  init(
    occurrenceId: String,
    reservationId: String,
    reservationGeneration: Int = 0,
    wakePlanId: String,
    scheduledAt: Date,
    targetAt: Date,
    soundId: String,
    vibrationEnabled: Bool
  ) {
    self.occurrenceId = occurrenceId
    self.reservationId = reservationId
    self.reservationGeneration = reservationGeneration
    self.wakePlanId = wakePlanId
    self.scheduledAt = scheduledAt
    self.targetAt = targetAt
    self.soundId = soundId
    self.vibrationEnabled = vibrationEnabled
  }
}

struct ScheduleRow {
  let status: String
  let platformAlarmId: String?
  let failureReason: String?
  let failureMessage: String?
}

struct NativeAlarmSnapshot {
  let platformAlarmId: String
  let status: String
}

@MainActor
protocol AlarmKitNativeClient {
  var isAuthorized: Bool { get }
  func inventory() throws -> [NativeAlarmSnapshot]
  func schedule(id: UUID, request: ScheduleRequest) async throws -> String
  func cancel(id: UUID) throws
}

@available(iOS 26.0, *)
@MainActor
final class SystemAlarmKitClient: AlarmKitNativeClient {
  var isAuthorized: Bool {
    AlarmManager.shared.authorizationState == .authorized
  }

  func inventory() throws -> [NativeAlarmSnapshot] {
    try AlarmManager.shared.alarms.map { alarm in
      NativeAlarmSnapshot(
        platformAlarmId: alarm.id.uuidString,
        status: inventoryStatus(for: alarm.state)
      )
    }
  }

  func schedule(id: UUID, request: ScheduleRequest) async throws -> String {
    let configuration = AlarmManager.AlarmConfiguration<CalarmAlarmMetadata>.alarm(
      schedule: .fixed(request.scheduledAt),
      attributes: alarmAttributes(for: request)
    )
    let alarm = try await AlarmManager.shared.schedule(
      id: id,
      configuration: configuration
    )
    return alarm.id.uuidString
  }

  func cancel(id: UUID) throws {
    try AlarmManager.shared.cancel(id: id)
  }
}

@available(iOS 26.0, *)
private func alarmAttributes(for request: ScheduleRequest) -> AlarmAttributes<CalarmAlarmMetadata> {
  let stopButton = AlarmButton(
    text: "Stop",
    textColor: .white,
    systemImageName: "stop.fill"
  )
  let alert = AlarmPresentation.Alert(
    title: "Calarm",
    stopButton: stopButton
  )
  let presentation = AlarmPresentation(alert: alert)
  let metadata = CalarmAlarmMetadata(
    occurrenceId: request.occurrenceId,
    wakePlanId: request.wakePlanId,
    targetAt: request.targetAt,
    soundId: request.soundId,
    vibrationEnabled: request.vibrationEnabled
  )
  return AlarmAttributes(
    presentation: presentation,
    metadata: metadata,
    tintColor: .orange
  )
}

@available(iOS 26.0, *)
func permissionStatus(_ state: AlarmManager.AuthorizationState) -> String {
  switch state {
  case .notDetermined:
    return "notDetermined"
  case .authorized:
    return "authorized"
  case .denied:
    return "denied"
  @unknown default:
    return "unknown"
  }
}

@available(iOS 26.0, *)
func inventoryStatus(for state: Alarm.State) -> String {
  switch state {
  case .scheduled, .countdown, .paused:
    return "scheduled"
  case .alerting:
    return "ringing"
  @unknown default:
    return "unknown"
  }
}

func inventoryRow(
  record: AlarmMirrorRecord,
  status: String
) -> [String: Any?] {
  [
    "reservationId": record.reservationId,
    "occurrenceId": record.occurrenceId,
    "reservationGeneration": record.generation,
    "wakePlanId": record.wakePlanId,
    "platformAlarmId": record.platformAlarmId,
    "status": status,
  ]
}
