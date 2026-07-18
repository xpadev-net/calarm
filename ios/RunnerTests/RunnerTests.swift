import Foundation
import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  func testAlarmKitUsageDescriptionIsConfigured() throws {
    let usageDescription = try XCTUnwrap(
      Bundle.main.object(forInfoDictionaryKey: "NSAlarmKitUsageDescription") as? String
    )

    XCTAssertFalse(usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  func testStablePlatformAlarmIdIsDeterministicAndUuidBacked() throws {
    let first = calarmPlatformAlarmId(for: "reservation-1")
    let second = calarmPlatformAlarmId(for: "reservation-1")
    let different = calarmPlatformAlarmId(for: "reservation-2")

    XCTAssertEqual(first, second)
    XCTAssertNotEqual(first, different)
    XCTAssertNotNil(UUID(uuidString: first))
    XCTAssertEqual(first.split(separator: "-")[2].first, "5")
  }

  @available(iOS 26.0, *)
  func testAlarmKitInventoryStatusMapsAlertingAndScheduledStates() {
    XCTAssertEqual(inventoryStatus(for: .scheduled), "scheduled")
    XCTAssertEqual(inventoryStatus(for: .alerting), "ringing")
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeDuplicateScheduleFailureRemainsRecoverable() async {
    let fake = FakeAlarmKitNativeClient()
    fake.gateFirstSchedule = true
    fake.failFirstSchedule = true
    fake.gatedScheduleAttempts = [2]
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest()
    clearMirror()
    defer { clearMirror() }

    let first = Task { @MainActor in await bridge.scheduleAlarm(request) }
    while !fake.firstScheduleStarted { await Task.yield() }
    let second = Task { @MainActor in await bridge.scheduleAlarm(request) }
    await Task.yield()
    fake.allowFirstScheduleToFinish = true

    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    let firstResult = await first.value
    while !fake.gatedScheduleStartedAttempts.contains(2) { await Task.yield() }
    XCTAssertFalse(mirrorContains(platformAlarmId))
    fake.allowGatedSchedules = true
    let secondResult = await second.value
    XCTAssertEqual(firstResult.failureReason, "nativeError")
    XCTAssertEqual(secondResult.status, "success")
    XCTAssertEqual(fake.maxActiveSchedules, 1)
    XCTAssertEqual(fake.nativeAlarmIds, Set([platformAlarmId.uppercased()]))
    XCTAssertTrue(mirrorContains(platformAlarmId))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeScheduleFailureRemovesMirrorBeforeRetry() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failFirstSchedule = true
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-cleanup")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let firstResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(firstResult.failureReason, "nativeError")
    XCTAssertFalse(mirrorContains(platformAlarmId))

    let retryResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(retryResult.status, "success")
    XCTAssertTrue(mirrorContains(platformAlarmId))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeStableReservationRetryUpdatesRecreatedOccurrence() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let original = makeScheduleRequest("reservation-recreated")
    let recreated = makeScheduleRequest(
      "reservation-recreated",
      occurrenceId: "occurrence-recreated"
    )
    let platformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    clearMirror()
    defer { clearMirror() }

    let originalResult = await bridge.scheduleAlarm(original)
    XCTAssertEqual(originalResult.status, "success")
    let retryResult = await bridge.scheduleAlarm(recreated)
    XCTAssertEqual(retryResult.status, "success")
    XCTAssertEqual(fake.scheduleAttempts, 2)
    XCTAssertEqual(fake.cancelCalls, 1)
    let replacementPlatformAlarmId = retryResult.platformAlarmId
    XCTAssertNotNil(replacementPlatformAlarmId)
    XCTAssertNotEqual(replacementPlatformAlarmId, platformAlarmId)

    let inventory = await inventoryValue(bridge)
    let rows = (inventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["reservationId"] as? String, original.reservationId)
    XCTAssertEqual(rows?.first?["occurrenceId"] as? String, recreated.occurrenceId)
    XCTAssertEqual(
      rows?.first?["platformAlarmId"] as? String,
      replacementPlatformAlarmId
    )
    XCTAssertFalse(mirrorContains(platformAlarmId))
    XCTAssertTrue(mirrorContains(replacementPlatformAlarmId!))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeLostScheduleReplyReconcilesAfterRestartWithoutDuplicateOrStranding() async {
    let fake = FakeAlarmKitNativeClient()
    let reservationId = "reservation-lost-reply"
    let occurrenceId = "occurrence-lost-reply"
    let wakePlanId = "wake-plan-1"
    let platformAlarmId = calarmPlatformAlarmId(for: reservationId)
    var occurrencePayload = makeSchedulePayload(occurrenceId: occurrenceId)
    occurrencePayload["reservationId"] = reservationId
    let scheduleArguments: [String: Any?] = [
      "schemaVersion": 1,
      "occurrences": [occurrencePayload],
    ]
    clearMirror()
    defer { clearMirror() }

    let originalBridge = AlarmKitBridge(nativeClient: fake)
    // Native scheduling completes, but the application discards the reply as
    // if the MethodChannel transport/process were lost immediately afterward.
    _ = await methodChannelValue(
      originalBridge,
      method: "scheduleOccurrences",
      arguments: scheduleArguments
    )
    XCTAssertEqual(fake.scheduleAttempts, 1)

    let restartedBridge = AlarmKitBridge(nativeClient: fake)
    let inventory = await methodChannelValue(
      restartedBridge,
      method: "getInventory",
      arguments: ["schemaVersion": 1]
    )
    let rows = (inventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["reservationId"] as? String, reservationId)
    XCTAssertEqual(rows?.first?["occurrenceId"] as? String, occurrenceId)
    XCTAssertEqual(rows?.first?["wakePlanId"] as? String, wakePlanId)
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, platformAlarmId)

    let retry = await methodChannelValue(
      restartedBridge,
      method: "scheduleOccurrences",
      arguments: scheduleArguments
    )
    let retryRows = (retry as? [String: Any?])?["occurrences"]
      as? [[String: Any?]]
    XCTAssertEqual(retryRows?.first?["status"] as? String, "success")
    XCTAssertEqual(retryRows?.first?["platformAlarmId"] as? String, platformAlarmId)
    XCTAssertEqual(fake.scheduleAttempts, 1)
    XCTAssertEqual(fake.nativeAlarmIds, Set([platformAlarmId.uppercased()]))

    let cancel = await methodChannelValue(
      restartedBridge,
      method: "cancelOccurrences",
      arguments: [
        "schemaVersion": 1,
        "alarms": [[
          "occurrenceId": occurrenceId,
          "reservationId": reservationId,
          "platformAlarmId": platformAlarmId,
        ]],
      ]
    )
    let cancelRows = (cancel as? [String: Any?])?["alarms"]
      as? [[String: Any?]]
    XCTAssertEqual(cancelRows?.first?["status"] as? String, "success")
    XCTAssertTrue(fake.nativeAlarmIds.isEmpty)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeLostReplacementReplyRestoresPriorTupleBeforeRestartInventory() async {
    let fake = FakeAlarmKitNativeClient()
    fake.inventoryErrorOnCall = 3
    let reservationId = "reservation-lost-replacement-reply"
    let originalOccurrenceId = "occurrence-before-lost-replacement"
    let replacementOccurrenceId = "occurrence-after-lost-replacement"
    let platformAlarmId = calarmPlatformAlarmId(for: reservationId)
    var originalPayload = makeSchedulePayload(occurrenceId: originalOccurrenceId)
    originalPayload["reservationId"] = reservationId
    var replacementPayload = makeSchedulePayload(occurrenceId: replacementOccurrenceId)
    replacementPayload["reservationId"] = reservationId
    let originalArguments: [String: Any?] = [
      "schemaVersion": 1,
      "occurrences": [originalPayload],
    ]
    let replacementArguments: [String: Any?] = [
      "schemaVersion": 1,
      "occurrences": [replacementPayload],
    ]
    clearMirror()
    defer { clearMirror() }

    let interruptedBridge = AlarmKitBridge(
      nativeClient: fake,
      replacementBeforeCommit: {
        throw FakeAlarmKitNativeClient.FakeError.scheduleFailed
      }
    )
    _ = await methodChannelValue(
      interruptedBridge,
      method: "scheduleOccurrences",
      arguments: originalArguments
    )
    XCTAssertEqual(fake.scheduleAttempts, 1)

    // The distinct candidate exists, but the reply is lost before the verified
    // phase and recovery inventory is unavailable to the interrupted bridge.
    let interrupted = await methodChannelValue(
      interruptedBridge,
      method: "scheduleOccurrences",
      arguments: replacementArguments
    )
    XCTAssertEqual(fake.scheduleAttempts, 2)
    let interruptedRows = (interrupted as? [String: Any?])?["occurrences"]
      as? [[String: Any?]]
    XCTAssertEqual(interruptedRows?.first?["status"] as? String, "failure")
    XCTAssertNil(interruptedRows?.first?["platformAlarmId"] as? String)
    XCTAssertEqual(fake.nativeAlarmIds.count, 2)
    XCTAssertTrue(mirrorContains(platformAlarmId))

    fake.inventoryErrorOnCall = nil
    let restartedBridge = AlarmKitBridge(nativeClient: fake)

    fake.inventoryError = true
    await restartedBridge.reconcileMirror(
      withNativeAlarmIds: [platformAlarmId]
    )
    XCTAssertNotNil(UserDefaults.standard.data(forKey: replacementJournalKey))
    fake.inventoryError = false

    let unrelatedPlatformAlarmId = calarmPlatformAlarmId(
      for: "reservation-observer-unknown"
    )
    fake.nativeAlarmIds.insert(unrelatedPlatformAlarmId.uppercased())
    await restartedBridge.reconcileMirror(
      withNativeAlarmIds: [platformAlarmId]
    )
    XCTAssertNotNil(UserDefaults.standard.data(forKey: replacementJournalKey))
    fake.nativeAlarmIds.remove(unrelatedPlatformAlarmId.uppercased())

    // Launch captured old-only before entering the mirror transaction, but
    // current native state is both-live. Recovery must refetch inside the
    // transaction, cancel the candidate, and retain the old tuple.
    fake.inventoryIdsByCall[fake.inventoryCalls + 1] = [platformAlarmId]
    await restartedBridge.reconcileMirrorOnObservationStart()
    XCTAssertNil(UserDefaults.standard.data(forKey: replacementJournalKey))
    let inventory = await methodChannelValue(
      restartedBridge,
      method: "getInventory",
      arguments: ["schemaVersion": 1]
    )
    let rows = (inventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["reservationId"] as? String, reservationId)
    XCTAssertEqual(rows?.first?["occurrenceId"] as? String, originalOccurrenceId)
    XCTAssertEqual(rows?.first?["wakePlanId"] as? String, "wake-plan-1")
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, platformAlarmId)
    XCTAssertEqual(fake.scheduleAttempts, 2)
    XCTAssertEqual(
      fake.scheduledRequests[platformAlarmId]?.occurrenceId,
      originalOccurrenceId
    )

    let retry = await methodChannelValue(
      restartedBridge,
      method: "scheduleOccurrences",
      arguments: replacementArguments
    )
    let retryRows = (retry as? [String: Any?])?["occurrences"]
      as? [[String: Any?]]
    XCTAssertEqual(retryRows?.first?["status"] as? String, "success")
    let replacementPlatformAlarmId = retryRows?.first?["platformAlarmId"] as? String
    XCTAssertNotNil(replacementPlatformAlarmId)
    XCTAssertNotEqual(replacementPlatformAlarmId, platformAlarmId)
    XCTAssertEqual(fake.scheduleAttempts, 3)
    XCTAssertEqual(fake.nativeAlarmIds.count, 1)
    XCTAssertEqual(
      fake.scheduledRequests[replacementPlatformAlarmId!]?.occurrenceId,
      replacementOccurrenceId
    )
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeSameOccurrenceRetryUpdatesNativeConfiguration() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let original = makeScheduleRequest("reservation-config-retry")
    let updated = ScheduleRequest(
      occurrenceId: original.occurrenceId,
      reservationId: original.reservationId,
      wakePlanId: original.wakePlanId,
      scheduledAt: original.scheduledAt.addingTimeInterval(60),
      targetAt: original.targetAt.addingTimeInterval(60),
      soundId: "updated",
      vibrationEnabled: false
    )
    clearMirror()
    defer { clearMirror() }

    let originalResult = await bridge.scheduleAlarm(original)
    XCTAssertEqual(originalResult.status, "success")
    let updatedResult = await bridge.scheduleAlarm(updated)
    XCTAssertEqual(updatedResult.status, "success")
    XCTAssertEqual(fake.scheduleAttempts, 2)
    XCTAssertEqual(fake.cancelCalls, 1)

    let originalPlatformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    XCTAssertNotEqual(updatedResult.platformAlarmId, originalPlatformAlarmId)
    let stored = fake.scheduledRequests[updatedResult.platformAlarmId!]
    XCTAssertEqual(stored?.scheduledAt, updated.scheduledAt)
    XCTAssertEqual(stored?.targetAt, updated.targetAt)
    XCTAssertEqual(stored?.soundId, updated.soundId)
    XCTAssertEqual(stored?.vibrationEnabled, updated.vibrationEnabled)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeReplacementFailureRestoresPriorNativeAlarmAndMirror() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failedScheduleAttempts = [2]
    let bridge = AlarmKitBridge(nativeClient: fake)
    let original = makeScheduleRequest("reservation-replacement-rollback")
    let replacement = makeScheduleRequest(
      "reservation-replacement-rollback",
      occurrenceId: "occurrence-replacement"
    )
    let platformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    clearMirror()
    defer { clearMirror() }

    let originalResult = await bridge.scheduleAlarm(original)
    XCTAssertEqual(originalResult.status, "success")

    let replacementResult = await bridge.scheduleAlarm(replacement)
    XCTAssertEqual(replacementResult.status, "failure")
    XCTAssertEqual(replacementResult.failureReason, "nativeError")
    XCTAssertNil(replacementResult.platformAlarmId)
    XCTAssertEqual(fake.cancelCalls, 0)
    XCTAssertTrue(fake.nativeAlarmIds.contains(platformAlarmId.uppercased()))
    XCTAssertEqual(
      fake.scheduledRequests[platformAlarmId]?.occurrenceId,
      original.occurrenceId
    )
    XCTAssertTrue(mirrorContains(platformAlarmId))

    let inventory = await inventoryValue(bridge)
    let rows = (inventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["occurrenceId"] as? String, original.occurrenceId)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeReplacementUnknownOutcomeKeepsRecoverablePriorIdentity() async {
    let fake = FakeAlarmKitNativeClient()
    fake.throwAfterMutationScheduleAttempts = [2]
    let bridge = AlarmKitBridge(nativeClient: fake)
    let original = makeScheduleRequest("reservation-replacement-unknown")
    let replacement = makeScheduleRequest(
      "reservation-replacement-unknown",
      occurrenceId: "occurrence-replacement-unknown"
    )
    let platformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    clearMirror()
    defer { clearMirror() }

    let originalResult = await bridge.scheduleAlarm(original)
    XCTAssertEqual(originalResult.status, "success")
    let replacementResult = await bridge.scheduleAlarm(replacement)
    XCTAssertEqual(replacementResult.status, "failure")
    XCTAssertEqual(replacementResult.failureReason, "nativeError")
    XCTAssertNil(replacementResult.platformAlarmId)
    XCTAssertTrue(fake.nativeAlarmIds.contains(platformAlarmId.uppercased()))
    XCTAssertEqual(fake.nativeAlarmIds.count, 1)
    XCTAssertTrue(mirrorContains(platformAlarmId))
    XCTAssertFalse(pendingMirrorContains(platformAlarmId))

    let blockedCancel = await bridge.cancelAlarm([
      "occurrenceId": original.occurrenceId,
      "reservationId": original.reservationId,
      "platformAlarmId": platformAlarmId,
    ])
    XCTAssertEqual(blockedCancel["status"] as? String, "success")
    XCTAssertEqual(fake.cancelCalls, 2)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeOldCancelFailureAbortsCandidateAndKeepsOldAlarm() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failedCancelAttempts = [1]
    var postRetireSeamCalls = 0
    let bridge = AlarmKitBridge(
      nativeClient: fake,
      replacementAfterRetireBeforeCommit: {
        postRetireSeamCalls += 1
      }
    )
    let original = makeScheduleRequest("reservation-replacement-recovery")
    let replacement = makeScheduleRequest(
      "reservation-replacement-recovery",
      occurrenceId: "occurrence-replacement-recovery"
    )
    let platformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    clearMirror()
    defer { clearMirror() }

    let originalResult = await bridge.scheduleAlarm(original)
    XCTAssertEqual(originalResult.status, "success")

    let failedReplacement = await bridge.scheduleAlarm(replacement)
    XCTAssertEqual(failedReplacement.status, "failure")
    XCTAssertNil(failedReplacement.platformAlarmId)
    XCTAssertEqual(postRetireSeamCalls, 0)
    XCTAssertEqual(fake.cancelCalls, 2)
    XCTAssertTrue(mirrorContains(platformAlarmId))
    XCTAssertFalse(pendingMirrorContains(platformAlarmId))
    XCTAssertTrue(fake.nativeAlarmIds.contains(platformAlarmId.uppercased()))
    XCTAssertEqual(
      fake.scheduledRequests[platformAlarmId]?.occurrenceId,
      original.occurrenceId
    )

    let recoveredInventory = await inventoryValue(bridge)
    let recoveredRows = (recoveredInventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(recoveredRows?.first?["occurrenceId"] as? String, original.occurrenceId)
    XCTAssertTrue(mirrorContains(platformAlarmId))
    XCTAssertFalse(pendingMirrorContains(platformAlarmId))
    XCTAssertEqual(
      fake.scheduledRequests[platformAlarmId]?.occurrenceId,
      original.occurrenceId
    )

    let replacementRetry = await bridge.scheduleAlarm(replacement)
    XCTAssertEqual(replacementRetry.status, "success")
    XCTAssertNotEqual(replacementRetry.platformAlarmId, platformAlarmId)
    XCTAssertEqual(
      fake.scheduledRequests[replacementRetry.platformAlarmId!]?.occurrenceId,
      replacement.occurrenceId
    )
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeOldCancelThrowAfterMutationCommitsVerifiedCandidate() async {
    let fake = FakeAlarmKitNativeClient()
    fake.throwAfterMutationCancelAttempts = [1]
    var postRetireSeamCalls = 0
    let bridge = AlarmKitBridge(
      nativeClient: fake,
      replacementAfterRetireBeforeCommit: {
        postRetireSeamCalls += 1
      }
    )
    let original = makeScheduleRequest("reservation-cancel-ambiguous")
    let replacement = makeScheduleRequest(
      original.reservationId,
      occurrenceId: "occurrence-after-ambiguous-cancel"
    )
    let oldPlatformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    clearMirror()
    defer { clearMirror() }

    let originalResult = await bridge.scheduleAlarm(original)
    XCTAssertEqual(originalResult.status, "success")
    let result = await bridge.scheduleAlarm(replacement)

    XCTAssertEqual(result.status, "success")
    XCTAssertEqual(postRetireSeamCalls, 1)
    XCTAssertNotEqual(result.platformAlarmId, oldPlatformAlarmId)
    XCTAssertEqual(fake.nativeAlarmIds.count, 1)
    XCTAssertFalse(fake.nativeAlarmIds.contains(oldPlatformAlarmId.uppercased()))
    XCTAssertEqual(
      fake.scheduledRequests[result.platformAlarmId!]?.occurrenceId,
      replacement.occurrenceId
    )
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeLostRetirementReplyCommitsSoleCandidateAfterRestart() async {
    let fake = FakeAlarmKitNativeClient()
    let original = makeScheduleRequest("reservation-lost-committed-replacement")
    let replacement = makeScheduleRequest(
      original.reservationId,
      occurrenceId: "occurrence-lost-committed-replacement"
    )
    clearMirror()
    defer { clearMirror() }

    let firstBridge = AlarmKitBridge(
      nativeClient: fake,
      replacementAfterRetireBeforeCommit: {
        throw FakeAlarmKitNativeClient.FakeError.scheduleFailed
      }
    )
    let originalResult = await firstBridge.scheduleAlarm(original)
    XCTAssertEqual(originalResult.status, "success")
    let lostReply = await firstBridge.scheduleAlarm(replacement)
    XCTAssertEqual(lostReply.status, "failure")
    XCTAssertNil(lostReply.platformAlarmId)
    XCTAssertEqual(fake.nativeAlarmIds.count, 1)
    let oldPlatformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    let newPlatformAlarmId = fake.nativeAlarmIds
      .map { $0.lowercased() }
      .first { $0 != oldPlatformAlarmId }
    XCTAssertNotNil(newPlatformAlarmId)

    let restartedBridge = AlarmKitBridge(nativeClient: fake)
    // Launch captured stale old-only before transaction admission, while the
    // current authoritative state is candidate-only. Transactional refetch
    // must commit the candidate rather than retaining the absent old tuple.
    fake.inventoryIdsByCall[fake.inventoryCalls + 1] = [oldPlatformAlarmId]
    await restartedBridge.reconcileMirrorOnObservationStart()
    XCTAssertNil(UserDefaults.standard.data(forKey: replacementJournalKey))
    let inventory = await inventoryValue(restartedBridge)
    let rows = (inventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["reservationId"] as? String, original.reservationId)
    XCTAssertEqual(rows?.first?["occurrenceId"] as? String, replacement.occurrenceId)
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, newPlatformAlarmId)

    let scheduleAttemptsBeforeRetry = fake.scheduleAttempts
    let retry = await restartedBridge.scheduleAlarm(replacement)
    XCTAssertEqual(retry.status, "success")
    XCTAssertEqual(retry.platformAlarmId, newPlatformAlarmId)
    XCTAssertEqual(fake.scheduleAttempts, scheduleAttemptsBeforeRetry)
    XCTAssertEqual(fake.nativeAlarmIds.count, 1)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeClearsStaleCommittedNewJournalAfterResolvedAlarmDisappears() async throws {
    let fake = FakeAlarmKitNativeClient()
    let original = makeScheduleRequest("reservation-stale-committed-new-journal")
    let replacement = makeScheduleRequest(
      original.reservationId,
      occurrenceId: "occurrence-stale-committed-new-journal"
    )
    clearMirror()
    defer { clearMirror() }

    let interruptedBridge = AlarmKitBridge(
      nativeClient: fake,
      replacementAfterRetireBeforeCommit: {
        throw FakeAlarmKitNativeClient.FakeError.scheduleFailed
      }
    )
    let originalResult = await interruptedBridge.scheduleAlarm(original)
    let replacementResult = await interruptedBridge.scheduleAlarm(replacement)
    XCTAssertEqual(originalResult.status, "success")
    XCTAssertEqual(replacementResult.status, "failure")
    let stagingJournal = try XCTUnwrap(
      UserDefaults.standard.data(forKey: replacementJournalKey)
    )
    var legacyJournal = try XCTUnwrap(
      JSONSerialization.jsonObject(with: stagingJournal) as? [String: Any]
    )
    legacyJournal["phase"] = "newVerified"
    let staleJournal = try JSONSerialization.data(
      withJSONObject: legacyJournal,
      options: [.sortedKeys]
    )

    // Production reconciliation commits the verified candidate. Reinstalling
    // the captured journal models process loss after that mirror save and
    // before the adjacent journal clear.
    UserDefaults.standard.set(staleJournal, forKey: replacementJournalKey)
    let recoveredBridge = AlarmKitBridge(nativeClient: fake)
    let recoveredInventory = await inventoryValue(recoveredBridge)
    let recoveredRows = (recoveredInventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(recoveredRows?.first?["occurrenceId"] as? String, replacement.occurrenceId)
    XCTAssertNil(UserDefaults.standard.data(forKey: replacementJournalKey))
    UserDefaults.standard.set(staleJournal, forKey: replacementJournalKey)

    fake.nativeAlarmIds.removeAll()
    fake.scheduledRequests.removeAll()
    let restartedBridge = AlarmKitBridge(nativeClient: fake)
    let emptyInventory = await inventoryValue(restartedBridge)
    let emptyRows = (emptyInventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(emptyRows?.count, 0)
    XCTAssertNil(UserDefaults.standard.data(forKey: replacementJournalKey))
    guard let recoveredPlatformAlarmId = recoveredRows?.first?["platformAlarmId"] as? String else {
      XCTFail("Expected the recovered candidate platform identity.")
      return
    }
    XCTAssertFalse(mirrorContains(recoveredPlatformAlarmId))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeClearsStaleRetainedOldJournalAfterResolvedAlarmDisappears() async {
    let fake = FakeAlarmKitNativeClient()
    fake.inventoryErrorOnCall = 3
    let original = makeScheduleRequest("reservation-stale-retained-old-journal")
    let replacement = makeScheduleRequest(
      original.reservationId,
      occurrenceId: "occurrence-stale-retained-old-journal"
    )
    let oldPlatformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    clearMirror()
    defer { clearMirror() }

    let interruptedBridge = AlarmKitBridge(
      nativeClient: fake,
      replacementBeforeCommit: {
        throw FakeAlarmKitNativeClient.FakeError.scheduleFailed
      }
    )
    let originalResult = await interruptedBridge.scheduleAlarm(original)
    let replacementResult = await interruptedBridge.scheduleAlarm(replacement)
    XCTAssertEqual(originalResult.status, "success")
    XCTAssertEqual(replacementResult.status, "failure")
    let staleJournal = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: replacementJournalKey)
    )

    // Production staging recovery retires the candidate and retains the old
    // alarm. Reinstalling the journal recreates the same save/clear crash gap.
    fake.inventoryErrorOnCall = nil
    let recoveredBridge = AlarmKitBridge(nativeClient: fake)
    let recoveredInventory = await inventoryValue(recoveredBridge)
    let recoveredRows = (recoveredInventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(recoveredRows?.first?["occurrenceId"] as? String, original.occurrenceId)
    XCTAssertEqual(recoveredRows?.first?["platformAlarmId"] as? String, oldPlatformAlarmId)
    XCTAssertNil(UserDefaults.standard.data(forKey: replacementJournalKey))
    UserDefaults.standard.set(staleJournal, forKey: replacementJournalKey)

    fake.nativeAlarmIds.removeAll()
    fake.scheduledRequests.removeAll()
    let restartedBridge = AlarmKitBridge(nativeClient: fake)
    let emptyInventory = await inventoryValue(restartedBridge)
    let emptyRows = (emptyInventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(emptyRows?.count, 0)
    XCTAssertNil(UserDefaults.standard.data(forKey: replacementJournalKey))
    XCTAssertFalse(mirrorContains(oldPlatformAlarmId))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeUnresolvedDuplicateFailsClosedUntilOwnedCleanupSucceeds() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failedCancelAttempts = [1, 2, 3, 4]
    let bridge = AlarmKitBridge(nativeClient: fake)
    let original = makeScheduleRequest("reservation-owned-duplicate")
    let replacement = makeScheduleRequest(
      original.reservationId,
      occurrenceId: "occurrence-owned-duplicate"
    )
    let oldPlatformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    clearMirror()
    defer { clearMirror() }

    let originalResult = await bridge.scheduleAlarm(original)
    XCTAssertEqual(originalResult.status, "success")
    let unresolved = await bridge.scheduleAlarm(replacement)
    XCTAssertEqual(unresolved.status, "failure")
    XCTAssertNil(unresolved.platformAlarmId)
    XCTAssertEqual(fake.nativeAlarmIds.count, 2)

    let blockedCancel = await bridge.cancelAlarm([
      "occurrenceId": original.occurrenceId,
      "reservationId": original.reservationId,
      "platformAlarmId": oldPlatformAlarmId,
    ])
    XCTAssertEqual(blockedCancel["status"] as? String, "failure")
    XCTAssertEqual(fake.nativeAlarmIds.count, 2)

    fake.failedCancelAttempts = []
    let recoveredInventory = await inventoryValue(bridge)
    let rows = (recoveredInventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["occurrenceId"] as? String, original.occurrenceId)
    XCTAssertEqual(fake.nativeAlarmIds.count, 1)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeLegacyMirrorReplacementFailsClosedWithoutCancel() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let original = makeScheduleRequest("reservation-legacy-replacement")
    let replacement = makeScheduleRequest(
      "reservation-legacy-replacement",
      occurrenceId: "occurrence-legacy-replacement"
    )
    let platformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    let legacyData = mirrorData([
      platformAlarmId: [
        "reservationId": original.reservationId,
        "occurrenceId": original.occurrenceId,
        "wakePlanId": original.wakePlanId,
        "platformAlarmId": platformAlarmId,
      ]
    ])
    clearMirror()
    UserDefaults.standard.set(legacyData, forKey: mirrorKey)
    fake.nativeAlarmIds.insert(platformAlarmId.uppercased())
    defer { clearMirror() }

    let result = await bridge.scheduleAlarm(replacement)
    XCTAssertEqual(result.status, "failure")
    XCTAssertEqual(result.failureReason, "nativeError")
    XCTAssertNil(result.platformAlarmId)
    XCTAssertEqual(fake.cancelCalls, 0)
    XCTAssertEqual(fake.scheduleAttempts, 0)
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), legacyData)
    XCTAssertTrue(fake.nativeAlarmIds.contains(platformAlarmId.uppercased()))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeConcurrentDifferentSchedulesPreserveBothMirrorRows() async {
    let fake = FakeAlarmKitNativeClient()
    fake.gatedScheduleAttempts = [1]
    let bridge = AlarmKitBridge(nativeClient: fake)
    let requestA = makeScheduleRequest("reservation-concurrent-a", occurrenceId: "occurrence-a")
    let requestB = makeScheduleRequest("reservation-concurrent-b", occurrenceId: "occurrence-b")
    clearMirror()
    defer { clearMirror() }

    let first = Task { @MainActor in await bridge.scheduleAlarm(requestA) }
    while !fake.gatedScheduleStartedAttempts.contains(1) { await Task.yield() }
    let second = Task { @MainActor in await bridge.scheduleAlarm(requestB) }
    await Task.yield()
    fake.allowGatedSchedules = true

    let firstResult = await first.value
    let secondResult = await second.value
    XCTAssertEqual(firstResult.status, "success")
    XCTAssertEqual(secondResult.status, "success")
    let idA = calarmPlatformAlarmId(for: requestA.reservationId)
    let idB = calarmPlatformAlarmId(for: requestB.reservationId)
    XCTAssertEqual(fake.nativeAlarmIds, Set([idA.uppercased(), idB.uppercased()]))
    XCTAssertTrue(mirrorContains(idA))
    XCTAssertTrue(mirrorContains(idB))
    let inventory = await inventoryValue(bridge)
    let rows = (inventory as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 2)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeScheduleAndCancelDifferentIdentitiesPreserveOrdering() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let requestA = makeScheduleRequest("reservation-overlap-a", occurrenceId: "occurrence-a")
    let requestB = makeScheduleRequest("reservation-overlap-b", occurrenceId: "occurrence-b")
    clearMirror()
    defer { clearMirror() }
    let initialResult = await bridge.scheduleAlarm(requestB)
    XCTAssertEqual(initialResult.status, "success")

    fake.gatedScheduleAttempts = [2]
    let schedule = Task { @MainActor in await bridge.scheduleAlarm(requestA) }
    while !fake.gatedScheduleStartedAttempts.contains(2) { await Task.yield() }
    let cancel = Task { @MainActor in
      await bridge.cancelAlarm([
        "occurrenceId": requestB.occurrenceId,
        "reservationId": requestB.reservationId,
        "platformAlarmId": calarmPlatformAlarmId(for: requestB.reservationId).uppercased(),
      ])
    }
    await Task.yield()
    fake.allowGatedSchedules = true

    let cancelResult = await cancel.value
    let scheduleResult = await schedule.value
    XCTAssertEqual(scheduleResult.status, "success")
    XCTAssertEqual(cancelResult["status"] as? String, "success")
    let idA = calarmPlatformAlarmId(for: requestA.reservationId)
    let idB = calarmPlatformAlarmId(for: requestB.reservationId)
    XCTAssertEqual(fake.nativeAlarmIds, Set([idA.uppercased()]))
    XCTAssertTrue(mirrorContains(idA))
    XCTAssertFalse(mirrorContains(idB))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeObserverRacingSchedulePreservesPendingAndUnrelatedRows() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-observer-race")
    let unrelatedRequest = makeScheduleRequest(
      "reservation-observer-unrelated",
      occurrenceId: "occurrence-observer-unrelated"
    )
    clearMirror()
    defer { clearMirror() }
    let unrelatedResult = await bridge.scheduleAlarm(unrelatedRequest)
    XCTAssertEqual(unrelatedResult.status, "success")
    fake.gatedScheduleAttempts = [2]

    let schedule = Task { @MainActor in await bridge.scheduleAlarm(request) }
    while !fake.gatedScheduleStartedAttempts.contains(2) { await Task.yield() }
    let id = calarmPlatformAlarmId(for: request.reservationId)
    let unrelatedId = calarmPlatformAlarmId(for: unrelatedRequest.reservationId)
    let observer = Task { @MainActor in
      await bridge.reconcileMirror(
        withNativeAlarmIds: [id.uppercased(), unrelatedId.uppercased()]
      )
    }
    await Task.yield()
    fake.allowGatedSchedules = true

    let scheduleResult = await schedule.value
    XCTAssertEqual(scheduleResult.status, "success")
    await observer.value
    XCTAssertTrue(mirrorContains(id))
    XCTAssertTrue(mirrorContains(unrelatedId))
    XCTAssertEqual(fake.nativeAlarmIds, Set([id.uppercased(), unrelatedId.uppercased()]))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeSharedMirrorCoordinatorSerializesCrossInstanceSchedules() async {
    let fakeA = FakeAlarmKitNativeClient()
    let fakeB = FakeAlarmKitNativeClient()
    fakeA.gatedScheduleAttempts = [1]
    let bridgeA = AlarmKitBridge(nativeClient: fakeA)
    let bridgeB = AlarmKitBridge(nativeClient: fakeB)
    let requestA = makeScheduleRequest("reservation-cross-instance-a", occurrenceId: "occurrence-cross-a")
    let requestB = makeScheduleRequest("reservation-cross-instance-b", occurrenceId: "occurrence-cross-b")
    clearMirror()
    defer { clearMirror() }

    let scheduleA = Task { @MainActor in await bridgeA.scheduleAlarm(requestA) }
    while !fakeA.gatedScheduleStartedAttempts.contains(1) { await Task.yield() }
    let scheduleB = Task { @MainActor in await bridgeB.scheduleAlarm(requestB) }
    await Task.yield()
    fakeA.allowGatedSchedules = true

    let scheduleAResult = await scheduleA.value
    let scheduleBResult = await scheduleB.value
    XCTAssertEqual(scheduleAResult.status, "success")
    XCTAssertEqual(scheduleBResult.status, "success")
    XCTAssertTrue(mirrorContains(calarmPlatformAlarmId(for: requestA.reservationId)))
    XCTAssertTrue(mirrorContains(calarmPlatformAlarmId(for: requestB.reservationId)))
    XCTAssertEqual(fakeA.maxActiveSchedules, 1)
    XCTAssertEqual(fakeB.maxActiveSchedules, 1)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeSharedMirrorCoordinatorSerializesCrossInstanceScheduleCancel() async {
    let fakeA = FakeAlarmKitNativeClient()
    let fakeB = FakeAlarmKitNativeClient()
    let bridgeA = AlarmKitBridge(nativeClient: fakeA)
    let bridgeB = AlarmKitBridge(nativeClient: fakeB)
    let requestA = makeScheduleRequest("reservation-cross-cancel-a", occurrenceId: "occurrence-cross-cancel-a")
    let requestB = makeScheduleRequest("reservation-cross-cancel-b", occurrenceId: "occurrence-cross-cancel-b")
    clearMirror()
    defer { clearMirror() }
    let initialResult = await bridgeB.scheduleAlarm(requestB)
    XCTAssertEqual(initialResult.status, "success")

    fakeA.gatedScheduleAttempts = [1]
    let schedule = Task { @MainActor in await bridgeA.scheduleAlarm(requestA) }
    while !fakeA.gatedScheduleStartedAttempts.contains(1) { await Task.yield() }
    let cancel = Task { @MainActor in
      await bridgeB.cancelAlarm([
        "occurrenceId": requestB.occurrenceId,
        "reservationId": requestB.reservationId,
        "platformAlarmId": calarmPlatformAlarmId(for: requestB.reservationId).uppercased(),
      ])
    }
    await Task.yield()
    fakeA.allowGatedSchedules = true

    let scheduleResult = await schedule.value
    let cancelResult = await cancel.value
    XCTAssertEqual(scheduleResult.status, "success")
    XCTAssertEqual(cancelResult["status"] as? String, "success")
    XCTAssertTrue(mirrorContains(calarmPlatformAlarmId(for: requestA.reservationId)))
    XCTAssertFalse(mirrorContains(calarmPlatformAlarmId(for: requestB.reservationId)))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeSharedMirrorCoordinatorSerializesCrossInstanceObserverSchedule() async {
    let fakeA = FakeAlarmKitNativeClient()
    let fakeB = FakeAlarmKitNativeClient()
    fakeA.gatedScheduleAttempts = [1]
    let bridgeA = AlarmKitBridge(nativeClient: fakeA)
    let bridgeB = AlarmKitBridge(nativeClient: fakeB)
    let request = makeScheduleRequest("reservation-cross-observer", occurrenceId: "occurrence-cross-observer")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let schedule = Task { @MainActor in await bridgeA.scheduleAlarm(request) }
    while !fakeA.gatedScheduleStartedAttempts.contains(1) { await Task.yield() }
    let observer = Task { @MainActor in
      await bridgeB.reconcileMirror(withNativeAlarmIds: [id.uppercased()])
    }
    await Task.yield()
    fakeA.allowGatedSchedules = true

    let scheduleResult = await schedule.value
    XCTAssertEqual(scheduleResult.status, "success")
    await observer.value
    XCTAssertTrue(mirrorContains(id))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeSharedMirrorCoordinatorSerializesCrossInstanceInventorySchedule() async {
    let fakeA = FakeAlarmKitNativeClient()
    let fakeB = FakeAlarmKitNativeClient()
    fakeA.gatedScheduleAttempts = [1]
    let bridgeA = AlarmKitBridge(nativeClient: fakeA)
    let bridgeB = AlarmKitBridge(nativeClient: fakeB)
    let request = makeScheduleRequest("reservation-cross-inventory", occurrenceId: "occurrence-cross-inventory")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    fakeB.inventoryIdsOverride = [id.uppercased()]
    clearMirror()
    defer { clearMirror() }

    let schedule = Task { @MainActor in await bridgeA.scheduleAlarm(request) }
    while !fakeA.gatedScheduleStartedAttempts.contains(1) { await Task.yield() }
    let inventory = Task { @MainActor in await inventoryValue(bridgeB) }
    await Task.yield()
    fakeA.allowGatedSchedules = true

    let scheduleResult = await schedule.value
    XCTAssertEqual(scheduleResult.status, "success")
    let inventoryValueResult = await inventory.value
    XCTAssertEqual(
      ((inventoryValueResult as? [String: Any?])?["reservations"] as? [[String: Any?]])?.count,
      1
    )
    XCTAssertTrue(mirrorContains(id))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeObserverPruneMakesSubsequentTupleCancelFailClosed() async {
    let fakeA = FakeAlarmKitNativeClient()
    let fakeB = FakeAlarmKitNativeClient()
    let bridgeA = AlarmKitBridge(nativeClient: fakeA)
    let bridgeB = AlarmKitBridge(nativeClient: fakeB)
    let request = makeScheduleRequest("reservation-cross-observer-cancel", occurrenceId: "occurrence-cross-observer-cancel")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }
    let initialResult = await bridgeB.scheduleAlarm(request)
    XCTAssertEqual(initialResult.status, "success")

    await bridgeA.reconcileMirror(withNativeAlarmIds: [])
    let cancelResult = await bridgeB.cancelAlarm([
      "occurrenceId": request.occurrenceId,
      "reservationId": request.reservationId,
      "platformAlarmId": id.uppercased(),
    ])
    XCTAssertEqual(cancelResult["status"] as? String, "failure")
    XCTAssertEqual(cancelResult["failureReason"] as? String, "invalidRequest")
    XCTAssertTrue(fakeB.nativeAlarmIds.contains(id.uppercased()))
    XCTAssertFalse(mirrorContains(id))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeSharedMirrorCoordinatorPreservesUnrelatedSuccessAfterCrossInstanceCleanup() async {
    let fakeA = FakeAlarmKitNativeClient()
    let fakeB = FakeAlarmKitNativeClient()
    fakeA.gatedScheduleAttempts = [1]
    fakeA.failFirstSchedule = true
    fakeA.inventoryIdsByCall = [1: [], 2: []]
    let bridgeA = AlarmKitBridge(nativeClient: fakeA)
    let bridgeB = AlarmKitBridge(nativeClient: fakeB)
    let failedRequest = makeScheduleRequest("reservation-cross-failure", occurrenceId: "occurrence-cross-failure")
    let successRequest = makeScheduleRequest("reservation-cross-success", occurrenceId: "occurrence-cross-success")
    clearMirror()
    defer { clearMirror() }

    let failed = Task { @MainActor in await bridgeA.scheduleAlarm(failedRequest) }
    while !fakeA.gatedScheduleStartedAttempts.contains(1) { await Task.yield() }
    let succeeded = Task { @MainActor in await bridgeB.scheduleAlarm(successRequest) }
    await Task.yield()
    fakeA.allowGatedSchedules = true

    let failedResult = await failed.value
    let succeededResult = await succeeded.value
    XCTAssertEqual(failedResult.failureReason, "nativeError")
    XCTAssertEqual(succeededResult.status, "success")
    XCTAssertFalse(mirrorContains(calarmPlatformAlarmId(for: failedRequest.reservationId)))
    XCTAssertTrue(mirrorContains(calarmPlatformAlarmId(for: successRequest.reservationId)))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeUncertainNewScheduleFailureKeepsCommittedBytesAndAllowsRetry() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failFirstSchedule = true
    fake.inventoryErrorOnCall = 2
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-uncertain-new")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    let unrelatedId = calarmPlatformAlarmId(for: "reservation-uncertain-unrelated")
    let originalData = mirrorData([
      unrelatedId: [
        "reservationId": "reservation-uncertain-unrelated",
        "occurrenceId": "occurrence-uncertain-unrelated",
        "wakePlanId": "wake-plan-uncertain-unrelated",
        "platformAlarmId": unrelatedId,
      ]
    ])
    clearMirror()
    UserDefaults.standard.set(originalData, forKey: mirrorKey)
    defer { clearMirror() }

    let failed = await bridge.scheduleAlarm(request)
    XCTAssertEqual(failed.failureReason, "nativeError")
    XCTAssertNil(failed.platformAlarmId)
    XCTAssertEqual(committedMirrorObject()?.count, 1)
    XCTAssertEqual(mirrorEnvelopeVersion(), 1)
    XCTAssertNotNil(committedMirrorObject()?[unrelatedId])
    XCTAssertTrue(pendingMirrorContains(id))

    fake.inventoryErrorOnCall = nil
    let retried = await bridge.scheduleAlarm(
      makeScheduleRequest("reservation-uncertain-new", occurrenceId: "occurrence-retry")
    )
    XCTAssertEqual(retried.status, "success")
    XCTAssertTrue(mirrorContains(id))
    XCTAssertTrue(mirrorContains(unrelatedId))
    XCTAssertFalse(pendingMirrorContains(id))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRecoversInterruptedPendingRemovalWhenNativeAlarmIsLive() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failFirstSchedule = true
    fake.inventoryErrorOnCall = 2
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-interrupted-pending")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let failed = await bridge.scheduleAlarm(request)
    XCTAssertEqual(failed.failureReason, "nativeError")
    XCTAssertTrue(pendingMirrorContains(id))
    let envelopeBeforeCrash = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: envelopeKey)
    )
    let transactionBeforeCrash = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: transactionKey)
    )

    // Emulate the crash window after the new committed projection/pending
    // removal but before envelope publication: old envelope and marker remain.
    fake.nativeAlarmIds.insert(id.uppercased())
    UserDefaults.standard.removeObject(forKey: pendingMirrorKey)
    let restarted = AlarmKitBridge(nativeClient: fake)
    let mirrorBeforeObserver = UserDefaults.standard.data(forKey: mirrorKey)
    let envelopeBeforeObserver = UserDefaults.standard.data(forKey: envelopeKey)
    await restarted.reconcileMirror(withNativeAlarmIds: [id.uppercased()])
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), mirrorBeforeObserver)
    XCTAssertEqual(UserDefaults.standard.data(forKey: envelopeKey), envelopeBeforeObserver)
    let value = await inventoryValue(restarted)
    let rows = (value as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, id)
    XCTAssertTrue(mirrorContains(id))
    XCTAssertFalse(pendingMirrorContains(id))
    XCTAssertNil(UserDefaults.standard.data(forKey: pendingMirrorKey))
    XCTAssertNotEqual(UserDefaults.standard.data(forKey: envelopeKey), envelopeBeforeCrash)
    XCTAssertNotEqual(UserDefaults.standard.data(forKey: transactionKey), transactionBeforeCrash)

    let cancelled = await restarted.cancelAlarm([
      "occurrenceId": request.occurrenceId,
      "reservationId": request.reservationId,
      "platformAlarmId": id.uppercased(),
    ])
    XCTAssertEqual(cancelled["status"] as? String, "success")
    let afterCancel = await inventoryValue(restarted)
    let afterCancelRows = (afterCancel as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(afterCancelRows?.count, 0)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeKeepsAmbiguousMixedStateCorruptWithoutMutation() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-ambiguous-recovery")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let committedData = mirrorData([
      id: [
        "reservationId": request.reservationId,
        "occurrenceId": request.occurrenceId,
        "wakePlanId": request.wakePlanId,
        "platformAlarmId": id,
      ],
    ])
    UserDefaults.standard.set(committedData, forKey: mirrorKey)
    UserDefaults.standard.set(Data("not-a-mirror".utf8), forKey: pendingMirrorKey)
    fake.nativeAlarmIds.insert(id.uppercased())
    let committedBefore = UserDefaults.standard.data(forKey: mirrorKey)
    let pendingBefore = UserDefaults.standard.data(forKey: pendingMirrorKey)

    let value = await inventoryValue(bridge)
    XCTAssertEqual((value as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), committedBefore)
    XCTAssertEqual(UserDefaults.standard.data(forKey: pendingMirrorKey), pendingBefore)
    XCTAssertEqual(fake.inventoryCalls, 1)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRecoversMalformedMarkerFromNativeIdentityEvidence() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-malformed-marker")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    UserDefaults.standard.set(
      mirrorData([
        id: [
          "reservationId": request.reservationId,
          "occurrenceId": request.occurrenceId,
          "wakePlanId": request.wakePlanId,
          "platformAlarmId": id,
        ],
      ]),
      forKey: mirrorKey
    )
    UserDefaults.standard.set(
      Data("unsupported-marker".utf8),
      forKey: transactionKey
    )
    fake.nativeAlarmIds.insert(id.uppercased())

    let value = await inventoryValue(bridge)
    let rows = (value as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, id)
    XCTAssertNotEqual(
      UserDefaults.standard.data(forKey: transactionKey),
      Data("unsupported-marker".utf8)
    )
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRecoversInterruptedStateAndPrunesAbsentPendingIdentity() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failFirstSchedule = true
    fake.inventoryErrorOnCall = 2
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-interrupted-absent")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let failedResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(failedResult.failureReason, "nativeError")
    XCTAssertTrue(pendingMirrorContains(id))
    UserDefaults.standard.removeObject(forKey: pendingMirrorKey)

    let value = await inventoryValue(bridge)
    let rows = (value as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 0)
    XCTAssertFalse(mirrorContains(id))
    XCTAssertFalse(pendingMirrorContains(id))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeMalformedRecoveryAlternativesRemainCorruptAndMutationFree() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-quarantine-alternatives")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let scheduleResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(scheduleResult.status, "success")
    let committedBefore = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: mirrorKey)
    )
    let malformedEnvelope = Data("malformed current envelope".utf8)
    let malformedPending = Data("malformed pending alternative".utf8)
    UserDefaults.standard.set(malformedEnvelope, forKey: envelopeKey)
    UserDefaults.standard.set(malformedPending, forKey: pendingMirrorKey)
    let value = await inventoryValue(bridge)
    XCTAssertEqual((value as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), committedBefore)
    XCTAssertEqual(UserDefaults.standard.data(forKey: envelopeKey), malformedEnvelope)
    XCTAssertEqual(UserDefaults.standard.data(forKey: pendingMirrorKey), malformedPending)
    XCTAssertEqual(fake.cancelCalls, 0)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeMalformedLegacyCommittedAndPendingRemainCorrupt() async {
    let request = makeScheduleRequest("reservation-malformed-legacy")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    let record: [String: String] = [
      "reservationId": request.reservationId,
      "occurrenceId": request.occurrenceId,
      "wakePlanId": request.wakePlanId,
      "platformAlarmId": id,
    ]
    defer { clearMirror() }

    clearMirror()
    let malformedLegacy = Data("malformed legacy committed".utf8)
    UserDefaults.standard.set(malformedLegacy, forKey: mirrorKey)
    let legacyBridge = AlarmKitBridge(nativeClient: FakeAlarmKitNativeClient())
    let legacyResult = await inventoryValue(legacyBridge)
    XCTAssertEqual((legacyResult as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), malformedLegacy)

    clearMirror()
    let pendingProjection = mirrorData([id: record])
    let malformedPending = Data("malformed pending projection".utf8)
    UserDefaults.standard.set(pendingProjection, forKey: mirrorKey)
    UserDefaults.standard.set(malformedPending, forKey: pendingMirrorKey)
    let pendingBridge = AlarmKitBridge(nativeClient: FakeAlarmKitNativeClient())
    let pendingResult = await inventoryValue(pendingBridge)
    XCTAssertEqual((pendingResult as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), pendingProjection)
    XCTAssertEqual(UserDefaults.standard.data(forKey: pendingMirrorKey), malformedPending)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeMalformedCurrentAndPriorEnvelopesRemainCorrupt() async {
    let request = makeScheduleRequest("reservation-malformed-envelope")
    defer { clearMirror() }

    clearMirror()
    let currentFake = FakeAlarmKitNativeClient()
    let currentBridge = AlarmKitBridge(nativeClient: currentFake)
    let currentResult = await currentBridge.scheduleAlarm(request)
    XCTAssertEqual(currentResult.status, "success")
    let committedBefore = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: mirrorKey)
    )
    let validEnvelope = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: envelopeKey)
    )
    var currentEnvelopeObject = try! XCTUnwrap(
      JSONSerialization.jsonObject(with: validEnvelope) as? [String: Any]
    )
    currentEnvelopeObject["generation"] = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    let malformedCurrent = try! JSONSerialization.data(
      withJSONObject: currentEnvelopeObject,
      options: [.sortedKeys]
    )
    UserDefaults.standard.set(malformedCurrent, forKey: envelopeKey)
    let currentInventoryResult = await inventoryValue(currentBridge)
    XCTAssertEqual((currentInventoryResult as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), committedBefore)
    XCTAssertEqual(UserDefaults.standard.data(forKey: envelopeKey), malformedCurrent)

    clearMirror()
    let priorFake = FakeAlarmKitNativeClient()
    let priorWriter = AlarmKitBridge(nativeClient: priorFake)
    let priorResult = await priorWriter.scheduleAlarm(request)
    XCTAssertEqual(priorResult.status, "success")
    let validCurrentEnvelope = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: envelopeKey)
    )
    let malformedPrior = Data(
      "{\"version\":2,\"committed\":{},\"pending\":{}}".utf8
    )
    UserDefaults.standard.set(validCurrentEnvelope, forKey: envelopeKey)
    UserDefaults.standard.set(malformedPrior, forKey: mirrorKey)
    let priorBridge = AlarmKitBridge(nativeClient: priorFake)
    let priorInventoryResult = await inventoryValue(priorBridge)
    XCTAssertEqual((priorInventoryResult as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), malformedPrior)
    XCTAssertEqual(UserDefaults.standard.data(forKey: envelopeKey), validCurrentEnvelope)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRejectsMalformedCurrentEnvelopeWithoutMutation() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-lowercase-generation")
    clearMirror()
    defer { clearMirror() }

    let scheduleResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(scheduleResult.status, "success")
    let envelope = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: envelopeKey)
    )
    var object = try! XCTUnwrap(
      JSONSerialization.jsonObject(with: envelope) as? [String: Any]
    )
    object["generation"] = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    let malformedCurrent = try! JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys]
    )
    UserDefaults.standard.set(malformedCurrent, forKey: envelopeKey)

    let value = await inventoryValue(bridge)
    XCTAssertEqual((value as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: envelopeKey), malformedCurrent)

    var unsupported = try! XCTUnwrap(
      JSONSerialization.jsonObject(
        with: try! XCTUnwrap(UserDefaults.standard.data(forKey: envelopeKey))
      ) as? [String: Any]
    )
    unsupported["version"] = 99
    let unsupportedData = try! JSONSerialization.data(
      withJSONObject: unsupported,
      options: [.sortedKeys]
    )
    UserDefaults.standard.set(unsupportedData, forKey: envelopeKey)
    let unsupportedValue = await inventoryValue(bridge)
    XCTAssertEqual((unsupportedValue as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: envelopeKey), unsupportedData)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRejectsConflictingValidRecoveryCandidatesWithoutMutation() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-conflicting-recovery")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let scheduleResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(scheduleResult.status, "success")
    let envelopeBefore = UserDefaults.standard.data(forKey: envelopeKey)
    let conflictingCommitted = mirrorData([
      id: [
        "reservationId": request.reservationId,
        "occurrenceId": "conflicting-occurrence",
        "wakePlanId": request.wakePlanId,
        "platformAlarmId": id,
      ],
    ])
    UserDefaults.standard.set(conflictingCommitted, forKey: mirrorKey)
    let value = await inventoryValue(bridge)
    XCTAssertEqual((value as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), conflictingCommitted)
    XCTAssertEqual(UserDefaults.standard.data(forKey: envelopeKey), envelopeBefore)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeUncertainCleanupKeepsPendingUntilNativePresenceIsKnown() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failFirstSchedule = true
    fake.inventoryIdsByCall = [1: [], 2: [calarmPlatformAlarmId(for: "reservation-uncertain-live").uppercased()]]
    fake.insertBeforeFailFirstSchedule = true
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-uncertain-live")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let failed = await bridge.scheduleAlarm(request)
    XCTAssertEqual(failed.failureReason, "nativeError")
    XCTAssertEqual(failed.platformAlarmId, id)
    XCTAssertTrue(pendingMirrorContains(id))
    XCTAssertFalse(mirrorContains(id))

    let inventory = await inventoryValue(bridge)
    let rows = (inventory as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, id)
    XCTAssertTrue(mirrorContains(id))
    XCTAssertFalse(pendingMirrorContains(id))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeChangedRetryPromotesUncertainPendingBeforeReplacementJournal() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failFirstSchedule = true
    fake.insertBeforeFailFirstSchedule = true
    let original = makeScheduleRequest("reservation-pending-replacement")
    let replacement = makeScheduleRequest(
      "reservation-pending-replacement",
      occurrenceId: "occurrence-pending-replacement"
    )
    let oldPlatformAlarmId = calarmPlatformAlarmId(for: original.reservationId)
    let interruptedBridge = AlarmKitBridge(
      nativeClient: fake,
      replacementAfterRetireBeforeCommit: {
        throw FakeAlarmKitNativeClient.FakeError.scheduleFailed
      }
    )
    clearMirror()
    defer { clearMirror() }

    let initial = await interruptedBridge.scheduleAlarm(original)
    XCTAssertEqual(initial.status, "failure")
    XCTAssertEqual(initial.platformAlarmId, oldPlatformAlarmId)
    XCTAssertTrue(pendingMirrorContains(oldPlatformAlarmId))
    XCTAssertFalse(mirrorContains(oldPlatformAlarmId))

    // Retry a changed tuple directly, without an intervening inventory read.
    // The reply is lost only after authoritative inventory proves that the
    // old UUID retired and the candidate is the sole native alarm.
    let interruptedReplacement = await interruptedBridge.scheduleAlarm(replacement)
    XCTAssertEqual(interruptedReplacement.status, "failure")
    XCTAssertNil(interruptedReplacement.platformAlarmId)
    XCTAssertEqual(fake.scheduleAttempts, 2)
    XCTAssertEqual(fake.nativeAlarmIds.count, 1)
    XCTAssertTrue(mirrorContains(oldPlatformAlarmId))
    XCTAssertFalse(pendingMirrorContains(oldPlatformAlarmId))
    XCTAssertNotNil(UserDefaults.standard.data(forKey: replacementJournalKey))

    let restartedBridge = AlarmKitBridge(nativeClient: fake)
    let inventory = await inventoryValue(restartedBridge)
    let rows = (inventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["reservationId"] as? String, replacement.reservationId)
    XCTAssertEqual(rows?.first?["occurrenceId"] as? String, replacement.occurrenceId)
    let activePlatformAlarmId = rows?.first?["platformAlarmId"] as? String
    XCTAssertNotNil(activePlatformAlarmId)
    XCTAssertNotEqual(activePlatformAlarmId, oldPlatformAlarmId)
    XCTAssertEqual(fake.nativeAlarmIds.count, 1)
    XCTAssertFalse(fake.nativeAlarmIds.contains(oldPlatformAlarmId.uppercased()))
    XCTAssertNil(UserDefaults.standard.data(forKey: replacementJournalKey))

    let retry = await restartedBridge.scheduleAlarm(replacement)
    XCTAssertEqual(retry.status, "success")
    XCTAssertEqual(retry.platformAlarmId, activePlatformAlarmId)
    XCTAssertEqual(fake.scheduleAttempts, 2)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeMalformedOrDuplicateCleanupKeepsCommittedBytesAndPendingRecovery() async {
    let request = makeScheduleRequest("reservation-invalid-cleanup")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    let unrelatedId = calarmPlatformAlarmId(for: "reservation-invalid-cleanup-unrelated")
    let originalData = mirrorData([
      unrelatedId: [
        "reservationId": "reservation-invalid-cleanup-unrelated",
        "occurrenceId": "occurrence-invalid-cleanup-unrelated",
        "wakePlanId": "wake-plan-invalid-cleanup-unrelated",
        "platformAlarmId": unrelatedId,
      ]
    ])
    let cleanupSnapshots = [
      ["not-a-uuid"],
      [id, id.uppercased()],
      [calarmPlatformAlarmId(for: "unrelated"), calarmPlatformAlarmId(for: "unrelated")],
    ]

    for cleanupSnapshot in cleanupSnapshots {
      let fake = FakeAlarmKitNativeClient()
      fake.failFirstSchedule = true
      fake.inventoryIdsByCall = [1: [], 2: cleanupSnapshot]
      let bridge = AlarmKitBridge(nativeClient: fake)
      clearMirror()
      UserDefaults.standard.set(originalData, forKey: mirrorKey)
      let failed = await bridge.scheduleAlarm(request)
      XCTAssertEqual(failed.failureReason, "nativeError")
      XCTAssertEqual(committedMirrorObject()?.count, 1)
      XCTAssertEqual(mirrorEnvelopeVersion(), 1)
      XCTAssertTrue(pendingMirrorContains(id))

      fake.inventoryIdsByCall.removeValue(forKey: 2)
      let recovered = await inventoryValue(bridge)
      let rows = (recovered as? [String: Any?])?["reservations"] as? [[String: Any?]]
      XCTAssertEqual(rows?.count, 0)
      XCTAssertFalse(pendingMirrorContains(id))
      clearMirror()
    }
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeCancelWaitsForOverlappingScheduleAndRetryIsRecoverable() async {
    let fake = FakeAlarmKitNativeClient()
    fake.gateFirstSchedule = true
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest()
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let schedule = Task { @MainActor in await bridge.scheduleAlarm(request) }
    while !fake.firstScheduleStarted { await Task.yield() }
    let cancel = Task { @MainActor in
      await bridge.cancelAlarm([
        "occurrenceId": request.occurrenceId,
        "reservationId": request.reservationId,
        "platformAlarmId": platformAlarmId.uppercased(),
      ])
    }
    await Task.yield()
    fake.allowFirstScheduleToFinish = true

    let scheduleResult = await schedule.value
    let cancelResult = await cancel.value
    XCTAssertEqual(scheduleResult.status, "success")
    XCTAssertEqual(cancelResult["status"] as? String, "success")
    XCTAssertEqual(fake.cancelCalls, 1)
    XCTAssertTrue(fake.nativeAlarmIds.isEmpty)
    XCTAssertFalse(mirrorContains(platformAlarmId))

    let retryResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(retryResult.status, "success")
    XCTAssertEqual(fake.nativeAlarmIds, Set([platformAlarmId.uppercased()]))
    XCTAssertTrue(mirrorContains(platformAlarmId))
    let inventory = await inventoryValue(bridge)
    let response = inventory as? [String: Any?]
    let rows = response?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, platformAlarmId)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeLegacyCancelUsesStoredReservationWhenPayloadOmitsIt() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest()
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let scheduleResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(scheduleResult.status, "success")
    let result = await bridge.cancelAlarm([
      "occurrenceId": request.occurrenceId,
      "platformAlarmId": platformAlarmId.uppercased(),
    ])
    XCTAssertEqual(result["status"] as? String, "success")
    XCTAssertEqual(result["reservationId"] as? String, request.occurrenceId)
    XCTAssertEqual(result["platformAlarmId"] as? String, platformAlarmId.uppercased())
    XCTAssertTrue(fake.nativeAlarmIds.isEmpty)
    XCTAssertFalse(mirrorContains(platformAlarmId))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeScheduleReservationPresenceSemanticsAndStableCollision() async {
    let invalidValues: [Any] = [NSNull(), "", " \n\t ", 42]
    for invalidValue in invalidValues {
      let fake = FakeAlarmKitNativeClient()
      let bridge = AlarmKitBridge(nativeClient: fake)
      clearMirror()
      var payload = makeSchedulePayload()
      payload["reservationId"] = invalidValue

      let result = await bridge.scheduleOccurrence(payload)
      XCTAssertEqual(result["status"] as? String, "failure")
      XCTAssertEqual(result["failureReason"] as? String, "invalidRequest")
      XCTAssertEqual(fake.scheduleAttempts, 0)
      XCTAssertNil(UserDefaults.standard.data(forKey: mirrorKey))
    }

    let absentFake = FakeAlarmKitNativeClient()
    let absentBridge = AlarmKitBridge(nativeClient: absentFake)
    clearMirror()
    let absentResult = await absentBridge.scheduleOccurrence(makeSchedulePayload())
    let occurrenceId = "occurrence-1"
    XCTAssertEqual(absentResult["status"] as? String, "success")
    XCTAssertEqual(absentResult["reservationId"] as? String, occurrenceId)
    XCTAssertTrue(mirrorContains(calarmPlatformAlarmId(for: occurrenceId)))

    let stableFake = FakeAlarmKitNativeClient()
    let stableBridge = AlarmKitBridge(nativeClient: stableFake)
    clearMirror()
    var stablePayload = makeSchedulePayload(occurrenceId: "occurrence-stable")
    stablePayload["reservationId"] = "stable-reservation"
    let stableResult = await stableBridge.scheduleOccurrence(stablePayload)
    let stablePlatformAlarmId = calarmPlatformAlarmId(for: "stable-reservation")
    XCTAssertEqual(stableResult["status"] as? String, "success")
    XCTAssertEqual(stableResult["reservationId"] as? String, "stable-reservation")
    XCTAssertTrue(mirrorContains(stablePlatformAlarmId))
    XCTAssertFalse(mirrorContains(calarmPlatformAlarmId(for: "occurrence-stable")))

    var collisionPayload = makeSchedulePayload(occurrenceId: "occurrence-collision")
    collisionPayload["reservationId"] = "stable-reservation"
    let collisionResult = await stableBridge.scheduleOccurrence(collisionPayload)
    XCTAssertEqual(collisionResult["status"] as? String, "success")
    XCTAssertEqual(stableFake.scheduleAttempts, 2)
    XCTAssertEqual(stableFake.cancelCalls, 1)
    XCTAssertGreaterThanOrEqual(stableFake.inventoryCalls, 2)
    let replacementPlatformAlarmId = collisionResult["platformAlarmId"] as? String
    XCTAssertNotNil(replacementPlatformAlarmId)
    XCTAssertNotEqual(replacementPlatformAlarmId, stablePlatformAlarmId)
    XCTAssertFalse(mirrorContains(stablePlatformAlarmId))
    XCTAssertTrue(mirrorContains(replacementPlatformAlarmId!))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRejectsConflictingPendingOwnershipWithoutMutation() async {
    let request = makeScheduleRequest(
      "reservation-pending-owner",
      occurrenceId: "requested-occurrence"
    )
    let id = calarmPlatformAlarmId(for: request.reservationId)
    let conflictingRecord: [String: String] = [
      "reservationId": request.reservationId,
      "occurrenceId": "recovery-owned-occurrence",
      "wakePlanId": "recovery-owned-plan",
      "platformAlarmId": id,
    ]
    let fake = FakeAlarmKitNativeClient()
    fake.inventoryIdsOverride = []
    let bridge = AlarmKitBridge(nativeClient: fake)
    clearMirror()
    let pendingData = mirrorData([id: conflictingRecord])
    UserDefaults.standard.set(pendingData, forKey: pendingMirrorKey)
    defer { clearMirror() }

    let result = await bridge.scheduleAlarm(request)
    XCTAssertEqual(result.failureReason, "unknown")
    XCTAssertEqual(fake.scheduleAttempts, 0)
    XCTAssertEqual(fake.inventoryCalls, 0)
    XCTAssertNil(UserDefaults.standard.data(forKey: mirrorKey))
    XCTAssertEqual(UserDefaults.standard.data(forKey: pendingMirrorKey), pendingData)
    XCTAssertNil(UserDefaults.standard.data(forKey: envelopeKey))
    XCTAssertNil(UserDefaults.standard.data(forKey: transactionKey))

    // A same-tuple pending recovery row remains idempotently schedulable when
    // authoritative native inventory is empty.
    clearMirror()
    let sameTupleRecord: [String: String] = [
      "reservationId": request.reservationId,
      "occurrenceId": request.occurrenceId,
      "wakePlanId": request.wakePlanId,
      "platformAlarmId": id,
    ]
    UserDefaults.standard.set(
      mirrorData([id: sameTupleRecord]),
      forKey: pendingMirrorKey
    )
    let retry = await bridge.scheduleAlarm(request)
    XCTAssertEqual(retry.status, "success")
    XCTAssertEqual(fake.scheduleAttempts, 1)
    XCTAssertTrue(mirrorContains(id))

    // A legacy pending row without a complete configuration cannot prove
    // which same-UUID native configuration is live, so fail closed instead
    // of promoting it from UUID presence alone.
    clearMirror()
    UserDefaults.standard.set(
      mirrorData([id: sameTupleRecord]),
      forKey: pendingMirrorKey
    )
    fake.inventoryIdsOverride = nil
    fake.nativeAlarmIds.insert(id.uppercased())
    let nativePresentBridge = AlarmKitBridge(nativeClient: fake)
    let nativePresent = await nativePresentBridge.scheduleAlarm(request)
    XCTAssertEqual(nativePresent.status, "failure")
    XCTAssertEqual(nativePresent.failureReason, "nativeError")
    XCTAssertEqual(fake.scheduleAttempts, 1)
    XCTAssertFalse(mirrorContains(id))
    XCTAssertTrue(pendingMirrorContains(id))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeCanonicalizesNativeUuidForLiveScheduleAndInventory() async throws {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-native-casing")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    let nativePlatformAlarmId = platformAlarmId.uppercased()
    clearMirror()
    UserDefaults.standard.set(
      try completeMirrorData([
        platformAlarmId: [
          "reservationId": request.reservationId,
          "occurrenceId": request.occurrenceId,
          "wakePlanId": request.wakePlanId,
          "platformAlarmId": platformAlarmId,
          "scheduledAt": request.scheduledAt.timeIntervalSinceReferenceDate,
          "targetAt": request.targetAt.timeIntervalSinceReferenceDate,
          "soundId": request.soundId,
          "vibrationEnabled": request.vibrationEnabled,
        ]
      ]),
      forKey: mirrorKey
    )
    fake.nativeAlarmIds.insert(nativePlatformAlarmId)
    defer { clearMirror() }

    let scheduleResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(scheduleResult.status, "success")
    XCTAssertEqual(scheduleResult.platformAlarmId, platformAlarmId)
    XCTAssertEqual(fake.scheduleAttempts, 0)

    let value = await inventoryValue(bridge)
    let response = value as? [String: Any?]
    let rows = response?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, platformAlarmId)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgePreservesMirrorWhenNativeFailureCommitsUppercaseAlarm() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failFirstSchedule = true
    fake.insertBeforeFailFirstSchedule = true
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-unknown-commit")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let result = await bridge.scheduleAlarm(request)
    XCTAssertEqual(result.failureReason, "nativeError")
    XCTAssertEqual(fake.nativeAlarmIds, Set([platformAlarmId.uppercased()]))
    XCTAssertTrue(pendingMirrorContains(platformAlarmId))
    XCTAssertFalse(mirrorContains(platformAlarmId))

    let inventory = await inventoryValue(bridge)
    let response = inventory as? [String: Any?]
    let rows = response?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, platformAlarmId)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeObserverCanonicalizesNativeUuidBeforePruning() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-observer-casing")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let scheduleResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(scheduleResult.status, "success")
    await bridge.reconcileMirror(withNativeAlarmIds: [platformAlarmId.uppercased()])
    XCTAssertTrue(mirrorContains(platformAlarmId))
    await bridge.reconcileMirror(withNativeAlarmIds: [])
    XCTAssertFalse(mirrorContains(platformAlarmId))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRejectsExplicitEmptyReservationAndWrongOwner() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-cancel-owner")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let scheduleResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(scheduleResult.status, "success")
    let wrongOwner = await bridge.cancelAlarm([
      "occurrenceId": request.occurrenceId,
      "reservationId": "wrong-owner",
      "platformAlarmId": platformAlarmId.uppercased(),
    ])
    XCTAssertEqual(wrongOwner["failureReason"] as? String, "invalidRequest")
    XCTAssertEqual(fake.cancelCalls, 0)
    XCTAssertTrue(mirrorContains(platformAlarmId))

    let emptyReservation = await bridge.cancelAlarm([
      "occurrenceId": request.occurrenceId,
      "reservationId": "",
      "platformAlarmId": platformAlarmId.uppercased(),
    ])
    XCTAssertEqual(emptyReservation["failureReason"] as? String, "invalidRequest")
    XCTAssertEqual(fake.cancelCalls, 0)
    XCTAssertTrue(mirrorContains(platformAlarmId))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeKeepsMirrorlessLegacyUuidCancellationCompatible() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let legacyId = UUID().uuidString
    clearMirror()
    defer { clearMirror() }
    fake.nativeAlarmIds.insert(legacyId)

    let result = await bridge.cancelAlarm([
      "occurrenceId": "legacy-occurrence",
      "platformAlarmId": legacyId.lowercased(),
    ])
    XCTAssertEqual(result["status"] as? String, "success")
    XCTAssertEqual(fake.cancelCalls, 1)
    XCTAssertTrue(fake.nativeAlarmIds.isEmpty)
    XCTAssertTrue(committedMirrorObject()?.isEmpty == true)
    XCTAssertEqual(mirrorEnvelopeVersion(), 1)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRejectsMirrorlessTupleBearingCancellationWithoutNativeMutation() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let unownedId = UUID().uuidString
    clearMirror()
    defer { clearMirror() }
    fake.nativeAlarmIds.insert(unownedId)

    let result = await bridge.cancelAlarm([
      "occurrenceId": "unowned-occurrence",
      "reservationId": "unowned-reservation",
      "platformAlarmId": unownedId.lowercased(),
    ])

    XCTAssertEqual(result["status"] as? String, "failure")
    XCTAssertEqual(result["failureReason"] as? String, "invalidRequest")
    XCTAssertEqual(fake.cancelCalls, 0)
    XCTAssertEqual(fake.nativeAlarmIds, Set([unownedId]))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeMigratesUppercaseMirrorAndRejectsCanonicalCollision() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-mirror-casing")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    let uppercasePlatformAlarmId = platformAlarmId.uppercased()
    let uppercaseData = mirrorData([
      uppercasePlatformAlarmId: [
        "reservationId": request.reservationId,
        "occurrenceId": request.occurrenceId,
        "wakePlanId": request.wakePlanId,
        "platformAlarmId": uppercasePlatformAlarmId,
      ]
    ])
    clearMirror()
    UserDefaults.standard.set(uppercaseData, forKey: mirrorKey)
    fake.nativeAlarmIds.insert(uppercasePlatformAlarmId)
    defer { clearMirror() }

    let inventory = await inventoryValue(bridge)
    let response = inventory as? [String: Any?]
    let rows = response?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, platformAlarmId)
    XCTAssertEqual(
      committedMirrorObject()?[platformAlarmId] as? [String: String],
      [
        "reservationId": request.reservationId,
        "occurrenceId": request.occurrenceId,
        "wakePlanId": request.wakePlanId,
        "platformAlarmId": platformAlarmId,
      ]
    )
    XCTAssertEqual(mirrorEnvelopeVersion(), 1)

    let collisionData = mirrorData([
      platformAlarmId: [
        "reservationId": "collision-lower",
        "occurrenceId": "collision-occurrence-lower",
        "wakePlanId": "wake-lower",
        "platformAlarmId": platformAlarmId,
      ],
      uppercasePlatformAlarmId: [
        "reservationId": "collision-upper",
        "occurrenceId": "collision-occurrence-upper",
        "wakePlanId": "wake-upper",
        "platformAlarmId": uppercasePlatformAlarmId,
      ],
    ])
    clearMirror()
    UserDefaults.standard.set(collisionData, forKey: mirrorKey)
    fake.nativeAlarmIds.removeAll()
    fake.inventoryCalls = 0
    let corrupt = await inventoryValue(bridge)
    XCTAssertEqual((corrupt as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), collisionData)
    XCTAssertEqual(fake.inventoryCalls, 1)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeMigratesLegacyPendingAndIdenticalPromotionWithoutCorruption() async {
    let request = makeScheduleRequest("reservation-legacy-pending")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    let record: [String: String] = [
      "reservationId": request.reservationId,
      "occurrenceId": request.occurrenceId,
      "wakePlanId": request.wakePlanId,
      "platformAlarmId": id,
    ]
    let legacyData = mirrorData([id: record])
    let fake = FakeAlarmKitNativeClient()
    fake.nativeAlarmIds.insert(id.uppercased())
    let bridge = AlarmKitBridge(nativeClient: fake)
    clearMirror()
    UserDefaults.standard.set(legacyData, forKey: pendingMirrorKey)
    let result = await inventoryValue(bridge)
    let rows = (result as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertTrue(mirrorContains(id))
    XCTAssertEqual(mirrorEnvelopeVersion(), 1)
    XCTAssertNil(UserDefaults.standard.data(forKey: pendingMirrorKey))

    clearMirror()
    UserDefaults.standard.set(legacyData, forKey: mirrorKey)
    UserDefaults.standard.set(legacyData, forKey: pendingMirrorKey)
    let duplicateFake = FakeAlarmKitNativeClient()
    duplicateFake.nativeAlarmIds.insert(id.uppercased())
    let duplicateBridge = AlarmKitBridge(nativeClient: duplicateFake)
    let duplicateResult = await inventoryValue(duplicateBridge)
    XCTAssertEqual(
      ((duplicateResult as? [String: Any?])?["reservations"] as? [[String: Any?]])?.count,
      1
    )
    XCTAssertEqual(mirrorEnvelopeVersion(), 1)
    XCTAssertNil(UserDefaults.standard.data(forKey: pendingMirrorKey))
    let restartBridge = AlarmKitBridge(nativeClient: fake)
    let cancelResult = await restartBridge.cancelAlarm([
      "occurrenceId": request.occurrenceId,
      "reservationId": request.reservationId,
      "platformAlarmId": id.uppercased(),
    ])
    XCTAssertEqual(cancelResult["status"] as? String, "success")
    XCTAssertTrue(fake.nativeAlarmIds.isEmpty)
    XCTAssertFalse(mirrorContains(id))
    clearMirror()
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeLegacyMirrorConflictsAndMalformedSideRemainRecoverablyCorrupt() async {
    let request = makeScheduleRequest("reservation-legacy-conflict")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    let baseRecord: [String: String] = [
      "reservationId": request.reservationId,
      "occurrenceId": request.occurrenceId,
      "wakePlanId": request.wakePlanId,
      "platformAlarmId": id,
    ]
    let conflictingRecord = [
      "reservationId": request.reservationId,
      "occurrenceId": "different-occurrence",
      "wakePlanId": request.wakePlanId,
      "platformAlarmId": id,
    ]
    let cases: [(Data, Data)] = [
      (mirrorData([id: baseRecord]), Data("not-json".utf8)),
      (mirrorData([id: baseRecord]), mirrorData([id: conflictingRecord])),
    ]

    for (committedData, pendingData) in cases {
      let fake = FakeAlarmKitNativeClient()
      let bridge = AlarmKitBridge(nativeClient: fake)
      clearMirror()
      UserDefaults.standard.set(committedData, forKey: mirrorKey)
      UserDefaults.standard.set(pendingData, forKey: pendingMirrorKey)
      let result = await inventoryValue(bridge)
      XCTAssertEqual((result as? FlutterError)?.code, "corrupt")
      XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), committedData)
      XCTAssertEqual(UserDefaults.standard.data(forKey: pendingMirrorKey), pendingData)
      XCTAssertEqual(fake.inventoryCalls, 1)
    }
    clearMirror()
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeMalformedPendingDoesNotFallBackToEnvelope() async {
    let request = makeScheduleRequest("reservation-envelope-restart")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    let record: [String: String] = [
      "reservationId": request.reservationId,
      "occurrenceId": request.occurrenceId,
      "wakePlanId": request.wakePlanId,
      "platformAlarmId": id,
    ]
    let envelopeData = mirrorEnvelopeData(committed: [id: record], pending: [:])
    let fake = FakeAlarmKitNativeClient()
    fake.nativeAlarmIds.insert(id.uppercased())
    let bridge = AlarmKitBridge(nativeClient: fake)
    clearMirror()
    let malformedPending = Data("stale legacy bytes".utf8)
    UserDefaults.standard.set(envelopeData, forKey: mirrorKey)
    UserDefaults.standard.set(malformedPending, forKey: pendingMirrorKey)

    let result = await inventoryValue(bridge)
    XCTAssertEqual((result as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), envelopeData)
    XCTAssertEqual(UserDefaults.standard.data(forKey: pendingMirrorKey), malformedPending)
    clearMirror()
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRollbackProjectionRemainsReadableAndDoesNotResurrectOldRows() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-rollback-projection")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    let scheduleResult = await bridge.scheduleAlarm(request)
    XCTAssertEqual(scheduleResult.status, "success")
    let committedProjection = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: mirrorKey)
    )
    XCTAssertNil(
      (try? JSONSerialization.jsonObject(with: committedProjection) as? [String: Any])?["version"]
    )
    XCTAssertEqual(mirrorEnvelopeVersion(), 1)

    // Simulate an older binary updating the committed projection after the
    // new writer published its envelope. The new reader must honor that
    // mutation rather than resurrecting stale envelope fields.
    let legacyUpdatedRecord: [String: String] = [
      "reservationId": request.reservationId,
      "occurrenceId": request.occurrenceId,
      "wakePlanId": request.wakePlanId,
      "platformAlarmId": id,
    ]
    UserDefaults.standard.set(
      mirrorData([id: legacyUpdatedRecord]),
      forKey: mirrorKey
    )
    let restartedAfterLegacyRewrite = AlarmKitBridge(nativeClient: fake)
    let updatedInventory = await inventoryValue(restartedAfterLegacyRewrite)
    let updatedRows = (updatedInventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(
      updatedRows?.first?["occurrenceId"] as? String,
      request.occurrenceId
    )

    let migratedEnvelope = try! XCTUnwrap(mirrorEnvelopeObject())
    let migratedRecord = try! XCTUnwrap(
      (migratedEnvelope["committed"] as? [String: Any])?[id] as? [String: Any]
    )
    XCTAssertNotNil(migratedRecord["scheduledAt"])
    XCTAssertNotNil(migratedRecord["targetAt"])
    XCTAssertEqual(migratedRecord["soundId"] as? String, request.soundId)
    XCTAssertEqual(migratedRecord["vibrationEnabled"] as? Bool, request.vibrationEnabled)

    // A legacy caller omits reservationId. The recovered identity remains
    // cancellable, and a restart must not resurrect it after native removal.
    let cancelResult = await restartedAfterLegacyRewrite.cancelAlarm([
      "occurrenceId": request.occurrenceId,
      "platformAlarmId": id.uppercased(),
    ])
    XCTAssertEqual(cancelResult["status"] as? String, "success")
    XCTAssertTrue(fake.nativeAlarmIds.isEmpty)
    let restarted = AlarmKitBridge(nativeClient: fake)
    let inventory = await inventoryValue(restarted)
    let rows = (inventory as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 0)
    let rewrittenProjection = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: mirrorKey)
    )
    let rewrittenProjectionObject = try! XCTUnwrap(
      try? JSONSerialization.jsonObject(with: rewrittenProjection) as? [String: Any]
    )
    XCTAssertNil(rewrittenProjectionObject["version"])
    XCTAssertTrue(rewrittenProjectionObject.isEmpty)
    let rewrittenEnvelope = try! XCTUnwrap(mirrorEnvelopeObject())
    XCTAssertEqual((rewrittenEnvelope["committed"] as? [String: Any])?.count, 0)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeUnsupportedEnvelopeRemainsCorruptWithoutLoss() async {
    let request = makeScheduleRequest("reservation-envelope-fallback")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    let record: [String: String] = [
      "reservationId": request.reservationId,
      "occurrenceId": request.occurrenceId,
      "wakePlanId": request.wakePlanId,
      "platformAlarmId": id,
    ]
    let fake = FakeAlarmKitNativeClient()
    fake.nativeAlarmIds.insert(id.uppercased())
    let bridge = AlarmKitBridge(nativeClient: fake)
    clearMirror()
    let legacyData = mirrorData([id: record])
    let unsupportedEnvelope = Data(
      "{\"version\":2,\"committed\":{},\"pending\":{}}".utf8
    )
    UserDefaults.standard.set(legacyData, forKey: mirrorKey)
    UserDefaults.standard.set(unsupportedEnvelope, forKey: envelopeKey)
    defer { clearMirror() }

    let inventory = await inventoryValue(bridge)
    XCTAssertEqual((inventory as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), legacyData)
    XCTAssertEqual(UserDefaults.standard.data(forKey: envelopeKey), unsupportedEnvelope)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeReconcilesActualPriorEnvelopeWriterBeforeRestart() async {
    let currentRequest = makeScheduleRequest("reservation-current-envelope")
    let priorRequest = makeScheduleRequest(
      "reservation-prior-envelope",
      occurrenceId: "prior-occurrence"
    )
    let currentId = calarmPlatformAlarmId(for: currentRequest.reservationId)
    let priorId = calarmPlatformAlarmId(for: priorRequest.reservationId)
    let priorRecord: [String: String] = [
      "reservationId": priorRequest.reservationId,
      "occurrenceId": priorRequest.occurrenceId,
      "wakePlanId": priorRequest.wakePlanId,
      "platformAlarmId": priorId,
    ]
    let fake = FakeAlarmKitNativeClient()
    clearMirror()
    let currentWriter = AlarmKitBridge(nativeClient: fake)
    let currentResult = await currentWriter.scheduleAlarm(currentRequest)
    XCTAssertEqual(currentResult.status, "success")
    try! fake.cancel(id: UUID(uuidString: currentId)!)
    fake.nativeAlarmIds.insert(priorId.uppercased())
    let bridge = AlarmKitBridge(nativeClient: fake)
    defer { clearMirror() }

    // This is the exact prior writer shape: a MirrorEnvelope in the legacy
    // key, including a changed occurrence identity, after a current envelope
    // was already published.
    UserDefaults.standard.set(
      mirrorEnvelopeData(committed: [priorId: priorRecord], pending: [:]),
      forKey: mirrorKey
    )

    let inventory = await inventoryValue(bridge)
    let rows = (inventory as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["reservationId"] as? String, priorRequest.reservationId)
    XCTAssertEqual(rows?.first?["occurrenceId"] as? String, priorRequest.occurrenceId)
    XCTAssertNotEqual(rows?.first?["reservationId"] as? String, currentRequest.reservationId)

    // Simulate the same prior reader cancelling the row, leaving a prior
    // empty envelope while the current envelope still contains stale data.
    try! fake.cancel(id: UUID(uuidString: priorId)!)
    UserDefaults.standard.set(
      mirrorEnvelopeData(committed: [:], pending: [:]),
      forKey: mirrorKey
    )
    let restarted = AlarmKitBridge(nativeClient: fake)
    let afterCancel = await inventoryValue(restarted)
    let afterRows = (afterCancel as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(afterRows?.count, 0)
    XCTAssertEqual((mirrorEnvelopeObject()?["committed"] as? [String: Any])?.count, 0)

    // A native row that exists only in the stale current envelope is not
    // resurrected; the reader reports non-authoritative state instead.
    clearMirror()
    let conflictFake = FakeAlarmKitNativeClient()
    let conflictWriter = AlarmKitBridge(nativeClient: conflictFake)
    let conflictResult = await conflictWriter.scheduleAlarm(currentRequest)
    XCTAssertEqual(conflictResult.status, "success")
    let currentEnvelopeData = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: envelopeKey)
    )
    let priorEmptyData = mirrorData([:])
    UserDefaults.standard.set(currentEnvelopeData, forKey: envelopeKey)
    UserDefaults.standard.set(priorEmptyData, forKey: mirrorKey)
    let conflictBridge = AlarmKitBridge(nativeClient: conflictFake)
    let conflictInventoryResult = await inventoryValue(conflictBridge)
    XCTAssertEqual((conflictInventoryResult as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), priorEmptyData)
    XCTAssertEqual(UserDefaults.standard.data(forKey: envelopeKey), currentEnvelopeData)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeNativeReadFailureDoesNotPersistUppercaseMirrorMigration() async {
    let fake = FakeAlarmKitNativeClient()
    fake.inventoryError = true
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-native-read-failure")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    let uppercasePlatformAlarmId = platformAlarmId.uppercased()
    let originalData = mirrorData([
      uppercasePlatformAlarmId: [
        "reservationId": request.reservationId,
        "occurrenceId": request.occurrenceId,
        "wakePlanId": request.wakePlanId,
        "platformAlarmId": uppercasePlatformAlarmId,
      ]
    ])
    clearMirror()
    UserDefaults.standard.set(originalData, forKey: mirrorKey)
    defer { clearMirror() }

    let value = await inventoryValue(bridge)
    XCTAssertEqual((value as? FlutterError)?.code, "nativeError")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), originalData)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRejectsMalformedAndDuplicateNativeSnapshotsBeforeScheduleSideEffects() async {
    let request = makeScheduleRequest("reservation-invalid-native-snapshot")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    let cases = [
      ["not-a-uuid"],
      [platformAlarmId, platformAlarmId.uppercased()],
      [calarmPlatformAlarmId(for: "unrelated"), calarmPlatformAlarmId(for: "unrelated")],
    ]

    for nativeIds in cases {
      let fake = FakeAlarmKitNativeClient()
      fake.inventoryIdsOverride = nativeIds
      let bridge = AlarmKitBridge(nativeClient: fake)
      clearMirror()

      let result = await bridge.scheduleAlarm(request)
      XCTAssertNotEqual(result.status, "success")
      XCTAssertEqual(result.failureReason, "unknown")
      XCTAssertEqual(fake.scheduleAttempts, 0)
      XCTAssertNil(UserDefaults.standard.data(forKey: mirrorKey))
    }
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRejectsValidUnmappedNativeIdentityAcrossScheduleInventoryObserverAndCleanup() async {
    let request = makeScheduleRequest("reservation-known-native")
    let knownId = calarmPlatformAlarmId(for: request.reservationId)
    let unrelatedId = calarmPlatformAlarmId(for: "reservation-unmapped-native")
    let originalData = mirrorData([
      knownId: [
        "reservationId": request.reservationId,
        "occurrenceId": request.occurrenceId,
        "wakePlanId": request.wakePlanId,
        "platformAlarmId": knownId,
      ]
    ])

    let scheduleFake = FakeAlarmKitNativeClient()
    scheduleFake.inventoryIdsOverride = [unrelatedId.uppercased()]
    let scheduleBridge = AlarmKitBridge(nativeClient: scheduleFake)
    clearMirror()
    let scheduleResult = await scheduleBridge.scheduleAlarm(request)
    XCTAssertEqual(scheduleResult.failureReason, "unknown")
    XCTAssertEqual(scheduleFake.scheduleAttempts, 0)
    XCTAssertNil(UserDefaults.standard.data(forKey: mirrorKey))

    let inventoryFake = FakeAlarmKitNativeClient()
    inventoryFake.inventoryIdsOverride = [unrelatedId.uppercased()]
    let inventoryBridge = AlarmKitBridge(nativeClient: inventoryFake)
    UserDefaults.standard.set(originalData, forKey: mirrorKey)
    let inventoryResult = await inventoryValue(inventoryBridge)
    XCTAssertEqual((inventoryResult as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), originalData)

    let observerFake = FakeAlarmKitNativeClient()
    observerFake.inventoryIdsOverride = [unrelatedId.uppercased()]
    let observerBridge = AlarmKitBridge(nativeClient: observerFake)
    let observerData = UserDefaults.standard.data(forKey: mirrorKey)
    await observerBridge.reconcileMirror(withNativeAlarmIds: [unrelatedId.uppercased()])
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), observerData)
    let observerInventory = await inventoryValue(observerBridge)
    XCTAssertEqual((observerInventory as? FlutterError)?.code, "corrupt")

    let cleanupFake = FakeAlarmKitNativeClient()
    cleanupFake.failFirstSchedule = true
    cleanupFake.inventoryIdsByCall = [1: [], 2: [unrelatedId.uppercased()]]
    let cleanupBridge = AlarmKitBridge(nativeClient: cleanupFake)
    clearMirror()
    let cleanupResult = await cleanupBridge.scheduleAlarm(
      makeScheduleRequest("reservation-cleanup-unmapped")
    )
    XCTAssertEqual(cleanupResult.failureReason, "nativeError")
    XCTAssertNil(cleanupResult.platformAlarmId)
    XCTAssertTrue(pendingMirrorContains(calarmPlatformAlarmId(for: "reservation-cleanup-unmapped")))
    XCTAssertEqual(committedMirrorObject()?.count, 0)
    XCTAssertEqual(mirrorEnvelopeVersion(), 1)
    XCTAssertEqual(cleanupFake.cancelCalls, 0)
    clearMirror()
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeDuplicateAndMalformedInventorySnapshotsPreserveMirrorBytes() async {
    let request = makeScheduleRequest("reservation-invalid-inventory")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    let uppercasePlatformAlarmId = platformAlarmId.uppercased()
    let originalData = mirrorData([
      uppercasePlatformAlarmId: [
        "reservationId": request.reservationId,
        "occurrenceId": request.occurrenceId,
        "wakePlanId": request.wakePlanId,
        "platformAlarmId": uppercasePlatformAlarmId,
      ]
    ])
    let nativeIdCases = [
      ["not-a-uuid"],
      [platformAlarmId, uppercasePlatformAlarmId],
      [calarmPlatformAlarmId(for: "unrelated"), calarmPlatformAlarmId(for: "unrelated")],
    ]

    for nativeIds in nativeIdCases {
      let fake = FakeAlarmKitNativeClient()
      fake.inventoryIdsOverride = nativeIds
      let bridge = AlarmKitBridge(nativeClient: fake)
      clearMirror()
      UserDefaults.standard.set(originalData, forKey: mirrorKey)

      let value = await inventoryValue(bridge)
      XCTAssertEqual((value as? FlutterError)?.code, "corrupt")
      XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), originalData)
    }
    clearMirror()
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeObserverInvalidSnapshotsPreserveMirrorBytes() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-invalid-observer")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    let uppercasePlatformAlarmId = platformAlarmId.uppercased()
    let originalData = mirrorData([
      uppercasePlatformAlarmId: [
        "reservationId": request.reservationId,
        "occurrenceId": request.occurrenceId,
        "wakePlanId": request.wakePlanId,
        "platformAlarmId": uppercasePlatformAlarmId,
      ]
    ])
    clearMirror()
    UserDefaults.standard.set(originalData, forKey: mirrorKey)
    await bridge.reconcileMirror(withNativeAlarmIds: [uppercasePlatformAlarmId, "not-a-uuid"])
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), originalData)
    await bridge.reconcileMirror(withNativeAlarmIds: [platformAlarmId, uppercasePlatformAlarmId])
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), originalData)
    clearMirror()
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeUnknownScheduleCleanupPreservesUppercaseMirrorBytes() async {
    let fake = FakeAlarmKitNativeClient()
    fake.failFirstSchedule = true
    fake.insertBeforeFailFirstSchedule = true
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-cleanup-casing")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    let uppercasePlatformAlarmId = platformAlarmId.uppercased()
    let originalData = mirrorData([
      uppercasePlatformAlarmId: [
        "reservationId": request.reservationId,
        "occurrenceId": request.occurrenceId,
        "wakePlanId": request.wakePlanId,
        "platformAlarmId": uppercasePlatformAlarmId,
      ]
    ])
    clearMirror()
    UserDefaults.standard.set(originalData, forKey: mirrorKey)
    defer { clearMirror() }

    let result = await bridge.scheduleAlarm(request)
    XCTAssertEqual(result.failureReason, "nativeError")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), originalData)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRejectsKeyMismatchBeforePruningEmptyNativeInventory() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let key = calarmPlatformAlarmId(for: "reservation-1")
    let wrongPlatformId = calarmPlatformAlarmId(for: "reservation-2")
    let data = mirrorData([
      key: [
        "reservationId": "reservation-1",
        "occurrenceId": "occurrence-1",
        "wakePlanId": "wake-plan-1",
        "platformAlarmId": wrongPlatformId,
      ]
    ])
    clearMirror()
    UserDefaults.standard.set(data, forKey: mirrorKey)
    defer { clearMirror() }

    let value = await inventoryValue(bridge)
    XCTAssertEqual((value as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), data)
    XCTAssertEqual(fake.inventoryCalls, 1)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeRejectsDuplicateMirrorIdentityBeforePruning() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let firstId = calarmPlatformAlarmId(for: "reservation-1")
    let secondId = calarmPlatformAlarmId(for: "reservation-2")
    let data = mirrorData([
      firstId: [
        "reservationId": "same-reservation",
        "occurrenceId": "occurrence-1",
        "wakePlanId": "wake-plan-1",
        "platformAlarmId": firstId,
      ],
      secondId: [
        "reservationId": "same-reservation",
        "occurrenceId": "occurrence-2",
        "wakePlanId": "wake-plan-2",
        "platformAlarmId": secondId,
      ],
    ])
    clearMirror()
    UserDefaults.standard.set(data, forKey: mirrorKey)
    defer { clearMirror() }

    let value = await inventoryValue(bridge)
    XCTAssertEqual((value as? FlutterError)?.code, "corrupt")
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), data)
    XCTAssertEqual(fake.inventoryCalls, 1)
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeReportsCorruptPersistedMirrorExplicitly() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    clearMirror()
    UserDefaults.standard.set(Data("not-json".utf8), forKey: mirrorKey)
    defer { clearMirror() }

    let value: Any? = await withCheckedContinuation {
      (continuation: CheckedContinuation<Any?, Never>) in
      bridge.getInventory { result in
        continuation.resume(returning: result)
      }
    }
    guard let error = value as? FlutterError else {
      XCTFail("Expected a corrupt inventory FlutterError")
      return
    }
    XCTAssertEqual(error.code, "corrupt")
  }
}

