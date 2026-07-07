import AlarmKit
import Flutter
import Foundation
import SwiftUI

private let nativeAlarmChannelName = "net.xpadev.calarm/native_alarm"
private let nativeAlarmSchemaVersion = 1

final class AlarmKitBridge {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: nativeAlarmChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCapability":
      guard validateBasePayload(call.arguments, result: result) else { return }
      result(getCapability())
    case "requestPermissionIfNeeded":
      guard validateBasePayload(call.arguments, result: result) else { return }
      requestPermission(result: result)
    case "scheduleOccurrences":
      scheduleOccurrences(call.arguments, result: result)
    case "cancelOccurrences", "cancelPlan":
      cancelAlarms(call.arguments, result: result)
    case "scheduleTestAlarm":
      scheduleTestAlarm(call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getCapability() -> [String: Any?] {
    var response = baseResponse()
    guard #available(iOS 26.0, *) else {
      response["permissionStatus"] = "unavailable"
      response["canScheduleAlarms"] = false
      response["canRequestPermission"] = false
      response["maxPendingAlarms"] = nil
      response["requiresExactAlarmPermission"] = false
      response["requiresNotificationPermission"] = false
      response["requiresFullScreenIntentPermission"] = false
      response["requiresNotificationChannelSetup"] = false
      response["supportsTestAlarm"] = false
      return response
    }

    let authorizationState = AlarmManager.shared.authorizationState
    response["permissionStatus"] = permissionStatus(authorizationState)
    response["canScheduleAlarms"] = authorizationState == .authorized
    response["canRequestPermission"] = authorizationState == .notDetermined
    response["maxPendingAlarms"] = nil
    response["requiresExactAlarmPermission"] = false
    response["requiresNotificationPermission"] = false
    response["requiresFullScreenIntentPermission"] = false
    response["requiresNotificationChannelSetup"] = false
    response["supportsTestAlarm"] = true
    return response
  }

  private func requestPermission(result: @escaping FlutterResult) {
    guard #available(iOS 26.0, *) else {
      var response = baseResponse()
      response["status"] = "unavailable"
      response["permissionStatus"] = "unavailable"
      result(response)
      return
    }

