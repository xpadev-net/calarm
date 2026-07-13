import AlarmKit
import CryptoKit
import Flutter
import Foundation
import SwiftUI

private let nativeAlarmChannelName = "net.xpadev.calarm/native_alarm"
private let nativeAlarmSchemaVersion = 1
private let nativeAlarmMirrorKey = "net.xpadev.calarm/native_alarm_mirror"

@MainActor
final class AlarmKitBridge {
  private let channel: FlutterMethodChannel?
  private var alarmObservationTask: Task<Void, Never>?
  private let scheduleCoordinator = AlarmScheduleCoordinator()
  private var pendingNativeAlarmIds = Set<String>()
  private let nativeClient: (any AlarmKitNativeClient)?

  init(
    messenger: FlutterBinaryMessenger,
    nativeClient: (any AlarmKitNativeClient)? = nil
  ) {
    let methodChannel = FlutterMethodChannel(
      name: nativeAlarmChannelName,
      binaryMessenger: messenger
    )
    channel = methodChannel
    self.nativeClient = nativeClient
    methodChannel.setMethodCallHandler(handle)
    if #available(iOS 26.0, *) {
      alarmObservationTask = Task { @MainActor [weak self] in
        await self?.observeAlarmUpdates()
      }
    }
  }

  init(nativeClient: any AlarmKitNativeClient) {
    channel = nil
    self.nativeClient = nativeClient
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCapability":
      guard validateBasePayload(call.arguments, result: result) else { return }
      complete(result, getCapability())
    case "requestPermissionIfNeeded":
      guard validateBasePayload(call.arguments, result: result) else { return }
      requestPermission(result: result)
    case "getInventory":
      guard validateBasePayload(call.arguments, result: result) else { return }
      getInventory(result: result)
    case "scheduleOccurrences":
      scheduleOccurrences(call.arguments, result: result)
    case "cancelOccurrences", "cancelPlan":
      cancelAlarms(call.arguments, result: result)
    case "scheduleTestAlarm":
      scheduleTestAlarm(call.arguments, result: result)
    default:
      complete(result, FlutterMethodNotImplemented)
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
      response["supportsInventory"] = false
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
    response["supportsInventory"] = true
    return response
  }

  private func requestPermission(result: @escaping FlutterResult) {
    guard #available(iOS 26.0, *) else {
      var response = baseResponse()
      response["status"] = "unavailable"
      response["permissionStatus"] = "unavailable"
      complete(result, response)
      return
    }

    Task { @MainActor in
      do {
        let state = try await AlarmManager.shared.requestAuthorization()
        var response = baseResponse()
        response["status"] = state == .authorized ? "granted" : "denied"
        response["permissionStatus"] = permissionStatus(state)
        complete(result, response)
      } catch {
        complete(
          result,
          FlutterError(
            code: "nativeError",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func getInventory(result: @escaping FlutterResult) {
    guard #available(iOS 26.0, *) else {
      complete(
        result,
        FlutterError(
          code: "unavailable",
          message: "AlarmKit requires iOS 26.0 or newer.",
          details: nil
        )
      )
      return
    }

    Task { @MainActor in
      let mirror: [String: AlarmMirrorRecord]
      do {
        mirror = try loadValidatedMirror()
      } catch {
        complete(
          result,
          FlutterError(
            code: "corrupt",
            message: "The persisted AlarmKit identity mirror is corrupt.",
            details: nil
          )
        )
        return
      }

      do {
        let alarms = try nativeClientForAlarmKit().inventory()
        let currentIds: Set<String>
        do {
          currentIds = try Set(alarms.map { try canonicalPlatformAlarmId($0.platformAlarmId) })
        } catch {
          complete(
            result,
            FlutterError(
              code: "corrupt",
              message: "AlarmKit returned an invalid platform identity.",
              details: nil
            )
          )
          return
        }
        var seenReservationIds = Set<String>()
        var seenOccurrenceIds = Set<String>()
        var seenPlatformIds = Set<String>()
        var rows = [[String: Any?]]()

        for alarm in alarms {
          guard let platformAlarmId = try? canonicalPlatformAlarmId(alarm.platformAlarmId) else {
            complete(
              result,
              FlutterError(
                code: "corrupt",
                message: "AlarmKit returned an invalid platform identity.",
                details: nil
              )
            )
            return
          }
          guard let record = mirror[platformAlarmId] else {
            complete(
              result,
              FlutterError(
                code: "corrupt",
                message: "Unknown AlarmKit identity: \(platformAlarmId).",
                details: nil
              )
            )
            return
          }
          guard record.platformAlarmId == platformAlarmId,
            !record.reservationId.isEmpty,
            !record.occurrenceId.isEmpty,
            !record.wakePlanId.isEmpty,
            seenReservationIds.insert(record.reservationId).inserted,
            seenOccurrenceIds.insert(record.occurrenceId).inserted,
            seenPlatformIds.insert(platformAlarmId).inserted
          else {
            complete(
              result,
              FlutterError(
                code: "corrupt",
                message: "Corrupt or duplicate AlarmKit identity: \(platformAlarmId).",
                details: nil
              )
            )
            return
          }

          rows.append(
            inventoryRow(
              record: record,
              status: alarm.status
            )
          )
        }

        // AlarmKit removes one-shot alarms after they fire or stop. Pruning
        // the mirror makes that removal observable as an absent row on the
        // next inventory read, including after the app was not running.
        let prunedMirror = mirror.filter {
          currentIds.contains($0.key) || pendingNativeAlarmIds.contains($0.key)
        }
        if prunedMirror.count != mirror.count {
          try saveMirror(prunedMirror)
        }

        var response = baseResponse()
        response["reservations"] = rows
        complete(result, response)
      } catch {
        complete(
          result,
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
      complete(result, invalidRequest("occurrences must be a list."))
      return
    }

    Task { @MainActor in
      let rows = await occurrencePayloads.asyncMap { payload in
        await scheduleOccurrence(payload)
      }
      var response = baseResponse()
      response["occurrences"] = rows
      complete(result, response)
    }
  }

  private func cancelAlarms(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let payload = validatedPayload(arguments, result: result) else { return }
    guard let alarmPayloads = payload["alarms"] as? [[String: Any?]] else {
      complete(result, invalidRequest("alarms must be a list."))
      return
    }

    Task { @MainActor in
      let rows = await alarmPayloads.asyncMap { payload in
        await cancelAlarm(payload)
      }
      var response = baseResponse()
      response["alarms"] = rows
      complete(result, response)
    }
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
      complete(result, response)
      return
    }

    let scheduledAt = Date().addingTimeInterval(TimeInterval(fireAfterMillis) / 1000.0)
    let testOccurrenceId = "test-\(UUID().uuidString)"
    let request = ScheduleRequest(
      occurrenceId: testOccurrenceId,
      reservationId: testOccurrenceId,
      wakePlanId: "test",
      scheduledAt: scheduledAt,
      targetAt: scheduledAt,
      soundId: soundId,
      vibrationEnabled: vibrationEnabled
    )

    Task { @MainActor in
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
      complete(result, response)
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
        reservationId: stringValue(payloadValue(payload, "reservationId"))
          ?? stringValue(payloadValue(payload, "occurrenceId"))
          ?? "",
        wakePlanId: stringValue(payloadValue(payload, "wakePlanId")) ?? "",
        reason: "invalidRequest",
        message: "Occurrence requires occurrenceId, wakePlanId, scheduledAt, and targetAt."
      )
    }
    let reservationId = nonEmptyString(payloadValue(payload, "reservationId")) ?? occurrenceId

    let request = ScheduleRequest(
      occurrenceId: occurrenceId,
      reservationId: reservationId,
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
        reservationId: reservationId,
        wakePlanId: wakePlanId,
        platformAlarmId: row.platformAlarmId ?? ""
      )
    }
    return scheduleFailureRow(
      occurrenceId: occurrenceId,
      reservationId: reservationId,
      wakePlanId: wakePlanId,
      reason: row.failureReason ?? "nativeError",
      message: row.failureMessage,
      platformAlarmId: row.platformAlarmId
    )
  }

  func cancelAlarm(_ payload: [String: Any?]) async -> [String: Any?] {
    guard let occurrenceId = nonEmptyString(payloadValue(payload, "occurrenceId")) else {
      return cancelFailureRow(
        occurrenceId: "",
        reservationId: stringValue(payloadValue(payload, "reservationId")) ?? "",
        platformAlarmId: stringValue(payloadValue(payload, "platformAlarmId")) ?? "",
        reason: "invalidRequest",
        message: "occurrenceId is required."
      )
    }
    let requestedReservationId: String?
    if payload.keys.contains("reservationId") {
      guard let suppliedReservationId = stringValue(payloadValue(payload, "reservationId")),
        !suppliedReservationId.isEmpty
      else {
        return cancelFailureRow(
          occurrenceId: occurrenceId,
          reservationId: occurrenceId,
          platformAlarmId: stringValue(payloadValue(payload, "platformAlarmId")) ?? "",
          reason: "invalidRequest",
          message: "reservationId must be a non-empty string when supplied."
        )
      }
      requestedReservationId = suppliedReservationId
    } else {
      requestedReservationId = nil
    }
    let responseReservationId = requestedReservationId ?? occurrenceId
    // Cancel rows are correlated by the caller's exact (occurrenceId,
    // platformAlarmId) tuple in Dart. Keep the accepted caller spelling in
    // the response while using the canonical UUID text for native ownership
    // and coordinator admission.
    guard let responsePlatformAlarmId = nonEmptyString(
      payloadValue(payload, "platformAlarmId")
    ) else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: responseReservationId,
        platformAlarmId: "",
        reason: "missingPlatformAlarmId",
        message: "platformAlarmId is required."
      )
    }
    guard let alarmId = UUID(uuidString: responsePlatformAlarmId),
      let platformAlarmId = try? canonicalPlatformAlarmId(responsePlatformAlarmId)
    else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: responseReservationId,
        platformAlarmId: responsePlatformAlarmId,
        reason: "invalidRequest",
        message: "platformAlarmId must be an AlarmKit UUID."
      )
    }
    guard #available(iOS 26.0, *) else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: responseReservationId,
        platformAlarmId: responsePlatformAlarmId,
        reason: "unavailable",
        message: "AlarmKit requires iOS 26.0 or newer."
      )
    }

    return await scheduleCoordinator.run(for: platformAlarmId) {
      await self.performCancelAlarm(
        occurrenceId: occurrenceId,
        requestedReservationId: requestedReservationId,
        responseReservationId: responseReservationId,
        platformAlarmId: platformAlarmId,
        responsePlatformAlarmId: responsePlatformAlarmId,
        alarmId: alarmId
      )
    }
  }

  @available(iOS 26.0, *)
  private func performCancelAlarm(
    occurrenceId: String,
    requestedReservationId: String?,
    responseReservationId: String,
    platformAlarmId: String,
    responsePlatformAlarmId: String,
    alarmId: UUID
  ) async -> [String: Any?] {
    do {
      var mirror = try loadValidatedMirror()
      if let record = mirror[platformAlarmId],
        record.occurrenceId != occurrenceId
          || (requestedReservationId != nil
            && record.reservationId != requestedReservationId)
      {
        return cancelFailureRow(
          occurrenceId: occurrenceId,
          reservationId: responseReservationId,
          platformAlarmId: responsePlatformAlarmId,
          reason: "invalidRequest",
          message: "AlarmKit identity does not match the requested reservation."
        )
      }
      try nativeClientForAlarmKit().cancel(id: alarmId)
      mirror.removeValue(forKey: platformAlarmId)
      try saveMirror(mirror)
      return cancelSuccessRow(
        occurrenceId: occurrenceId,
        reservationId: responseReservationId,
        platformAlarmId: responsePlatformAlarmId
      )
    } catch {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: responseReservationId,
        platformAlarmId: responsePlatformAlarmId,
        reason: "nativeError",
        message: error.localizedDescription
      )
    }
  }

  func scheduleAlarm(_ request: ScheduleRequest) async -> ScheduleRow {
    await scheduleCoordinator.run(
      for: calarmPlatformAlarmId(for: request.reservationId)
    ) {
      await self.performScheduleAlarm(request)
    }
  }

  private func performScheduleAlarm(_ request: ScheduleRequest) async -> ScheduleRow {
    guard #available(iOS 26.0, *) else {
      return ScheduleRow(
        status: "failure",
        platformAlarmId: nil,
        failureReason: "unavailable",
        failureMessage: "AlarmKit requires iOS 26.0 or newer."
      )
    }

    guard nativeClientForAlarmKit().isAuthorized else {
      return ScheduleRow(
        status: "failure",
        platformAlarmId: nil,
        failureReason: "permissionMissing",
        failureMessage: "AlarmKit authorization is required."
      )
    }

    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    guard let alarmId = UUID(uuidString: platformAlarmId) else {
      return ScheduleRow(
        status: "failure",
        platformAlarmId: nil,
        failureReason: "invalidRequest",
        failureMessage: "reservationId could not produce an AlarmKit UUID."
      )
    }

    var mirrorEntryWritten = false
    do {
      var mirror = try loadValidatedMirror()
      if let existing = mirror[platformAlarmId], !existing.matches(request) {
        return ScheduleRow(
          status: "failure",
          platformAlarmId: platformAlarmId,
          failureReason: "unknown",
          failureMessage: "reservationId is already bound to a different alarm."
        )
      }

      let currentIds = Set(
        try nativeClientForAlarmKit().inventory().map {
          try canonicalPlatformAlarmId($0.platformAlarmId)
        }
      )
      if currentIds.contains(platformAlarmId) {
        guard mirror[platformAlarmId] != nil else {
          return ScheduleRow(
            status: "failure",
            platformAlarmId: platformAlarmId,
            failureReason: "unknown",
            failureMessage: "AlarmKit contains an unknown native identity."
          )
        }
        return ScheduleRow(
          status: "success",
          platformAlarmId: platformAlarmId,
          failureReason: nil,
          failureMessage: nil
        )
      }

      pendingNativeAlarmIds.insert(platformAlarmId)
      defer { pendingNativeAlarmIds.remove(platformAlarmId) }

      // Persist before crossing into AlarmKit so an interrupted process can
      // recover the caller identity from the next inventory read.
      mirror[platformAlarmId] = AlarmMirrorRecord(
        request: request,
        platformAlarmId: platformAlarmId
      )
      try saveMirror(mirror)
      mirrorEntryWritten = true

      let scheduledPlatformAlarmId = try await nativeClientForAlarmKit().schedule(
        id: alarmId,
        request: request
      )
      guard try canonicalPlatformAlarmId(scheduledPlatformAlarmId) == platformAlarmId else {
        throw MirrorValidationError.invalid
      }
      return ScheduleRow(
        status: "success",
        platformAlarmId: platformAlarmId,
        failureReason: nil,
        failureMessage: nil
      )
    } catch AlarmManager.AlarmError.maximumLimitReached {
      if mirrorEntryWritten {
        removeMirrorEntryIfNativeAlarmAbsent(platformAlarmId, request: request)
      }
      return ScheduleRow(
        status: "failure",
        platformAlarmId: nil,
        failureReason: "osConstraint",
        failureMessage: "AlarmKit maximum pending alarm limit was reached."
      )
    } catch {
      if mirrorEntryWritten {
        removeMirrorEntryIfNativeAlarmAbsent(platformAlarmId, request: request)
      }
      return ScheduleRow(
        status: "failure",
        platformAlarmId: nil,
        failureReason: "nativeError",
        failureMessage: error.localizedDescription
      )
    }
  }

  @available(iOS 26.0, *)
  private func nativeClientForAlarmKit() -> any AlarmKitNativeClient {
    nativeClient ?? SystemAlarmKitClient()
  }

  @available(iOS 26.0, *)
  private func observeAlarmUpdates() async {
    for await alarms in AlarmManager.shared.alarmUpdates {
      reconcileMirror(with: alarms)
    }
  }

  @available(iOS 26.0, *)
  private func reconcileMirror(with alarms: [Alarm]) {
    reconcileMirror(withNativeAlarmIds: alarms.map { $0.id.uuidString })
  }

  func reconcileMirror(withNativeAlarmIds nativeAlarmIds: [String]) {
    guard let mirror = try? loadValidatedMirror() else { return }
    guard let currentIds = try? Set(
      nativeAlarmIds.map { try canonicalPlatformAlarmId($0) }
    ) else { return }
    let prunedMirror = mirror.filter {
      currentIds.contains($0.key) || pendingNativeAlarmIds.contains($0.key)
    }
    if prunedMirror.count != mirror.count {
      try? saveMirror(prunedMirror)
    }
  }

  private func loadMirror() throws -> [String: AlarmMirrorRecord] {
    guard let data = UserDefaults.standard.data(forKey: nativeAlarmMirrorKey) else {
      return [:]
    }
    return try JSONDecoder().decode([String: AlarmMirrorRecord].self, from: data)
  }

  private func loadValidatedMirror() throws -> [String: AlarmMirrorRecord] {
    let mirror = try loadMirror()
    let normalizedMirror = try validatedMirror(mirror)
    if normalizedMirror != mirror {
      try saveMirror(normalizedMirror)
    }
    return normalizedMirror
  }

  private func validatedMirror(
    _ mirror: [String: AlarmMirrorRecord]
  ) throws -> [String: AlarmMirrorRecord] {
    var reservationIds = Set<String>()
    var occurrenceIds = Set<String>()
    var platformAlarmIds = Set<String>()
    var normalizedMirror = [String: AlarmMirrorRecord]()

    for (key, record) in mirror {
      guard let normalizedKey = try? canonicalPlatformAlarmId(key),
        let normalizedRecordId = try? canonicalPlatformAlarmId(record.platformAlarmId),
        normalizedKey == normalizedRecordId,
        !record.reservationId.isEmpty,
        !record.occurrenceId.isEmpty,
        !record.wakePlanId.isEmpty,
        reservationIds.insert(record.reservationId).inserted,
        occurrenceIds.insert(record.occurrenceId).inserted,
        platformAlarmIds.insert(normalizedKey).inserted,
        normalizedMirror[normalizedKey] == nil
      else {
        throw MirrorValidationError.invalid
      }
      normalizedMirror[normalizedKey] = AlarmMirrorRecord(
        reservationId: record.reservationId,
        occurrenceId: record.occurrenceId,
        wakePlanId: record.wakePlanId,
        platformAlarmId: normalizedKey
      )
    }
    return normalizedMirror
  }

  private func saveMirror(_ mirror: [String: AlarmMirrorRecord]) throws {
    let data = try JSONEncoder().encode(mirror)
    UserDefaults.standard.set(data, forKey: nativeAlarmMirrorKey)
  }

  private func removeMirrorEntryIfNativeAlarmAbsent(
    _ platformAlarmId: String,
    request: ScheduleRequest
  ) {
    do {
      let currentNativeAlarmIds = Set(
        try nativeClientForAlarmKit().inventory().map {
          try canonicalPlatformAlarmId($0.platformAlarmId)
        }
      )
      guard calarmShouldRemoveMirrorAfterScheduleFailure(
        currentNativeAlarmIds: currentNativeAlarmIds,
        platformAlarmId: platformAlarmId
      ) else { return }

      var mirror = try loadValidatedMirror()
      guard mirror[platformAlarmId]?.matches(request) == true else { return }
      mirror.removeValue(forKey: platformAlarmId)
      try saveMirror(mirror)
    } catch {
      // Preserve the mirror when native inventory or mirror persistence cannot
      // establish that the AlarmKit alarm is absent.
    }
  }

  private func complete(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async {
      result(value)
    }
  }

  private func validateBasePayload(_ arguments: Any?, result: @escaping FlutterResult) -> Bool {
    validatedPayload(arguments, result: result) != nil
  }

  private func validatedPayload(
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
  let wakePlanId: String
  let scheduledAt: Date
  let targetAt: Date
  let soundId: String
  let vibrationEnabled: Bool
}