private let mirrorKey = "net.xpadev.calarm/native_alarm_mirror"
private let pendingMirrorKey = "net.xpadev.calarm/native_alarm_pending_mirror"
private let envelopeKey = "net.xpadev.calarm/native_alarm_mirror_envelope"
private let transactionKey = "net.xpadev.calarm/native_alarm_mirror_transaction"
private let replacementJournalKey = "net.xpadev.calarm/native_alarm_replacement_journal"

@MainActor
private final class FakeAlarmKitNativeClient: AlarmKitNativeClient {
  enum FakeError: Error {
    case scheduleFailed
    case inventoryFailed
  }

  var isAuthorized = true
  var nativeAlarmIds = Set<String>()
  var scheduleAttempts = 0
  var activeSchedules = 0
  var maxActiveSchedules = 0
  var firstScheduleStarted = false
  var allowFirstScheduleToFinish = false
  var gateFirstSchedule = false
  var failFirstSchedule = false
  var failedScheduleAttempts = Set<Int>()
  var removeBeforeFailScheduleAttempts = Set<Int>()
  var throwAfterMutationScheduleAttempts = Set<Int>()
  var insertBeforeFailFirstSchedule = false
  var cancelCalls = 0
  var failedCancelAttempts = Set<Int>()
  var throwAfterMutationCancelAttempts = Set<Int>()
  var scheduledRequests: [String: ScheduleRequest] = [:]
  var inventoryCalls = 0
  var inventoryError = false
  var inventoryErrorOnCall: Int?
  var inventoryIdsOverride: [String]?
  var inventoryIdsByCall: [Int: [String]] = [:]
  var gatedScheduleAttempts = Set<Int>()
  var gatedScheduleStartedAttempts = Set<Int>()
  var allowGatedSchedules = false