    Task {
      do {
        let state = try await AlarmManager.shared.requestAuthorization()
        var response = baseResponse()
        response["status"] = state == .authorized ? "granted" : "denied"
        response["permissionStatus"] = permissionStatus(state)
        result(response)
      } catch {
        result(
          FlutterError(
            code: "nativeError",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func scheduleOccurrences(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let payload = validatedPayload(arguments, result: result) else { return }
    guard let occurrencePayloads = payload["occurrences"] as? [[String: Any?]] else {
      result(invalidRequest("occurrences must be a list."))
      return
    }

    Task {
      let rows = await occurrencePayloads.asyncMap { payload in
        await scheduleOccurrence(payload)
      }
      var response = baseResponse()
      response["occurrences"] = rows
      result(response)
    }
  }

  private func cancelAlarms(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let payload = validatedPayload(arguments, result: result) else { return }
    guard let alarmPayloads = payload["alarms"] as? [[String: Any?]] else {
      result(invalidRequest("alarms must be a list."))
      return
    }

    let rows = alarmPayloads.map(cancelAlarm)
    var response = baseResponse()
    response["alarms"] = rows
    result(response)
  }

  private func scheduleTestAlarm(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let payload = validatedPayload(arguments, result: result) else { return }
    let soundId = stringValue(payloadValue(payload, "soundId")) ?? "default"
    let vibrationEnabled = boolValue(payloadValue(payload, "vibrationEnabled")) ?? true

    guard let fireAfterMillis = intValue(payloadValue(payload, "fireAfterMillis")),
      fireAfterMillis > 0
    else {
      var response = baseResponse()
      response["status"] = "failure"
      response["failureReason"] = "invalidRequest"
      response["failureMessage"] = "fireAfterMillis must be a positive integer."
      result(response)
      return
    }

    let scheduledAt = Date().addingTimeInterval(TimeInterval(fireAfterMillis) / 1000.0)
    let request = ScheduleRequest(
      occurrenceId: "test-\(UUID().uuidString)",
      wakePlanId: "test",
      scheduledAt: scheduledAt,
      targetAt: scheduledAt,
      soundId: soundId,
      vibrationEnabled: vibrationEnabled
    )

    Task {
      let row = await scheduleAlarm(request)
      var response = baseResponse()
      if row.status == "success", let platformAlarmId = row.platformAlarmId {
        response["status"] = "success"
        response["platformAlarmId"] = platformAlarmId
      } else {
        response["status"] = "failure"
        response["failureReason"] = row.failureReason ?? "nativeError"
        response["failureMessage"] = row.failureMessage
      }
      result(response)
    }
  }

  private func scheduleOccurrence(_ payload: [String: Any?]) async -> [String: Any?] {
    guard
      let occurrenceId = nonEmptyString(payloadValue(payload, "occurrenceId")),
      let wakePlanId = nonEmptyString(payloadValue(payload, "wakePlanId")),
      let scheduledAtString = nonEmptyString(payloadValue(payload, "scheduledAt")),
      let targetAtString = nonEmptyString(payloadValue(payload, "targetAt")),
      let scheduledAt = isoDate(scheduledAtString),
      let targetAt = isoDate(targetAtString)
    else {
      return scheduleFailureRow(
        occurrenceId: stringValue(payloadValue(payload, "occurrenceId")) ?? "",
        wakePlanId: stringValue(payloadValue(payload, "wakePlanId")) ?? "",
        reason: "invalidRequest",
        message: "Occurrence requires occurrenceId, wakePlanId, scheduledAt, and targetAt."
      )
    }

    let request = ScheduleRequest(
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
      scheduledAt: scheduledAt,
      targetAt: targetAt,
      soundId: stringValue(payloadValue(payload, "soundId")) ?? "default",
      vibrationEnabled: boolValue(payloadValue(payload, "vibrationEnabled")) ?? true
    )
    let row = await scheduleAlarm(request)
    if row.status == "success" {
      return scheduleSuccessRow(
        occurrenceId: occurrenceId,
        wakePlanId: wakePlanId,
        platformAlarmId: row.platformAlarmId ?? ""
      )
    }
    return scheduleFailureRow(
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
      reason: row.failureReason ?? "nativeError",
      message: row.failureMessage,
      platformAlarmId: row.platformAlarmId
    )
  }

  private func cancelAlarm(_ payload: [String: Any?]) -> [String: Any?] {
    guard let occurrenceId = nonEmptyString(payloadValue(payload, "occurrenceId")) else {
      return cancelFailureRow(
        occurrenceId: "",
        platformAlarmId: stringValue(payloadValue(payload, "platformAlarmId")) ?? "",
        reason: "invalidRequest",
        message: "occurrenceId is required."
      )
    }
    guard let platformAlarmId = nonEmptyString(payloadValue(payload, "platformAlarmId")) else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        platformAlarmId: "",
        reason: "missingPlatformAlarmId",
        message: "platformAlarmId is required."
      )
    }
    guard #available(iOS 26.0, *) else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        platformAlarmId: platformAlarmId,
        reason: "unavailable",
        message: "AlarmKit requires iOS 26.0 or newer."
      )
    }
    guard let alarmId = UUID(uuidString: platformAlarmId) else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        platformAlarmId: platformAlarmId,
        reason: "invalidRequest",
        message: "platformAlarmId must be an AlarmKit UUID."
      )
    }

    do {
      try AlarmManager.shared.cancel(id: alarmId)
      return cancelSuccessRow(occurrenceId: occurrenceId, platformAlarmId: platformAlarmId)
    } catch {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        platformAlarmId: platformAlarmId,
        reason: "nativeError",
        message: error.localizedDescription
      )
    }
  }

  private func scheduleAlarm(_ request: ScheduleRequest) async -> ScheduleRow {
    guard #available(iOS 26.0, *) else {
      return ScheduleRow(
        status: "failure",
        platformAlarmId: nil,
        failureReason: "unavailable",
        failureMessage: "AlarmKit requires iOS 26.0 or newer."
      )
    }

    guard AlarmManager.shared.authorizationState == .authorized else {
      return ScheduleRow(
        status: "failure",
        platformAlarmId: nil,
        failureReason: "permissionMissing",
        failureMessage: "AlarmKit authorization is required."
      )
    }

    let alarmId = UUID()
    do {
      let attributes = alarmAttributes(for: request)
      let configuration = AlarmManager.AlarmConfiguration<CalarmAlarmMetadata>.alarm(
        schedule: .fixed(request.scheduledAt),
        attributes: attributes
      )
      let alarm = try await AlarmManager.shared.schedule(
        id: alarmId,
        configuration: configuration
      )
      return ScheduleRow(
        status: "success",
        platformAlarmId: alarm.id.uuidString,
        failureReason: nil,
        failureMessage: nil
      )
    } catch AlarmManager.AlarmError.maximumLimitReached {
      return ScheduleRow(
        status: "failure",
        platformAlarmId: nil,
        failureReason: "osConstraint",
        failureMessage: "AlarmKit maximum pending alarm limit was reached."
      )
    } catch {
      return ScheduleRow(
        status: "failure",
        platformAlarmId: nil,
        failureReason: "nativeError",
        failureMessage: error.localizedDescription
      )
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

  private func validateBasePayload(_ arguments: Any?, result: FlutterResult) -> Bool {
    validatedPayload(arguments, result: result) != nil
  }

  private func validatedPayload(_ arguments: Any?, result: FlutterResult) -> [String: Any?]? {
    guard let payload = arguments as? [String: Any?] else {
      result(invalidRequest("Arguments must be a map."))
      return nil
    }
    guard intValue(payloadValue(payload, "schemaVersion")) == nativeAlarmSchemaVersion else {
      result(invalidRequest("Unsupported native alarm schemaVersion."))
      return nil
    }
    return payload
  }
}