private struct AlarmMirrorRecord: Codable, Equatable {
  let reservationId: String
  let occurrenceId: String
  let wakePlanId: String
  let platformAlarmId: String

  init(request: ScheduleRequest, platformAlarmId: String) {
    reservationId = request.reservationId
    occurrenceId = request.occurrenceId
    wakePlanId = request.wakePlanId
    self.platformAlarmId = platformAlarmId
  }

  init(
    reservationId: String,
    occurrenceId: String,
    wakePlanId: String,
    platformAlarmId: String
  ) {
    self.reservationId = reservationId
    self.occurrenceId = occurrenceId
    self.wakePlanId = wakePlanId
    self.platformAlarmId = platformAlarmId
  }

  func matches(_ request: ScheduleRequest) -> Bool {
    reservationId == request.reservationId &&
      occurrenceId == request.occurrenceId &&
      wakePlanId == request.wakePlanId
  }
}

private enum MirrorValidationError: Error {
  case invalid
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
private final class SystemAlarmKitClient: AlarmKitNativeClient {
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

@MainActor
final class AlarmScheduleCoordinator {
  private struct Tail {
    let token: UUID
    let task: Task<Void, Never>
  }

  private var tails: [String: Tail] = [:]

  func run<Value>(
    for reservationId: String,
    operation: @escaping @MainActor () async -> Value
  ) async -> Value {
    let token = UUID()
    let predecessor = tails[reservationId]?.task
    return await withCheckedContinuation { continuation in
      let task = Task { @MainActor in
        if let predecessor {
          await predecessor.value
        }
        let value = await operation()
        continuation.resume(returning: value)
        if tails[reservationId]?.token == token {
          tails.removeValue(forKey: reservationId)
        }
      }
      tails[reservationId] = Tail(token: token, task: task)
    }
  }
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
  reservationId: String,
  wakePlanId: String,
  platformAlarmId: String
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "reservationId": reservationId,
    "wakePlanId": wakePlanId,
    "status": "success",
    "platformAlarmId": platformAlarmId,
  ]
}

private func scheduleFailureRow(
  occurrenceId: String,
  reservationId: String,
  wakePlanId: String,
  reason: String,
  message: String?,
  platformAlarmId: String? = nil
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "reservationId": reservationId,
    "wakePlanId": wakePlanId,
    "status": "failure",
    "failureReason": reason,
    "failureMessage": message,
    "platformAlarmId": platformAlarmId,
  ]
}