  func inventory() throws -> [NativeAlarmSnapshot] {
    inventoryCalls += 1
    if inventoryError || inventoryErrorOnCall == inventoryCalls {
      throw FakeError.inventoryFailed
    }
    let ids = inventoryIdsByCall[inventoryCalls]
      ?? inventoryIdsOverride
      ?? Array(nativeAlarmIds)
    return ids.map {
      NativeAlarmSnapshot(platformAlarmId: $0, status: "scheduled")
    }
  }

  func schedule(id: UUID, request: ScheduleRequest) async throws -> String {
    scheduleAttempts += 1
    activeSchedules += 1
    maxActiveSchedules = max(maxActiveSchedules, activeSchedules)
    defer { activeSchedules -= 1 }

    if gateFirstSchedule && scheduleAttempts == 1 {
      firstScheduleStarted = true
      while !allowFirstScheduleToFinish {
        await Task.yield()
      }
    }
    if gatedScheduleAttempts.contains(scheduleAttempts) {
      gatedScheduleStartedAttempts.insert(scheduleAttempts)
      while !allowGatedSchedules {
        await Task.yield()
      }
    }
    if failFirstSchedule && scheduleAttempts == 1 {
      if insertBeforeFailFirstSchedule {
        nativeAlarmIds.insert(id.uuidString)
      }
      throw FakeError.scheduleFailed
    }
    if failedScheduleAttempts.contains(scheduleAttempts) {
      if removeBeforeFailScheduleAttempts.contains(scheduleAttempts) {
        nativeAlarmIds.remove(id.uuidString)
        scheduledRequests.removeValue(forKey: id.uuidString.lowercased())
      }
      throw FakeError.scheduleFailed
    }
    nativeAlarmIds.insert(id.uuidString)
    scheduledRequests[id.uuidString.lowercased()] = request
    if throwAfterMutationScheduleAttempts.contains(scheduleAttempts) {
      throw FakeError.scheduleFailed
    }
    return id.uuidString
  }

