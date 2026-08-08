import Flutter
import Foundation

extension AlarmKitBridge {
  func complete(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async {
      result(value)
    }
  }

  func validateBasePayload(_ arguments: Any?, result: @escaping FlutterResult) -> Bool {
    validatedPayload(arguments, result: result) != nil
  }

  func validatedPayload(
    _ arguments: Any?,
    result: @escaping FlutterResult
  ) -> [String: Any?]? {
    guard let payload = arguments as? [String: Any?] else {
      complete(result, invalidRequest("Arguments must be a map."))
      return nil
    }
    guard intValue(payloadValue(payload, "schemaVersion")) == nativeAlarmSchemaVersion else {
      complete(result, invalidRequest("Unsupported native alarm schemaVersion."))
      return nil
    }
    return payload
  }
}

func baseResponse() -> [String: Any?] {
  ["schemaVersion": nativeAlarmSchemaVersion]
}

func scheduleSuccessRow(
  occurrenceId: String,
  reservationId: String,
  reservationGeneration: Int = 0,
  wakePlanId: String,
  platformAlarmId: String
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "reservationId": reservationId,
    "reservationGeneration": reservationGeneration,
    "wakePlanId": wakePlanId,
    "status": "success",
    "platformAlarmId": platformAlarmId,
  ]
}

func scheduleFailureRow(
  occurrenceId: String,
  reservationId: String,
  reservationGeneration: Int = 0,
  wakePlanId: String,
  reason: String,
  message: String?,
  platformAlarmId: String? = nil
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "reservationId": reservationId,
    "reservationGeneration": reservationGeneration,
    "wakePlanId": wakePlanId,
    "status": "failure",
    "failureReason": reason,
    "failureMessage": message,
    "platformAlarmId": platformAlarmId,
  ]
}

func cancelSuccessRow(
  occurrenceId: String,
  reservationId: String,
  reservationGeneration: Int = 0,
  platformAlarmId: String
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "reservationId": reservationId,
    "reservationGeneration": reservationGeneration,
    "platformAlarmId": platformAlarmId,
    "status": "success",
  ]
}

func cancelFailureRow(
  occurrenceId: String,
  reservationId: String,
  reservationGeneration: Int = 0,
  platformAlarmId: String,
  reason: String,
  message: String?
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "reservationId": reservationId,
    "reservationGeneration": reservationGeneration,
    "platformAlarmId": platformAlarmId,
    "status": "failure",
    "failureReason": reason,
    "failureMessage": message,
  ]
}

func invalidRequest(_ message: String) -> FlutterError {
  FlutterError(code: "invalidRequest", message: message, details: nil)
}

func nonEmptyString(_ value: Any?) -> String? {
  guard let string = stringValue(value), !string.isEmpty else {
    return nil
  }
  return string
}

func payloadValue(_ payload: [String: Any?], _ key: String) -> Any? {
  guard let value = payload[key] else {
    return nil
  }
  return value
}

func stringValue(_ value: Any?) -> String? {
  value as? String
}

func boolValue(_ value: Any?) -> Bool? {
  value as? Bool
}

func intValue(_ value: Any?) -> Int? {
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

func exactNonNegativeInt(_ value: Any?) -> Int? {
  guard let value else { return nil }
  if type(of: value) == Int.self, let integer = value as? Int {
    return integer >= 0 ? integer : nil
  }
  if type(of: value as Any) == Int32.self, let integer = value as? Int32 {
    return integer >= 0 ? Int(integer) : nil
  }
  if type(of: value as Any) == Int64.self, let integer = value as? Int64,
    let exact = Int(exactly: integer)
  {
    return exact >= 0 ? exact : nil
  }
  guard let number = value as? NSNumber else { return nil }
  let encodedType = String(cString: number.objCType)
  guard !["c", "B", "f", "d"].contains(encodedType),
    let exact = Int(number.stringValue),
    exact >= 0
  else { return nil }
  return exact
}

func isoDate(_ value: String) -> Date? {
  ISO8601DateFormatter.calarmFormatter.date(from: value)
}

extension ISO8601DateFormatter {
  static let calarmFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

extension Sequence {
  func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
    var values: [T] = []
    for element in self {
      let value = await transform(element)
      values.append(value)
    }
    return values
  }
}