@available(iOS 26.0, *)
private struct CalarmAlarmMetadata: AlarmMetadata {
  let occurrenceId: String
  let wakePlanId: String
  let targetAt: Date
  let soundId: String
  let vibrationEnabled: Bool
}

private struct ScheduleRequest {
  let occurrenceId: String
  let wakePlanId: String
  let scheduledAt: Date
  let targetAt: Date
  let soundId: String
  let vibrationEnabled: Bool
}

private struct ScheduleRow {
  let status: String
  let platformAlarmId: String?
  let failureReason: String?
  let failureMessage: String?
}

private func baseResponse() -> [String: Any?] {
  ["schemaVersion": nativeAlarmSchemaVersion]
}

@available(iOS 26.0, *)
private func permissionStatus(_ state: AlarmManager.AuthorizationState) -> String {
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

private func scheduleSuccessRow(
  occurrenceId: String,
  wakePlanId: String,
  platformAlarmId: String
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "wakePlanId": wakePlanId,
    "status": "success",
    "platformAlarmId": platformAlarmId,
  ]
}

private func scheduleFailureRow(
  occurrenceId: String,
  wakePlanId: String,
  reason: String,
  message: String?,
  platformAlarmId: String? = nil
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "wakePlanId": wakePlanId,
    "status": "failure",
    "failureReason": reason,
    "failureMessage": message,
    "platformAlarmId": platformAlarmId,
  ]
}

private func cancelSuccessRow(occurrenceId: String, platformAlarmId: String) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "platformAlarmId": platformAlarmId,
    "status": "success",
  ]
}

private func cancelFailureRow(
  occurrenceId: String,
  platformAlarmId: String,
  reason: String,
  message: String?
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "platformAlarmId": platformAlarmId,
    "status": "failure",
    "failureReason": reason,
    "failureMessage": message,
  ]
}

private func invalidRequest(_ message: String) -> FlutterError {
  FlutterError(code: "invalidRequest", message: message, details: nil)
}

private func nonEmptyString(_ value: Any?) -> String? {
  guard let string = stringValue(value), !string.isEmpty else {
    return nil
  }
  return string
}

private func payloadValue(_ payload: [String: Any?], _ key: String) -> Any? {
  guard let value = payload[key] else {
    return nil
  }
  return value
}

private func stringValue(_ value: Any?) -> String? {
  value as? String
}

private func boolValue(_ value: Any?) -> Bool? {
  value as? Bool
}

private func intValue(_ value: Any?) -> Int? {
  if let value = value as? Int {
    return value
  }
  if let value = value as? Int64 {
    return Int(value)
  }
  if let value = value as? NSNumber {
    return value.intValue
  }
  return nil
}

private func isoDate(_ value: String) -> Date? {
  ISO8601DateFormatter.calarmFormatter.date(from: value)
}

private extension ISO8601DateFormatter {
  static let calarmFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

private extension Sequence {
  func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
    var values: [T] = []
    for element in self {
      let value = await transform(element)
      values.append(value)
    }
    return values
  }
}