  func cancel(id: UUID) throws {
    cancelCalls += 1
    if failedCancelAttempts.contains(cancelCalls) {
      throw FakeError.scheduleFailed
    }
    nativeAlarmIds.remove(id.uuidString)
    scheduledRequests.removeValue(forKey: id.uuidString.lowercased())
    if throwAfterMutationCancelAttempts.contains(cancelCalls) {
      throw FakeError.scheduleFailed
    }
  }
}

private func makeScheduleRequest(
  _ reservationId: String = "reservation-1",
  occurrenceId: String = "occurrence-1"
) -> ScheduleRequest {
  let date = Date(timeIntervalSince1970: 1_900_000_000)
  return ScheduleRequest(
    occurrenceId: occurrenceId,
    reservationId: reservationId,
    wakePlanId: "wake-plan-1",
    scheduledAt: date,
    targetAt: date,
    soundId: "default",
    vibrationEnabled: true
  )
}

private func makeSchedulePayload(
  occurrenceId: String = "occurrence-1"
) -> [String: Any?] {
  let date = "2030-04-05T06:07:08.000Z"
  return [
    "occurrenceId": occurrenceId,
    "wakePlanId": "wake-plan-1",
    "scheduledAt": date,
    "targetAt": date,
    "soundId": "default",
    "vibrationEnabled": true,
  ]
}

