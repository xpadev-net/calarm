@_weakLinked import AlarmKit
import Flutter
import Foundation

let nativeAlarmChannelName = "net.xpadev.calarm/native_alarm"
let nativeAlarmSchemaVersion = 1

@MainActor
final class AlarmKitBridge {
  private let channel: FlutterMethodChannel?
  private var alarmObservationTask: Task<Void, Never>?
  private let scheduleCoordinator = AlarmScheduleCoordinator()
  let mirrorCoordinator = AlarmMirrorCoordinator.shared
  var pendingNativeAlarmIds = Set<String>()
  private let nativeClient: (any AlarmKitNativeClient)?
  private let replacementBeforeCommit: (() throws -> Void)?
  private let replacementAfterRetireBeforeCommit: (() throws -> Void)?

  init(
    messenger: FlutterBinaryMessenger,
    nativeClient: (any AlarmKitNativeClient)? = nil,
    replacementBeforeCommit: (() throws -> Void)? = nil,
    replacementAfterRetireBeforeCommit: (() throws -> Void)? = nil
  ) {
    let methodChannel = FlutterMethodChannel(
      name: nativeAlarmChannelName,
      binaryMessenger: messenger
    )
    channel = methodChannel
    self.nativeClient = nativeClient
    self.replacementBeforeCommit = replacementBeforeCommit
    self.replacementAfterRetireBeforeCommit = replacementAfterRetireBeforeCommit
    methodChannel.setMethodCallHandler(handle)
    if #available(iOS 26.0, *) {
      alarmObservationTask = Task { @MainActor [weak self] in
        await self?.observeAlarmUpdates()
      }
    }
  }

  init(
    nativeClient: any AlarmKitNativeClient,
    replacementBeforeCommit: (() throws -> Void)? = nil,
    replacementAfterRetireBeforeCommit: (() throws -> Void)? = nil
  ) {
    channel = nil
    self.nativeClient = nativeClient
    self.replacementBeforeCommit = replacementBeforeCommit
    self.replacementAfterRetireBeforeCommit = replacementAfterRetireBeforeCommit
  }

  // Internal so RunnerTests can exercise the exact production MethodChannel
  // dispatcher without substituting a parallel test-only routing path.
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
    var alarms: [NativeAlarmSnapshot]
    do {
      alarms = try nativeClientForAlarmKit().inventory()
    } catch {
      return FlutterError(
        code: "nativeError",
        message: error.localizedDescription,
        details: nil
      )
    }

    var mirrorSnapshot: MirrorSnapshot
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
      try validateAuthorityConsistency(mirrorSnapshot)
      if try loadReplacementJournal() != nil {
        mirrorSnapshot = try await reconcileReplacementJournal(
          in: mirrorSnapshot,
          nativeAlarms: alarms
        )
        alarms = try nativeClientForAlarmKit().inventory()
      }
      let recovery = try await restoreRequiredNativeConfigurations(
        in: mirrorSnapshot
      )
      mirrorSnapshot = recovery.snapshot
      if recovery.didRestore {
        alarms = try nativeClientForAlarmKit().inventory()
      }
    } catch {
      return FlutterError(
        code: "nativeError",
        message: "AlarmKit recovery could not restore the last authoritative configuration.",
        details: nil
      )
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
        currentIds.contains($0.key)
          || pendingNativeAlarmIds.contains($0.key)
          || $0.value.requiresNativeRestoration == true
      }
      for (platformAlarmId, record) in reconciledMirror
      where prunedMirror[platformAlarmId] == nil {
        try persistRetirement(record)
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
    guard let reservationGeneration = exactNonNegativeInt(
      payload.keys.contains("reservationGeneration")
        ? payloadValue(payload, "reservationGeneration")
        : 0
    ) else {
      return scheduleFailureRow(
        occurrenceId: occurrenceId,
        reservationId: reservationId,
        reservationGeneration: 0,
        wakePlanId: wakePlanId,
        reason: "invalidRequest",
        message: "reservationGeneration must be a non-negative integer."
      )
    }

    let request = ScheduleRequest(
      occurrenceId: occurrenceId,
      reservationId: reservationId,
      reservationGeneration: reservationGeneration,
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
        reservationGeneration: reservationGeneration,
        wakePlanId: wakePlanId,
        platformAlarmId: row.platformAlarmId ?? ""
      )
    }
    return scheduleFailureRow(
      occurrenceId: occurrenceId,
      reservationId: reservationId,
      reservationGeneration: reservationGeneration,
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
    guard let requestedReservationId = stringValue(payloadValue(payload, "reservationId")),
      !requestedReservationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: stringValue(payloadValue(payload, "reservationId")) ?? "",
        platformAlarmId: stringValue(payloadValue(payload, "platformAlarmId")) ?? "",
        reason: "invalidRequest",
        message: "reservationId must be a non-empty string."
      )
    }
    let responseReservationId = requestedReservationId
    guard let reservationGeneration = exactNonNegativeInt(
      payload.keys.contains("reservationGeneration")
        ? payloadValue(payload, "reservationGeneration")
        : 0
    ) else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: responseReservationId,
        reservationGeneration: 0,
        platformAlarmId: stringValue(payloadValue(payload, "platformAlarmId")) ?? "",
        reason: "invalidRequest",
        message: "reservationGeneration must be a non-negative integer."
      )
    }
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
        reservationGeneration: reservationGeneration,
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
        reservationGeneration: reservationGeneration,
        platformAlarmId: responsePlatformAlarmId,
        reason: "invalidRequest",
        message: "platformAlarmId must be an AlarmKit UUID."
      )
    }
    guard #available(iOS 26.0, *) else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: responseReservationId,
        reservationGeneration: reservationGeneration,
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
        reservationGeneration: reservationGeneration,
        platformAlarmId: platformAlarmId,
        responsePlatformAlarmId: responsePlatformAlarmId,
        alarmId: alarmId
      )
    }
  }

  @available(iOS 26.0, *)
  private func performCancelAlarm(
    occurrenceId: String,
    requestedReservationId: String,
    responseReservationId: String,
    reservationGeneration: Int,
    platformAlarmId: String,
    responsePlatformAlarmId: String,
    alarmId: UUID
  ) async -> [String: Any?] {
    await mirrorCoordinator.run {
      await self.performCancelAlarmInMirrorTransaction(
        occurrenceId: occurrenceId,
        requestedReservationId: requestedReservationId,
        responseReservationId: responseReservationId,
        reservationGeneration: reservationGeneration,
        platformAlarmId: platformAlarmId,
        responsePlatformAlarmId: responsePlatformAlarmId,
        alarmId: alarmId
      )
    }
  }

  @available(iOS 26.0, *)
  private func performCancelAlarmInMirrorTransaction(
    occurrenceId: String,
    requestedReservationId: String,
    responseReservationId: String,
    reservationGeneration: Int,
    platformAlarmId: String,
    responsePlatformAlarmId: String,
    alarmId: UUID
  ) async -> [String: Any?] {
    do {
      var mirrorSnapshot: MirrorSnapshot
      do {
        mirrorSnapshot = try loadMirrorSnapshot()
      } catch {
        let recoveryAlarms = try nativeClientForAlarmKit().inventory()
        mirrorSnapshot = try recoverMirrorSnapshot(from: recoveryAlarms)
      }
      var authorities = try loadReservationAuthorities()
      let hasReplacementJournal = try loadReplacementJournal() != nil
      if hasReplacementJournal {
        if let failure = cancelOwnershipFailure(
          in: mirrorSnapshot,
          occurrenceId: occurrenceId,
          reservationId: requestedReservationId,
          reservationGeneration: reservationGeneration,
          platformAlarmId: platformAlarmId,
          responsePlatformAlarmId: responsePlatformAlarmId
        ) {
          return failure
        }
        mirrorSnapshot = try await reconcileReplacementJournal(in: mirrorSnapshot)
        authorities = try loadReservationAuthorities()
      }
      let ownedAfterRecovery = mirrorSnapshot.normalized[platformAlarmId]
        ?? mirrorSnapshot.pendingNormalized[platformAlarmId]
      if let authority = authorities[requestedReservationId] {
        guard authority.matchesCancellation(
          occurrenceId: occurrenceId,
          reservationId: requestedReservationId,
          reservationGeneration: reservationGeneration,
          platformAlarmId: platformAlarmId
        ) else {
          return cancelFailureRow(
            occurrenceId: occurrenceId,
            reservationId: responseReservationId,
            reservationGeneration: reservationGeneration,
            platformAlarmId: responsePlatformAlarmId,
            reason: "invalidRequest",
            message: "AlarmKit generation authority does not match the cancellation."
          )
        }
        if authority.state == .retired {
          if ownedAfterRecovery != nil {
            if let failure = cancelOwnershipFailure(
              in: mirrorSnapshot,
              occurrenceId: occurrenceId,
              reservationId: requestedReservationId,
              reservationGeneration: reservationGeneration,
              platformAlarmId: platformAlarmId,
              responsePlatformAlarmId: responsePlatformAlarmId
            ) {
              return failure
            }
            try nativeClientForAlarmKit().cancel(id: alarmId)
            var mirror = mirrorSnapshot.normalized
            var pending = mirrorSnapshot.pendingNormalized
            mirror.removeValue(forKey: platformAlarmId)
            pending.removeValue(forKey: platformAlarmId)
            try saveMirrorState(mirror, pending: pending)
          } else {
            let nativeAlarmIds = Set(
              try canonicalNativeAlarmIds(
                nativeClientForAlarmKit().inventory().map { $0.platformAlarmId }
              )
            )
            if nativeAlarmIds.contains(platformAlarmId) {
              return cancelFailureRow(
                occurrenceId: occurrenceId,
                reservationId: responseReservationId,
                reservationGeneration: reservationGeneration,
                platformAlarmId: responsePlatformAlarmId,
                reason: "invalidRequest",
                message: "AlarmKit identity ownership could not be verified."
              )
            }
          }
          return cancelSuccessRow(
            occurrenceId: occurrenceId,
            reservationId: responseReservationId,
            reservationGeneration: reservationGeneration,
            platformAlarmId: responsePlatformAlarmId
          )
        }
      } else {
        guard let ownedAfterRecovery,
          ownedAfterRecovery.reservationId == requestedReservationId,
          ownedAfterRecovery.occurrenceId == occurrenceId,
          ownedAfterRecovery.generation == reservationGeneration
        else {
          return cancelFailureRow(
            occurrenceId: occurrenceId,
            reservationId: responseReservationId,
            reservationGeneration: reservationGeneration,
            platformAlarmId: responsePlatformAlarmId,
            reason: "invalidRequest",
            message: "AlarmKit identity ownership could not be verified."
          )
        }
        authorities[requestedReservationId] = ReservationAuthorityRecord(
          record: ownedAfterRecovery,
          state: .active
        )
        try saveReservationAuthorities(authorities)
      }
      if let failure = cancelOwnershipFailure(
        in: mirrorSnapshot,
        occurrenceId: occurrenceId,
        reservationId: requestedReservationId,
        reservationGeneration: reservationGeneration,
        platformAlarmId: platformAlarmId,
        responsePlatformAlarmId: responsePlatformAlarmId
      ) {
        return failure
      }
      var mirror = mirrorSnapshot.normalized
      var pendingMirror = mirrorSnapshot.pendingNormalized
      guard let retiringRecord = mirror[platformAlarmId] ?? pendingMirror[platformAlarmId]
      else { throw MirrorValidationError.invalid }
      try persistRetirement(retiringRecord)
      try nativeClientForAlarmKit().cancel(id: alarmId)
      mirror.removeValue(forKey: platformAlarmId)
      pendingMirror.removeValue(forKey: platformAlarmId)
      try saveMirrorState(mirror, pending: pendingMirror)
      return cancelSuccessRow(
        occurrenceId: occurrenceId,
        reservationId: responseReservationId,
        reservationGeneration: reservationGeneration,
        platformAlarmId: responsePlatformAlarmId
      )
    } catch {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: responseReservationId,
        reservationGeneration: reservationGeneration,
        platformAlarmId: responsePlatformAlarmId,
        reason: "nativeError",
        message: error.localizedDescription
      )
    }
  }

  private func cancelOwnershipFailure(
    in mirrorSnapshot: MirrorSnapshot,
    occurrenceId: String,
    reservationId: String,
    reservationGeneration: Int,
    platformAlarmId: String,
    responsePlatformAlarmId: String
  ) -> [String: Any?]? {
    guard
      let ownedRecord = mirrorSnapshot.normalized[platformAlarmId]
        ?? mirrorSnapshot.pendingNormalized[platformAlarmId]
    else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: reservationId,
        reservationGeneration: reservationGeneration,
        platformAlarmId: responsePlatformAlarmId,
        reason: "invalidRequest",
        message: "AlarmKit identity ownership could not be verified."
      )
    }
    if ownedRecord.requiresNativeRestoration == true {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: reservationId,
        reservationGeneration: reservationGeneration,
        platformAlarmId: responsePlatformAlarmId,
        reason: "unknown",
        message: "AlarmKit identity must be restored before it can be cancelled."
      )
    }
    guard ownedRecord.reservationId == reservationId,
      ownedRecord.occurrenceId == occurrenceId,
      ownedRecord.generation == reservationGeneration,
      ownedRecord.platformAlarmId == platformAlarmId
    else {
      return cancelFailureRow(
        occurrenceId: occurrenceId,
        reservationId: reservationId,
        reservationGeneration: reservationGeneration,
        platformAlarmId: responsePlatformAlarmId,
        reason: "invalidRequest",
        message: "AlarmKit identity does not match the requested reservation."
      )
    }
    return nil
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

    var platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    guard var alarmId = UUID(uuidString: platformAlarmId) else {
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
      var mirrorSnapshot: MirrorSnapshot
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
      let authorityPlatformAlarmId = mirrorSnapshot.normalized.first(where: {
        $0.value.reservationId == request.reservationId
      })?.key ?? mirrorSnapshot.pendingNormalized.first(where: {
        $0.value.reservationId == request.reservationId
      })?.key ?? platformAlarmId
      do {
        try admitScheduleGeneration(
          request,
          platformAlarmId: authorityPlatformAlarmId,
          snapshot: mirrorSnapshot
        )
      } catch is ReservationAuthorityError {
        return ScheduleRow(
          status: "failure",
          platformAlarmId: nil,
          failureReason: "invalidRequest",
          failureMessage: "reservationGeneration conflicts with durable native authority."
        )
      } catch {
        return ScheduleRow(
          status: "failure",
          platformAlarmId: nil,
          failureReason: "unknown",
          failureMessage: "Native reservation generation authority is corrupt."
        )
      }
      if try loadReplacementJournal() != nil {
        mirrorSnapshot = try await reconcileReplacementJournal(in: mirrorSnapshot)
      }
      if mirrorSnapshot.pendingNormalized[platformAlarmId]?.requiresNativeRestoration == true {
        mirrorSnapshot = try await restoreRequiredNativeConfigurations(
          in: mirrorSnapshot,
          restrictedTo: Set([platformAlarmId])
        ).snapshot
      }
      var mirror = mirrorSnapshot.normalized
      var pendingMirror = mirrorSnapshot.pendingNormalized
      let committedReservationMatches = mirror.filter {
        $0.value.reservationId == request.reservationId
      }
      let pendingReservationMatches = pendingMirror.filter {
        $0.value.reservationId == request.reservationId
      }
      guard committedReservationMatches.count + pendingReservationMatches.count <= 1 else {
        throw MirrorValidationError.invalid
      }
      let conflictingOccurrenceOwner = mirror.values.contains { record in
        record.occurrenceId == request.occurrenceId
          && (record.reservationId != request.reservationId
            || record.wakePlanId != request.wakePlanId)
      } || pendingMirror.values.contains { record in
        record.occurrenceId == request.occurrenceId
          && (record.reservationId != request.reservationId
            || record.wakePlanId != request.wakePlanId)
      }
      if conflictingOccurrenceOwner {
        return ScheduleRow(
          status: "failure",
          platformAlarmId: nil,
          failureReason: "invalidRequest",
          failureMessage: "occurrenceId is already owned by another reservation."
        )
      }
      if let active = committedReservationMatches.first ?? pendingReservationMatches.first {
        platformAlarmId = active.key
        guard let activeAlarmId = UUID(uuidString: platformAlarmId) else {
          throw MirrorValidationError.invalid
        }
        alarmId = activeAlarmId
      }
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
          // A complete pending row can represent an initial schedule that
          // mutated AlarmKit before its reply was lost. Native presence proves
          // that old UUID is still the safe active alarm. Promote that exact
          // tuple before journaling a replacement so every restart sees the
          // old side in committed ownership and no stale pending row survives
          // either commitNew() or retainOld().
          if committedExisting == nil {
            guard pendingExisting == existing,
              existing.scheduleRequest() != nil
            else {
              throw MirrorValidationError.invalid
            }
            mirror[platformAlarmId] = existing
            try saveMirrorState(mirror, pending: pendingMirror)
          }

          // A replacement uses a distinct, durably journaled UUID. The old
          // alarm stays authoritative and native-present until the new alarm
          // is verified, so no finite native failure can create a missed-fire
          // gap. The journal keeps both exact tuples owned across restart.
          let candidatePlatformAlarmId = try canonicalPlatformAlarmId(UUID().uuidString)
          guard let candidateAlarmId = UUID(uuidString: candidatePlatformAlarmId) else {
            throw MirrorValidationError.invalid
          }
          let candidateRecord = AlarmMirrorRecord(
            request: request,
            platformAlarmId: candidatePlatformAlarmId
          )
          try updateScheduleAuthorityPlatform(
            request,
            platformAlarmId: candidatePlatformAlarmId
          )
          let journal = AlarmReplacementJournal(
            old: existing,
            new: candidateRecord,
            phase: .staging
          )
          try saveReplacementJournal(journal)
          do {
            let scheduledPlatformAlarmId = try await nativeClientForAlarmKit().schedule(
              id: candidateAlarmId,
              request: request
            )
            guard try canonicalPlatformAlarmId(scheduledPlatformAlarmId)
              == candidatePlatformAlarmId
            else {
              throw MirrorValidationError.invalid
            }
            // Test seam for the external-side-effect/durable-phase boundary.
            try replacementBeforeCommit?()
          } catch {
            let resolved = try? await reconcileReplacementJournal(
              in: loadMirrorSnapshot()
            )
            let activeRecord = resolved?.normalized.values.first(where: {
              $0.reservationId == request.reservationId
            })
            let activeId = activeRecord?.matches(request) == true
              ? activeRecord?.platformAlarmId
              : nil
            return ScheduleRow(
              status: "failure",
              platformAlarmId: activeId,
              failureReason: "nativeError",
              failureMessage: error.localizedDescription
            )
          }

          // Keep the durable journal in staging until the old UUID is gone.
          // A process loss before retirement therefore keeps the old alarm
          // authoritative and rolls the candidate back on restart. If cancel
          // mutates and then throws, authoritative inventory is new-only and
          // staging recovery safely commits the candidate.
          try persistRetirement(existing)
          do { try nativeClientForAlarmKit().cancel(id: alarmId) } catch {}

          // Do not expose an application-controlled failure boundary while
          // both UUIDs are known live. Verify retirement first; the test seam
          // can then model a lost reply only when the candidate is the sole
          // owned native alarm. Other authoritative states go directly to
          // finite reconciliation.
          let postRetireAlarms = try nativeClientForAlarmKit().inventory()
          let postRetireIds = try Set(
            canonicalNativeAlarmIds(postRetireAlarms.map { $0.platformAlarmId })
          )
          let knownIds = Set(mirror.keys)
            .union(pendingMirror.keys)
            .union([platformAlarmId, candidatePlatformAlarmId])
          guard postRetireIds.subtracting(knownIds).isEmpty else {
            throw NativeSnapshotValidationError.unknownIdentity
          }
          if postRetireIds == Set([candidatePlatformAlarmId]) {
            do {
              try replacementAfterRetireBeforeCommit?()
            } catch {
              // The staging journal and sole verified candidate survive a
              // lost reply; restart recovery commits that exact tuple.
              return ScheduleRow(
                status: "failure",
                platformAlarmId: nil,
                failureReason: "nativeError",
                failureMessage: error.localizedDescription
              )
            }
          }

          let resolved = try await reconcileReplacementJournal(
            in: loadMirrorSnapshot(),
            nativeAlarms: postRetireAlarms
          )
          if resolved.normalized[candidatePlatformAlarmId] == candidateRecord {
            return ScheduleRow(
              status: "success",
              platformAlarmId: candidatePlatformAlarmId,
              failureReason: nil,
              failureMessage: nil
            )
          }
          return ScheduleRow(
            status: "failure",
            platformAlarmId: nil,
            failureReason: "nativeError",
            failureMessage: "AlarmKit could not retire the prior alarm safely."
          )
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
        platformAlarmId: cleanup == .nativePresent
          && mirrorOwnsMatchingTuple(platformAlarmId, request: request)
          ? platformAlarmId
          : nil,
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
        platformAlarmId: cleanup == .nativePresent
          && mirrorOwnsMatchingTuple(platformAlarmId, request: request)
          ? platformAlarmId
          : nil,
        failureReason: "nativeError",
        failureMessage: error.localizedDescription
      )
    }
  }

  @available(iOS 26.0, *)
  func nativeClientForAlarmKit() -> any AlarmKitNativeClient {
    nativeClient ?? SystemAlarmKitClient()
  }
}