private func cancelSuccessRow(
  occurrenceId: String,
  reservationId: String,
  platformAlarmId: String
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "reservationId": reservationId,
    "platformAlarmId": platformAlarmId,
    "status": "success",
  ]
}

private func cancelFailureRow(
  occurrenceId: String,
  reservationId: String,
  platformAlarmId: String,
  reason: String,
  message: String?
) -> [String: Any?] {
  [
    "occurrenceId": occurrenceId,
    "reservationId": reservationId,
    "platformAlarmId": platformAlarmId,
    "status": "failure",
    "failureReason": reason,
    "failureMessage": message,
  ]
}

private func invalidRequest(_ message: String) -> FlutterError {
  FlutterError(code: "invalidRequest", message: message, details: nil)
}

func calarmPlatformAlarmId(for reservationId: String) -> String {
  var bytes = Array(SHA256.hash(data: Data(reservationId.utf8)).prefix(16))
  bytes[6] = (bytes[6] & 0x0f) | 0x50
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  let hex = bytes.map { String(format: "%02x", $0) }
  return "\(hex[0])\(hex[1])\(hex[2])\(hex[3])-\(hex[4])\(hex[5])-\(hex[6])\(hex[7])-\(hex[8])\(hex[9])-\(hex[10])\(hex[11])\(hex[12])\(hex[13])\(hex[14])\(hex[15])"
}

private func canonicalPlatformAlarmId(_ platformAlarmId: String) throws -> String {
  guard let uuid = UUID(uuidString: platformAlarmId) else {
    throw MirrorValidationError.invalid
  }
  return uuid.uuidString.lowercased()
}

func calarmShouldRemoveMirrorAfterScheduleFailure(
  currentNativeAlarmIds: Set<String>?,
  platformAlarmId: String
) -> Bool {
  guard let currentNativeAlarmIds,
    let normalizedPlatformAlarmId = try? canonicalPlatformAlarmId(platformAlarmId)
  else { return false }
  let normalizedCurrentIds = Set(
    currentNativeAlarmIds.compactMap { try? canonicalPlatformAlarmId($0) }
  )
  return !normalizedCurrentIds.contains(normalizedPlatformAlarmId)
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

private func inventoryRow(
  record: AlarmMirrorRecord,
  status: String
) -> [String: Any?] {
  [
    "reservationId": record.reservationId,
    "occurrenceId": record.occurrenceId,
    "wakePlanId": record.wakePlanId,
    "platformAlarmId": record.platformAlarmId,
    "status": status,
  ]
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