private func clearMirror() {
  UserDefaults.standard.removeObject(forKey: mirrorKey)
  UserDefaults.standard.removeObject(forKey: pendingMirrorKey)
  UserDefaults.standard.removeObject(forKey: envelopeKey)
  UserDefaults.standard.removeObject(forKey: transactionKey)
  UserDefaults.standard.removeObject(forKey: replacementJournalKey)
}

private func mirrorData(_ records: [String: [String: String]]) -> Data {
  try! JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
}

private func completeMirrorData(_ records: [String: [String: Any]]) throws -> Data {
  try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
}

private func mirrorEnvelopeData(
  committed: [String: [String: String]],
  pending: [String: [String: String]]
) -> Data {
  try! JSONSerialization.data(
    withJSONObject: [
      "version": 1,
      "committed": committed,
      "pending": pending,
    ],
    options: [.sortedKeys]
  )
}

private func mirrorContains(_ platformAlarmId: String) -> Bool {
  committedMirrorObject()?[platformAlarmId] != nil
}

private func pendingMirrorContains(_ platformAlarmId: String) -> Bool {
  guard let data = UserDefaults.standard.data(forKey: pendingMirrorKey),
    let mirror = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    guard let envelope = mirrorEnvelopeObject() else { return false }
    let pending = envelope["pending"] as? [String: Any]
    return pending?[platformAlarmId] != nil
  }
  return mirror[platformAlarmId] != nil
}

