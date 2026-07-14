@_weakLinked import AlarmKit
import CryptoKit
import Flutter
import Foundation
import SwiftUI

private let nativeAlarmChannelName = "net.xpadev.calarm/native_alarm"
private let nativeAlarmSchemaVersion = 1
private let nativeAlarmMirrorKey = "net.xpadev.calarm/native_alarm_mirror"
private let nativeAlarmPendingMirrorKey = "net.xpadev.calarm/native_alarm_pending_mirror"
private let nativeAlarmMirrorEnvelopeKey = "net.xpadev.calarm/native_alarm_mirror_envelope"
private let nativeAlarmMirrorTransactionKey = "net.xpadev.calarm/native_alarm_mirror_transaction"
private let nativeAlarmMirrorEnvelopeVersion = 1

@MainActor
final class AlarmKitBridge {
  private let channel: FlutterMethodChannel?
  private var alarmObservationTask: Task<Void, Never>?
  private let scheduleCoordinator = AlarmScheduleCoordinator()
  private let mirrorCoordinator = AlarmMirrorCoordinator.shared
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

  // Internal for the native XCTest production-seam harness. The MethodChannel
  // remains the only application-facing entry point.
  func getInventory(result: @escaping FlutterResult) {
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
      let value = await mirrorCoordinator.run {
        await self.performGetInventory()
      }
      complete(result, value)
    }
  }

  @available(iOS 26.0, *)
  private func performGetInventory() async -> Any? {
    let alarms: [NativeAlarmSnapshot]
    do {
      alarms = try nativeClientForAlarmKit().inventory()
    } catch {
      return FlutterError(
        code: "nativeError",
        message: error.localizedDescription,
        details: nil
      )
    }

    let mirrorSnapshot: MirrorSnapshot
    do {
      mirrorSnapshot = try loadMirrorSnapshot()
    } catch {
      do {
        mirrorSnapshot = try recoverMirrorSnapshot(from: alarms)
      } catch {
        return FlutterError(
          code: "corrupt",
          message: "The persisted AlarmKit identity mirror is corrupt or ambiguous.",
          details: nil
        )
      }
    }

    do {
      let canonicalIds: [String]
      do {
        canonicalIds = try authoritativeNativeAlarmIds(
          alarms.map { $0.platformAlarmId },
          mirrorSnapshot: mirrorSnapshot
        )
      } catch {
        return FlutterError(
          code: "corrupt",
          message: "AlarmKit returned invalid or duplicate platform identities.",
          details: nil
        )
      }
      let currentIds = Set(canonicalIds)
      var reconciledMirror = mirrorSnapshot.normalized
      var reconciledPendingMirror = mirrorSnapshot.pendingNormalized
      var seenReservationIds = Set<String>()
      var seenOccurrenceIds = Set<String>()
      var seenPlatformIds = Set<String>()
      var rows = [[String: Any?]]()

      for (alarm, platformAlarmId) in zip(alarms, canonicalIds) {
        guard let record = reconciledMirror[platformAlarmId]
          ?? reconciledPendingMirror[platformAlarmId]
        else {
          return FlutterError(
            code: "corrupt",
            message: "Unknown AlarmKit identity: \(platformAlarmId).",
            details: nil
          )
        }
        guard record.platformAlarmId == platformAlarmId,
          !record.reservationId.isEmpty,
          !record.occurrenceId.isEmpty,
          !record.wakePlanId.isEmpty,
          seenReservationIds.insert(record.reservationId).inserted,
          seenOccurrenceIds.insert(record.occurrenceId).inserted,
          seenPlatformIds.insert(platformAlarmId).inserted
        else {
          return FlutterError(
            code: "corrupt",
            message: "Corrupt or duplicate AlarmKit identity: \(platformAlarmId).",
            details: nil
          )
        }

        if reconciledPendingMirror.removeValue(forKey: platformAlarmId) != nil {
          reconciledMirror[platformAlarmId] = record
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
      let prunedMirror = reconciledMirror.filter {
        currentIds.contains($0.key) || pendingNativeAlarmIds.contains($0.key)
      }
      let prunedPendingMirror = reconciledPendingMirror.filter {
        currentIds.contains($0.key) || pendingNativeAlarmIds.contains($0.key)
      }
      if !mirrorSnapshot.isEnvelope
        || mirrorSnapshot.needsProjectionRewrite
        || mirrorSnapshot.needsTransactionMarkerRewrite
        || mirrorSnapshot.legacyPendingPresent
        || prunedMirror != mirrorSnapshot.normalized
        || prunedPendingMirror != mirrorSnapshot.pendingNormalized
        || prunedMirror != mirrorSnapshot.stored
        || prunedPendingMirror != mirrorSnapshot.pendingStored
      {
        try saveMirrorState(prunedMirror, pending: prunedPendingMirror)
      }

      var response = baseResponse()
      response["reservations"] = rows
      return response
    } catch {
      return FlutterError(
        code: "nativeError",
        message: error.localizedDescription,
        details: nil
      )
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
    // Keep the test alarm's full ownership tuple stable across the
    // MethodChannel schedule/cancel smoke flow. Production alarms still use
    // their caller-owned reservation identity.
    let testOccurrenceId = "ci-smoke-test-alarm"
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
        // Preserve a recoverable identity for native smoke cleanup when the
        // schedule outcome is uncertain. Older Dart readers may ignore this
        // optional field, so cleanup also recovers it from inventory by the
        // stable test tuple.
        response["platformAlarmId"] = row.platformAlarmId
      }
      complete(result, response)
    }
  }

  func scheduleOccurrence(_ payload: [String: Any?]) async -> [String: Any?] {
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
    let reservationId: String
    if payload.keys.contains("reservationId") {
      guard let suppliedReservationId = stringValue(payloadValue(payload, "reservationId")),
        !suppliedReservationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return scheduleFailureRow(
          occurrenceId: occurrenceId,
          reservationId: occurrenceId,
          wakePlanId: wakePlanId,
          reason: "invalidRequest",
          message: "reservationId must be a non-empty string when supplied."
        )
      }
      reservationId = suppliedReservationId
    } else {
      reservationId = occurrenceId
    }

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
    await mirrorCoordinator.run {
      await self.performCancelAlarmInMirrorTransaction(
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
  private func performCancelAlarmInMirrorTransaction(
    occurrenceId: String,
    requestedReservationId: String?,
    responseReservationId: String,
    platformAlarmId: String,
    responsePlatformAlarmId: String,
    alarmId: UUID
  ) async -> [String: Any?] {
    do {
      let mirrorSnapshot: MirrorSnapshot
      do {
        mirrorSnapshot = try loadMirrorSnapshot()
      } catch {
        let recoveryAlarms = try nativeClientForAlarmKit().inventory()
        mirrorSnapshot = try recoverMirrorSnapshot(from: recoveryAlarms)
      }
      var mirror = mirrorSnapshot.normalized
      var pendingMirror = mirrorSnapshot.pendingNormalized
      if let record = mirror[platformAlarmId] ?? pendingMirror[platformAlarmId],
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
      pendingMirror.removeValue(forKey: platformAlarmId)
      try saveMirrorState(mirror, pending: pendingMirror)
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
    await mirrorCoordinator.run {
      await self.performScheduleAlarmInMirrorTransaction(request)
    }
  }

  private func performScheduleAlarmInMirrorTransaction(
    _ request: ScheduleRequest
  ) async -> ScheduleRow {
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

    var mirrorEntryPresent = false
    var pendingEntryCreated = false
    do {
      let mirrorSnapshot: MirrorSnapshot
      do {
        mirrorSnapshot = try loadMirrorSnapshot()
      } catch {
        do {
          let recoveryAlarms = try nativeClientForAlarmKit().inventory()
          mirrorSnapshot = try recoverMirrorSnapshot(from: recoveryAlarms)
        } catch is NativeSnapshotValidationError {
          return ScheduleRow(
            status: "failure",
            platformAlarmId: platformAlarmId,
            failureReason: "unknown",
            failureMessage: "AlarmKit identity state was ambiguous or non-authoritative."
          )
        } catch {
          return ScheduleRow(
            status: "failure",
            platformAlarmId: platformAlarmId,
            failureReason: "nativeError",
            failureMessage: error.localizedDescription
          )
        }
      }
      var mirror = mirrorSnapshot.normalized
      var pendingMirror = mirrorSnapshot.pendingNormalized
      let committedExisting = mirror[platformAlarmId]
      let pendingExisting = pendingMirror[platformAlarmId]
      if let committedExisting,
        !committedExisting.matchesStableReservation(request)
      {
        return ScheduleRow(
          status: "failure",
          platformAlarmId: platformAlarmId,
          failureReason: "unknown",
          failureMessage: "reservationId is already bound to a different alarm."
        )
      }
      if let pendingExisting,
        !pendingExisting.matchesStableReservation(request)
      {
        return ScheduleRow(
          status: "failure",
          platformAlarmId: platformAlarmId,
          failureReason: "unknown",
          failureMessage: "reservationId is already bound to a different alarm."
        )
      }
      let existing = committedExisting ?? pendingExisting
      mirrorEntryPresent = existing != nil

      let nativeAlarms = try nativeClientForAlarmKit().inventory()
      let currentIds: Set<String>
      do {
        currentIds = try Set(
          authoritativeNativeAlarmIds(
            nativeAlarms.map { $0.platformAlarmId },
            mirrorSnapshot: mirrorSnapshot
          )
        )
      } catch {
        return ScheduleRow(
          status: "failure",
          platformAlarmId: platformAlarmId,
          failureReason: "unknown",
          failureMessage: "AlarmKit inventory was invalid or non-authoritative."
        )
      }
      if currentIds.contains(platformAlarmId) {
        guard let existing,
          existing.matchesStableReservation(request)
        else {
          return ScheduleRow(
            status: "failure",
            platformAlarmId: platformAlarmId,
            failureReason: "unknown",
            failureMessage: "AlarmKit contains an unknown native identity."
          )
        }
        pendingMirror.removeValue(forKey: platformAlarmId)

        if !existing.matches(request) {
          // The stable reservation may be retried with a recreated occurrence.
          // Replace the native configuration before publishing the new mirror,
          // so inventory cannot claim that new metadata is scheduled on the
          // old AlarmKit configuration. Keep the prior record available until
          // the replacement is committed so a failed replacement can restore
          // both the native alarm and its durable identity.
          let previousRecord = existing
          do {
            try nativeClientForAlarmKit().cancel(id: alarmId)
            mirror[platformAlarmId] = AlarmMirrorRecord(
              request: request,
              platformAlarmId: platformAlarmId
            )
            try saveMirrorState(mirror, pending: pendingMirror)
            let scheduledPlatformAlarmId = try await nativeClientForAlarmKit().schedule(
              id: alarmId,
              request: request
            )
            guard try canonicalPlatformAlarmId(scheduledPlatformAlarmId) == platformAlarmId else {
              throw MirrorValidationError.invalid
            }
            try saveMirrorState(mirror, pending: pendingMirror)
            return ScheduleRow(
              status: "success",
              platformAlarmId: platformAlarmId,
              failureReason: nil,
              failureMessage: nil
            )
          } catch {
            mirror[platformAlarmId] = previousRecord
            pendingMirror.removeValue(forKey: platformAlarmId)
            var nativeRestored = false
            if let previousRequest = previousRecord.scheduleRequest() {
              do {
                let restoredPlatformAlarmId = try await nativeClientForAlarmKit().schedule(
                  id: alarmId,
                  request: previousRequest
                )
                nativeRestored = try canonicalPlatformAlarmId(restoredPlatformAlarmId) == platformAlarmId
              } catch {
                nativeRestored = false
              }
            }
            try? saveMirrorState(mirror, pending: pendingMirror)
            if nativeRestored {
              return ScheduleRow(
                status: "failure",
                platformAlarmId: platformAlarmId,
                failureReason: "nativeError",
                failureMessage: error.localizedDescription
              )
            }
            return ScheduleRow(
              status: "failure",
              platformAlarmId: nil,
              failureReason: "nativeError",
              failureMessage: error.localizedDescription
            )
          }
        }

        mirror[platformAlarmId] = AlarmMirrorRecord(
          request: request,
          platformAlarmId: platformAlarmId
        )
        try saveMirrorState(mirror, pending: pendingMirror)
        return ScheduleRow(
          status: "success",
          platformAlarmId: platformAlarmId,
          failureReason: nil,
          failureMessage: nil
        )
      }

      if pendingMirror.removeValue(forKey: platformAlarmId) != nil {
        mirrorEntryPresent = false
      }

      if committedExisting != nil {
        mirror[platformAlarmId] = AlarmMirrorRecord(
          request: request,
          platformAlarmId: platformAlarmId
        )
      }

      pendingNativeAlarmIds.insert(platformAlarmId)
      defer { pendingNativeAlarmIds.remove(platformAlarmId) }

      if !mirrorEntryPresent {
        // Keep in-flight recovery identity separate from the committed mirror.
        // A failed/uncertain native call must never turn a new row into an
        // ordinary committed identity or overwrite the caller's prior bytes.
        let mirrorEntry = AlarmMirrorRecord(
          request: request,
          platformAlarmId: platformAlarmId
        )
        pendingMirror[platformAlarmId] = mirrorEntry
        try saveMirrorState(mirror, pending: pendingMirror)
        mirrorEntryPresent = true
        pendingEntryCreated = true
      }

      let scheduledPlatformAlarmId = try await nativeClientForAlarmKit().schedule(
        id: alarmId,
        request: request
      )
      guard try canonicalPlatformAlarmId(scheduledPlatformAlarmId) == platformAlarmId else {
        throw MirrorValidationError.invalid
      }
      if pendingEntryCreated {
        if let pendingEntry = pendingMirror.removeValue(forKey: platformAlarmId) {
          mirror[platformAlarmId] = pendingEntry
        }
      }
      try saveMirrorState(mirror, pending: pendingMirror)
      return ScheduleRow(
        status: "success",
        platformAlarmId: platformAlarmId,
        failureReason: nil,
        failureMessage: nil
      )
    } catch AlarmManager.AlarmError.maximumLimitReached {
      let cleanup = mirrorEntryPresent
        ? removeMirrorEntryIfNativeAlarmAbsent(
          platformAlarmId,
          request: request,
          pendingEntryCreated: pendingEntryCreated
        )
        : .uncertain
      return ScheduleRow(
        status: "failure",
        platformAlarmId: cleanup == .nativePresent ? platformAlarmId : nil,
        failureReason: "osConstraint",
        failureMessage: "AlarmKit maximum pending alarm limit was reached."
      )
    } catch {
      let cleanup = mirrorEntryPresent
        ? removeMirrorEntryIfNativeAlarmAbsent(
          platformAlarmId,
          request: request,
          pendingEntryCreated: pendingEntryCreated
        )
        : .uncertain
      return ScheduleRow(
        status: "failure",
        platformAlarmId: cleanup == .nativePresent ? platformAlarmId : nil,
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
      await reconcileMirror(with: alarms)
    }
  }

  @available(iOS 26.0, *)
  private func reconcileMirror(with alarms: [Alarm]) async {
    await reconcileMirror(withNativeAlarmIds: alarms.map { $0.id.uuidString })
  }

  func reconcileMirror(withNativeAlarmIds nativeAlarmIds: [String]) async {
    await mirrorCoordinator.run {
      await self.reconcileMirrorInMirrorTransaction(withNativeAlarmIds: nativeAlarmIds)
    }
  }

  private func reconcileMirrorInMirrorTransaction(withNativeAlarmIds nativeAlarmIds: [String]) async {
    guard let mirrorSnapshot = try? loadMirrorSnapshot(),
      let canonicalIds = try? authoritativeNativeAlarmIds(
        nativeAlarmIds,
        mirrorSnapshot: mirrorSnapshot
      )
    else { return }
    var reconciledMirror = mirrorSnapshot.normalized
    var reconciledPendingMirror = mirrorSnapshot.pendingNormalized
    let currentIds = Set(canonicalIds)
    for (platformAlarmId, record) in reconciledPendingMirror {
      if currentIds.contains(platformAlarmId) {
        reconciledMirror[platformAlarmId] = record
      }
    }
    for platformAlarmId in Array(reconciledPendingMirror.keys)
      where currentIds.contains(platformAlarmId)
    {
      reconciledPendingMirror.removeValue(forKey: platformAlarmId)
    }
    let prunedMirror = reconciledMirror.filter {
      currentIds.contains($0.key) || pendingNativeAlarmIds.contains($0.key)
    }
    let prunedPendingMirror = reconciledPendingMirror.filter {
      currentIds.contains($0.key) || pendingNativeAlarmIds.contains($0.key)
    }
    if !mirrorSnapshot.isEnvelope
      || mirrorSnapshot.needsProjectionRewrite
      || mirrorSnapshot.needsTransactionMarkerRewrite
      || mirrorSnapshot.legacyPendingPresent
      || prunedMirror != mirrorSnapshot.normalized
      || prunedPendingMirror != mirrorSnapshot.pendingNormalized
      || prunedMirror != mirrorSnapshot.stored
      || prunedPendingMirror != mirrorSnapshot.pendingStored
    {
      try? saveMirrorState(prunedMirror, pending: prunedPendingMirror)
    }
  }

  private func loadMirrorSnapshot() throws -> MirrorSnapshot {
    let committedData = UserDefaults.standard.data(forKey: nativeAlarmMirrorKey)
    let legacyPendingData = UserDefaults.standard.data(forKey: nativeAlarmPendingMirrorKey)
    let envelopeData = UserDefaults.standard.data(forKey: nativeAlarmMirrorEnvelopeKey)
    let state: StoredMirrorState
    if let envelopeData {
      do {
        let envelope = try decodeMirrorEnvelope(envelopeData)
        let currentEnvelopeState = try validatedMirrorEnvelopeState(envelope)
        if let committedData, isMirrorEnvelope(committedData) {
          // The prior implementation wrote its complete envelope to the
          // legacy key. A current writer always replaces that key with a
          // plain committed projection before publishing the new envelope,
          // so a valid prior envelope here proves that an older reader wrote
          // after the current envelope. It is the deterministic latest state.
          // If it is malformed, do not silently fall back and resurrect rows.
          let priorEnvelope = try decodeMirrorEnvelope(committedData)
          let priorEnvelopeState = try validatedMirrorEnvelopeState(priorEnvelope)
          state = StoredMirrorState(
            committed: priorEnvelopeState.committed,
            pending: priorEnvelopeState.pending,
              isEnvelope: true,
              legacyPendingPresent: legacyPendingData != nil,
              needsProjectionRewrite: true,
              needsTransactionMarkerRewrite: true
          )
        } else if let committedData {
          // A present legacy key must be fully decodable and semantically
          // valid. Treating malformed prior-envelope/projection bytes as
          // absent would silently discard rollback evidence.
          let projection = try validatedMirror(decodeMirrorMap(committedData))
          let pendingProjection = try validatedMirror(decodeMirrorMap(legacyPendingData))
          var pending = currentEnvelopeState.pending
          for (key, record) in pendingProjection {
            if let existing = pending[key] {
              guard existing == record else { throw MirrorValidationError.invalid }
            } else {
              pending[key] = record
            }
          }
          // A valid legacy projection may have been changed by an older
          // binary after this envelope was written. It is therefore the
          // committed authority; never resurrect envelope-only committed
          // rows from a stale rollback projection.
          state = StoredMirrorState(
            committed: projection,
            pending: pending.filter { projection[$0.key] == nil },
            isEnvelope: true,
            legacyPendingPresent: legacyPendingData != nil,
            needsProjectionRewrite: projection != currentEnvelopeState.committed
              || pending != currentEnvelopeState.pending,
            needsTransactionMarkerRewrite: false
          )
        } else {
          state = StoredMirrorState(
            committed: currentEnvelopeState.committed,
            pending: currentEnvelopeState.pending,
              isEnvelope: true,
              legacyPendingPresent: false,
              needsProjectionRewrite: true,
              needsTransactionMarkerRewrite: true
          )
        }
      } catch {
        // A partially written/unsupported envelope can fall back to the
        // legacy projection, which is deliberately written before the new
        // envelope. If that projection is not readable, the state is truly
        // unrecoverable and must remain corrupt.
        if let committedData, isMirrorEnvelope(committedData) {
          // If the current envelope write is interrupted but the prior
          // reader's legacy envelope is complete, retain that recoverable
          // state. Decode and validate it fully before any reconciliation.
          let priorEnvelope = try decodeMirrorEnvelope(committedData)
          let priorEnvelopeState = try validatedMirrorEnvelopeState(priorEnvelope)
          state = StoredMirrorState(
            committed: priorEnvelopeState.committed,
            pending: priorEnvelopeState.pending,
            isEnvelope: false,
            legacyPendingPresent: legacyPendingData != nil,
            needsProjectionRewrite: true,
            needsTransactionMarkerRewrite: true
          )
        } else {
          guard committedData != nil || legacyPendingData != nil else {
            throw MirrorValidationError.invalid
          }
          let committed = try validatedMirror(decodeMirrorMap(committedData))
          let pending = try validatedMirror(decodeMirrorMap(legacyPendingData))
          let merged = try mergeLegacyMirrorState(committed: committed, pending: pending)
          state = StoredMirrorState(
            committed: merged.committed,
            pending: merged.pending,
            isEnvelope: false,
            legacyPendingPresent: legacyPendingData != nil,
            needsProjectionRewrite: true,
            needsTransactionMarkerRewrite: true
          )
        }
      }
    } else if let committedData, isMirrorEnvelope(committedData) {
      // Compatibility with the short-lived envelope-at-legacy-key layout
      // shipped before the rollback projection was split out.
      let envelope = try decodeMirrorEnvelope(committedData)
      state = StoredMirrorState(
        committed: envelope.committed,
        pending: envelope.pending,
        isEnvelope: false,
        legacyPendingPresent: legacyPendingData != nil,
        needsProjectionRewrite: true,
        needsTransactionMarkerRewrite: true
      )
    } else {
      let committed = try decodeMirrorMap(committedData)
      let pending = try decodeMirrorMap(legacyPendingData)
      let merged = try mergeLegacyMirrorState(committed: committed, pending: pending)
      state = StoredMirrorState(
        committed: merged.committed,
        pending: merged.pending,
        isEnvelope: false,
        legacyPendingPresent: legacyPendingData != nil,
        needsProjectionRewrite: true,
        needsTransactionMarkerRewrite: true
      )
    }

    let mirror = state.committed
    let pendingMirror = state.pending
    let normalizedMirror = try validatedMirror(mirror)
    let normalizedPendingMirror = try validatedMirror(pendingMirror)
    var combined = normalizedMirror
    for (key, record) in normalizedPendingMirror {
      guard combined[key] == nil else { throw MirrorValidationError.invalid }
      combined[key] = record
    }
    _ = try validatedMirror(combined)
    let needsTransactionMarkerRewrite = try transactionMarkerNeedsRewrite(
      markerData: UserDefaults.standard.data(forKey: nativeAlarmMirrorTransactionKey),
      committedData: committedData,
      pendingData: legacyPendingData,
      envelopeData: envelopeData,
      authoritativePriorEnvelope: committedData.map(isMirrorEnvelope) ?? false,
      normalizedMirror: normalizedMirror,
      normalizedPendingMirror: normalizedPendingMirror
    )
    return MirrorSnapshot(
      stored: mirror,
      normalized: normalizedMirror,
      pendingStored: pendingMirror,
      pendingNormalized: normalizedPendingMirror,
      isEnvelope: state.isEnvelope,
      legacyPendingPresent: state.legacyPendingPresent,
      needsProjectionRewrite: state.needsProjectionRewrite,
      needsTransactionMarkerRewrite: state.needsTransactionMarkerRewrite
        || needsTransactionMarkerRewrite
    )
  }

  // A marker or projection failure is not immediately terminal: a native
  // schedule may have committed before the durable publication crashed. Read
  // AlarmKit first, then combine only independently valid persisted artifacts.
  // Recovery never invents an identity; every live native ID must have one
  // unambiguous persisted ownership tuple.
  private func recoverMirrorSnapshot(
    from nativeAlarms: [NativeAlarmSnapshot]
  ) throws -> MirrorSnapshot {
    let committedData = UserDefaults.standard.data(forKey: nativeAlarmMirrorKey)
    let pendingData = UserDefaults.standard.data(forKey: nativeAlarmPendingMirrorKey)
    let envelopeData = UserDefaults.standard.data(forKey: nativeAlarmMirrorEnvelopeKey)

    let committedArtifact = decodeRecoveryArtifact(
      committedData,
      allowEnvelope: true,
      requireGeneration: false
    )
    let envelopeArtifact = decodeRecoveryArtifact(
      envelopeData,
      allowEnvelope: true,
      requireGeneration: true
    )
    let pendingArtifact = decodeRecoveryArtifact(
      pendingData,
      allowEnvelope: false,
      requireGeneration: false
    )

    let artifacts = [committedArtifact, envelopeArtifact, pendingArtifact]
    let hasMalformedArtifact = artifacts.contains { $0.isPresent && !$0.isValid }
    guard !hasMalformedArtifact else {
      throw MirrorValidationError.invalid
    }

    var committed = [String: AlarmMirrorRecord]()
    var pending = [String: AlarmMirrorRecord]()
    if committedArtifact.isPresent, committedArtifact.isPlainProjection {
      // A valid plain map in the legacy committed key is the rollback/older
      // writer's authoritative key set. Enrich matching rows from newer
      // artifacts, but never resurrect rows omitted by that projection.
      committed = committedArtifact.committed
      for artifact in artifacts where artifact.isPresent && !artifact.isPlainProjection {
        for (key, record) in artifact.committed {
          guard let existing = committed[key] else { continue }
          committed[key] = try existing.mergedRecoveryRecord(with: record)
        }
      }
    } else {
      for artifact in artifacts where artifact.isPresent {
        try mergeRecoveryRecords(&committed, from: artifact.committed)
      }
    }
    for artifact in artifacts where artifact.isPresent {
      try mergeRecoveryRecords(&pending, from: artifact.pending)
    }

    for (key, record) in Array(pending) {
      if let committedRecord = committed[key] {
        guard committedRecord == record else { throw MirrorValidationError.invalid }
        pending.removeValue(forKey: key)
      }
    }
    let normalizedCommitted = try validatedMirror(committed)
    let normalizedPending = try validatedMirror(pending)
    var combined = normalizedCommitted
    for (key, record) in normalizedPending {
      guard combined[key] == nil else { throw MirrorValidationError.invalid }
      combined[key] = record
    }
    _ = try validatedMirror(combined)

    let canonicalIds = try canonicalNativeAlarmIds(
      nativeAlarms.map { $0.platformAlarmId }
    )
    let candidateIds = Set(normalizedCommitted.keys)
      .union(normalizedPending.keys)
    guard Set(canonicalIds).subtracting(candidateIds).isEmpty else {
      throw NativeSnapshotValidationError.unknownIdentity
    }

    return MirrorSnapshot(
      stored: normalizedCommitted,
      normalized: normalizedCommitted,
      pendingStored: normalizedPending,
      pendingNormalized: normalizedPending,
      isEnvelope: false,
      legacyPendingPresent: pendingData != nil,
      needsProjectionRewrite: true,
      needsTransactionMarkerRewrite: true
    )
  }

  private func decodeRecoveryArtifact(
    _ data: Data?,
    allowEnvelope: Bool,
    requireGeneration: Bool
  ) -> RecoveryMirrorArtifact {
    guard let data else { return RecoveryMirrorArtifact() }
    do {
      if isMirrorEnvelope(data) {
        guard allowEnvelope else { return RecoveryMirrorArtifact.invalid }
        let envelope = try decodeMirrorEnvelope(data)
        if requireGeneration {
          guard let generation = envelope.generation,
            (try? canonicalMirrorGeneration(generation)) != nil
          else { return RecoveryMirrorArtifact.invalid }
        }
        let state = try validatedMirrorEnvelopeState(envelope)
        return RecoveryMirrorArtifact(
          committed: state.committed,
          pending: state.pending,
          isPresent: true,
          isValid: true
        )
      }
      return RecoveryMirrorArtifact(
        committed: try validatedMirror(decodeMirrorMap(data)),
        isPresent: true,
        isValid: true,
        isPlainProjection: true
      )
    } catch {
      // Preserve invalidity as evidence. The recovery caller rejects any
      // present malformed artifact before considering valid alternatives.
      return RecoveryMirrorArtifact.invalid
    }
  }

  private func mergeRecoveryRecords(
    _ target: inout [String: AlarmMirrorRecord],
    from source: [String: AlarmMirrorRecord]
  ) throws {
    for (key, record) in source {
      if let existing = target[key] {
        target[key] = try existing.mergedRecoveryRecord(with: record)
      } else {
        target[key] = record
      }
    }
  }

  private func decodeMirrorEnvelope(_ data: Data) throws -> MirrorEnvelope {
    let envelope = try JSONDecoder().decode(MirrorEnvelope.self, from: data)
    guard envelope.version == nativeAlarmMirrorEnvelopeVersion else {
      throw MirrorValidationError.invalid
    }
    return envelope
  }

  private func validatedMirrorEnvelopeState(
    _ envelope: MirrorEnvelope
  ) throws -> (committed: [String: AlarmMirrorRecord], pending: [String: AlarmMirrorRecord]) {
    let committed = try validatedMirror(envelope.committed)
    let pending = try validatedMirror(envelope.pending)
    var combined = committed
    for (key, record) in pending {
      guard combined[key] == nil else { throw MirrorValidationError.invalid }
      combined[key] = record
    }
    _ = try validatedMirror(combined)
    return (committed, pending)
  }

  private func transactionMarkerNeedsRewrite(
    markerData: Data?,
    committedData: Data?,
    pendingData: Data?,
    envelopeData: Data?,
    authoritativePriorEnvelope: Bool,
    normalizedMirror: [String: AlarmMirrorRecord],
    normalizedPendingMirror: [String: AlarmMirrorRecord]
  ) throws -> Bool {
    guard let markerData else {
      // A legacy map-only layout is safe to migrate. Once an envelope exists,
      // however, the absence of a marker is not evidence that its projections
      // belong to one generation; recovery must consult native authority.
      if envelopeData == nil && !authoritativePriorEnvelope {
        return true
      }
      throw MirrorValidationError.invalid
    }
    let marker = try JSONDecoder().decode(MirrorTransactionMarker.self, from: markerData)
    try marker.validate()
    let markerMatches = marker.committedDigest == mirrorDigest(committedData)
      && marker.pendingDigest == mirrorDigest(pendingData)
      && marker.envelopeDigest == mirrorDigest(envelopeData)
    if markerMatches {
      guard let envelopeData,
        let envelope = try? decodeMirrorEnvelope(envelopeData),
        let generation = envelope.generation,
        try canonicalMirrorGeneration(generation) == marker.generation
      else { throw MirrorValidationError.invalid }
      return false
    }

    // Any mismatch is a crash boundary. Even semantically equal maps are not
    // proof of a shared transaction, so defer to recovery-first native
    // correlation instead of accepting or republishing them here.
    _ = authoritativePriorEnvelope
    _ = normalizedMirror
    _ = normalizedPendingMirror
    throw MirrorValidationError.invalid
  }

  private func mirrorDigest(_ data: Data?) -> String {
    let bytes = data ?? Data("<absent>".utf8)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  private func decodeMirrorMap(_ data: Data?) throws -> [String: AlarmMirrorRecord] {
    guard let data else {
      return [:]
    }
    return try JSONDecoder().decode([String: AlarmMirrorRecord].self, from: data)
  }

  private func isMirrorEnvelope(_ data: Data) -> Bool {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else { return false }
    return dictionary["version"] != nil
      || dictionary["committed"] != nil
      || dictionary["pending"] != nil
  }

  private func mergeLegacyMirrorState(
    committed: [String: AlarmMirrorRecord],
    pending: [String: AlarmMirrorRecord]
  ) throws -> (committed: [String: AlarmMirrorRecord], pending: [String: AlarmMirrorRecord]) {
    let normalizedCommitted = try validatedMirror(committed)
    let normalizedPending = try validatedMirror(pending)
    var merged = normalizedCommitted
    var recoverablePending = normalizedPending
    for (key, record) in normalizedPending {
      if let committedRecord = normalizedCommitted[key] {
        guard committedRecord == record else { throw MirrorValidationError.invalid }
        recoverablePending.removeValue(forKey: key)
      } else {
        merged[key] = record
      }
    }
    _ = try validatedMirror(merged)
    return (normalizedCommitted, recoverablePending)
  }

  private func validatedMirror(
    _ mirror: [String: AlarmMirrorRecord]
  ) throws -> [String: AlarmMirrorRecord] {
    var reservationIds = Set<String>()
    var occurrenceIds = Set<String>()
    var platformAlarmIds = Set<String>()
    var normalizedMirror = [String: AlarmMirrorRecord]()

    for (key, record) in mirror {
      let hasLegacyConfiguration = record.scheduledAt == nil &&
        record.targetAt == nil &&
        record.soundId == nil &&
        record.vibrationEnabled == nil
      let hasCompleteConfiguration = record.scheduledAt != nil &&
        record.targetAt != nil &&
        record.soundId?.isEmpty == false &&
        record.vibrationEnabled != nil
      guard let normalizedKey = try? canonicalPlatformAlarmId(key),
        let normalizedRecordId = try? canonicalPlatformAlarmId(record.platformAlarmId),
        normalizedKey == normalizedRecordId,
        !record.reservationId.isEmpty,
        !record.occurrenceId.isEmpty,
        !record.wakePlanId.isEmpty,
        hasLegacyConfiguration || hasCompleteConfiguration,
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
        platformAlarmId: normalizedKey,
        scheduledAt: record.scheduledAt,
        targetAt: record.targetAt,
        soundId: record.soundId,
        vibrationEnabled: record.vibrationEnabled
      )
    }
    return normalizedMirror
  }

  private func saveMirrorState(
    _ mirror: [String: AlarmMirrorRecord],
    pending: [String: AlarmMirrorRecord]
  ) throws {
    let envelope = MirrorEnvelope(
      version: nativeAlarmMirrorEnvelopeVersion,
      generation: UUID().uuidString,
      committed: mirror,
      pending: pending
    )
    let encoder = JSONEncoder()
    let envelopeData = try encoder.encode(envelope)
    let committedData = try encoder.encode(mirror)
    let pendingData = pending.isEmpty ? nil : try encoder.encode(pending)
    let marker = MirrorTransactionMarker(
      version: nativeAlarmMirrorEnvelopeVersion,
      generation: envelope.generation ?? UUID().uuidString,
      committedDigest: mirrorDigest(committedData),
      pendingDigest: mirrorDigest(pendingData),
      envelopeDigest: mirrorDigest(envelopeData)
    )
    let markerData = try encoder.encode(marker)

    // Publish a transaction marker before any artifact. A restart either
    // observes all matching digests or rejects a mixed-generation state;
    // ordering alone must never resurrect stale pending recovery rows. The
    // legacy projection remains decodable by older binaries and intentionally
    // excludes pending-only rows.
    UserDefaults.standard.set(markerData, forKey: nativeAlarmMirrorTransactionKey)
    UserDefaults.standard.set(committedData, forKey: nativeAlarmMirrorKey)
    if let pendingData {
      UserDefaults.standard.set(pendingData, forKey: nativeAlarmPendingMirrorKey)
    } else {
      UserDefaults.standard.removeObject(forKey: nativeAlarmPendingMirrorKey)
    }
    UserDefaults.standard.set(envelopeData, forKey: nativeAlarmMirrorEnvelopeKey)
  }

  private enum ScheduleFailureCleanupOutcome: Equatable {
    case nativePresent
    case nativeAbsent
    case uncertain
  }

  @available(iOS 26.0, *)
  private func removeMirrorEntryIfNativeAlarmAbsent(
    _ platformAlarmId: String,
    request: ScheduleRequest,
    pendingEntryCreated: Bool
  ) -> ScheduleFailureCleanupOutcome {
    do {
      let snapshot: MirrorSnapshot
      do {
        snapshot = try loadMirrorSnapshot()
      } catch {
        let recoveryAlarms = try nativeClientForAlarmKit().inventory()
        snapshot = try recoverMirrorSnapshot(from: recoveryAlarms)
      }
      let currentNativeAlarmIds = Set(
        try authoritativeNativeAlarmIds(
          nativeClientForAlarmKit().inventory().map { $0.platformAlarmId },
          mirrorSnapshot: snapshot
        )
      )
      if currentNativeAlarmIds.contains(platformAlarmId) {
        return .nativePresent
      }

      var mirror = snapshot.stored
      var pendingMirror = snapshot.pendingStored
      let matchingKeys = try (pendingEntryCreated ? pendingMirror.keys : mirror.keys).filter {
        try canonicalPlatformAlarmId($0) == platformAlarmId
      }
      guard matchingKeys.count == 1,
        let matchingKey = matchingKeys.first,
        (pendingEntryCreated ? pendingMirror[matchingKey] : mirror[matchingKey])?.matches(request) == true
      else { return .uncertain }
      if pendingEntryCreated {
        pendingMirror.removeValue(forKey: matchingKey)
        try saveMirrorState(mirror, pending: pendingMirror)
      } else {
        mirror.removeValue(forKey: matchingKey)
        try saveMirrorState(mirror, pending: pendingMirror)
      }
      return .nativeAbsent
    } catch {
      // Preserve the mirror when native inventory or mirror persistence cannot
      // establish that the AlarmKit alarm is absent.
      return .uncertain
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
  // These fields were added after the initial mirror schema. They remain
  // optional so older committed rows can be read and safely replaced on the
  // next retry, rather than being treated as corrupt solely because they do
  // not contain native configuration metadata.
  let scheduledAt: Date?
  let targetAt: Date?
  let soundId: String?
  let vibrationEnabled: Bool?

  init(request: ScheduleRequest, platformAlarmId: String) {
    reservationId = request.reservationId
    occurrenceId = request.occurrenceId
    wakePlanId = request.wakePlanId
    self.platformAlarmId = platformAlarmId
    scheduledAt = request.scheduledAt
    targetAt = request.targetAt
    soundId = request.soundId
    vibrationEnabled = request.vibrationEnabled
  }

  init(
    reservationId: String,
    occurrenceId: String,
    wakePlanId: String,
    platformAlarmId: String,
    scheduledAt: Date? = nil,
    targetAt: Date? = nil,
    soundId: String? = nil,
    vibrationEnabled: Bool? = nil
  ) {
    self.reservationId = reservationId
    self.occurrenceId = occurrenceId
    self.wakePlanId = wakePlanId
    self.platformAlarmId = platformAlarmId
    self.scheduledAt = scheduledAt
    self.targetAt = targetAt
    self.soundId = soundId
    self.vibrationEnabled = vibrationEnabled
  }

  func matches(_ request: ScheduleRequest) -> Bool {
    guard reservationId == request.reservationId &&
      occurrenceId == request.occurrenceId &&
      wakePlanId == request.wakePlanId,
      let scheduledAt,
      let targetAt,
      let soundId,
      let vibrationEnabled
    else {
      return false
    }
    return scheduledAt == request.scheduledAt &&
      targetAt == request.targetAt &&
      soundId == request.soundId &&
      vibrationEnabled == request.vibrationEnabled
  }

  func matchesStableReservation(_ request: ScheduleRequest) -> Bool {
    reservationId == request.reservationId &&
      wakePlanId == request.wakePlanId
  }

  func scheduleRequest() -> ScheduleRequest? {
    guard let scheduledAt,
      let targetAt,
      let soundId,
      let vibrationEnabled
    else {
      return nil
    }
    return ScheduleRequest(
      occurrenceId: occurrenceId,
      reservationId: reservationId,
      wakePlanId: wakePlanId,
      scheduledAt: scheduledAt,
      targetAt: targetAt,
      soundId: soundId,
      vibrationEnabled: vibrationEnabled
    )
  }

  func mergedRecoveryRecord(with other: AlarmMirrorRecord) throws -> AlarmMirrorRecord {
    guard reservationId == other.reservationId,
      occurrenceId == other.occurrenceId,
      wakePlanId == other.wakePlanId,
      platformAlarmId == other.platformAlarmId
    else {
      throw MirrorValidationError.invalid
    }
    return AlarmMirrorRecord(
      reservationId: reservationId,
      occurrenceId: occurrenceId,
      wakePlanId: wakePlanId,
      platformAlarmId: platformAlarmId,
      scheduledAt: try mergeRecoveryValue(scheduledAt, other.scheduledAt),
      targetAt: try mergeRecoveryValue(targetAt, other.targetAt),
      soundId: try mergeRecoveryValue(soundId, other.soundId),
      vibrationEnabled: try mergeRecoveryValue(vibrationEnabled, other.vibrationEnabled)
    )
  }
}

private enum MirrorValidationError: Error {
  case invalid
}

private enum NativeSnapshotValidationError: Error {
  case invalidOrDuplicate
  case unknownIdentity
}

private func mergeRecoveryValue<T: Equatable>(_ first: T?, _ second: T?) throws -> T? {
  guard let first else { return second }
  guard let second else { return first }
  guard first == second else { throw MirrorValidationError.invalid }
  return first
}

private struct MirrorEnvelope: Codable {
  let version: Int
  let generation: String?
  let committed: [String: AlarmMirrorRecord]
  let pending: [String: AlarmMirrorRecord]
}

private struct MirrorTransactionMarker: Codable {
  let version: Int
  let generation: String
  let committedDigest: String
  let pendingDigest: String
  let envelopeDigest: String

  func validate() throws {
    guard version == nativeAlarmMirrorEnvelopeVersion,
      (try? canonicalMirrorGeneration(generation)) != nil,
      isDigest(committedDigest),
      isDigest(pendingDigest),
      isDigest(envelopeDigest)
    else {
      throw MirrorValidationError.invalid
    }
  }

  private func isDigest(_ value: String) -> Bool {
    value.count == 64
      && value.unicodeScalars.allSatisfy { scalar in
        (scalar.value >= 48 && scalar.value <= 57)
          || (scalar.value >= 97 && scalar.value <= 102)
      }
  }
}

private func canonicalMirrorGeneration(_ generation: String) throws -> String {
  guard let uuid = UUID(uuidString: generation),
    generation == uuid.uuidString
  else {
    throw MirrorValidationError.invalid
  }
  return generation
}

private struct RecoveryMirrorArtifact {
  let committed: [String: AlarmMirrorRecord]
  let pending: [String: AlarmMirrorRecord]
  let isPresent: Bool
  let isValid: Bool
  let isPlainProjection: Bool

  init(
    committed: [String: AlarmMirrorRecord] = [:],
    pending: [String: AlarmMirrorRecord] = [:],
    isPresent: Bool = false,
    isValid: Bool = true,
    isPlainProjection: Bool = false
  ) {
    self.committed = committed
    self.pending = pending
    self.isPresent = isPresent
    self.isValid = isValid
    self.isPlainProjection = isPlainProjection
  }

  static let invalid = RecoveryMirrorArtifact(
    isPresent: true,
    isValid: false
  )
}

private struct StoredMirrorState {
  let committed: [String: AlarmMirrorRecord]
  let pending: [String: AlarmMirrorRecord]
  let isEnvelope: Bool
  let legacyPendingPresent: Bool
  let needsProjectionRewrite: Bool
  let needsTransactionMarkerRewrite: Bool
}

private struct MirrorSnapshot {
  let stored: [String: AlarmMirrorRecord]
  let normalized: [String: AlarmMirrorRecord]
  let pendingStored: [String: AlarmMirrorRecord]
  let pendingNormalized: [String: AlarmMirrorRecord]
  let isEnvelope: Bool
  let legacyPendingPresent: Bool
  let needsProjectionRewrite: Bool
  let needsTransactionMarkerRewrite: Bool
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

@MainActor
final class AlarmMirrorCoordinator {
  // UserDefaults stores the committed and pending mirrors as whole maps. Keep
  // every read/normalize/merge/write transaction in one shared FIFO so a
  // native await cannot let another bridge instance save a stale snapshot.
  static let shared = AlarmMirrorCoordinator()

  private struct Tail {
    let token: UUID
    let task: Task<Void, Never>
  }

  private var tail: Tail?

  func run<Value>(
    operation: @escaping @MainActor () async -> Value
  ) async -> Value {
    let token = UUID()
    let predecessor = tail?.task
    return await withCheckedContinuation { continuation in
      let task = Task { @MainActor in
        if let predecessor {
          await predecessor.value
        }
        let value = await operation()
        continuation.resume(returning: value)
        if tail?.token == token {
          tail = nil
        }
      }
      tail = Tail(token: token, task: task)
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

private func canonicalNativeAlarmIds(_ platformAlarmIds: [String]) throws -> [String] {
  var seen = Set<String>()
  return try platformAlarmIds.map { platformAlarmId in
    let canonicalId: String
    do {
      canonicalId = try canonicalPlatformAlarmId(platformAlarmId)
    } catch {
      throw NativeSnapshotValidationError.invalidOrDuplicate
    }
    guard seen.insert(canonicalId).inserted else {
      throw NativeSnapshotValidationError.invalidOrDuplicate
    }
    return canonicalId
  }
}

private func authoritativeNativeAlarmIds(
  _ platformAlarmIds: [String],
  mirrorSnapshot: MirrorSnapshot
) throws -> [String] {
  let canonicalIds = try canonicalNativeAlarmIds(platformAlarmIds)
  let knownIds = Set(mirrorSnapshot.normalized.keys)
    .union(mirrorSnapshot.pendingNormalized.keys)
  guard Set(canonicalIds).subtracting(knownIds).isEmpty else {
    throw NativeSnapshotValidationError.unknownIdentity
  }
  return canonicalIds
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