private func mirrorEnvelopeObject() -> [String: Any]? {
  guard let data = UserDefaults.standard.data(forKey: envelopeKey)
      ?? UserDefaults.standard.data(forKey: mirrorKey),
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    object["version"] != nil
  else { return nil }
  return object
}

private func committedMirrorObject() -> [String: Any]? {
  guard let data = UserDefaults.standard.data(forKey: envelopeKey)
      ?? UserDefaults.standard.data(forKey: mirrorKey),
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { return nil }
  return (object["committed"] as? [String: Any]) ?? object
}

private func mirrorEnvelopeVersion() -> Int? {
  mirrorEnvelopeObject()?["version"] as? Int
}

@MainActor
private func inventoryValue(_ bridge: AlarmKitBridge) async -> Any? {
  await withCheckedContinuation {
    (continuation: CheckedContinuation<Any?, Never>) in
    bridge.getInventory { result in
      continuation.resume(returning: result)
    }
  }
}

@MainActor
private func methodChannelValue(
  _ bridge: AlarmKitBridge,
  method: String,
  arguments: Any?
) async -> Any? {
  await withCheckedContinuation {
    (continuation: CheckedContinuation<Any?, Never>) in
    bridge.handle(
      FlutterMethodCall(methodName: method, arguments: arguments)
    ) { result in
      continuation.resume(returning: result)
    }
  }
}
