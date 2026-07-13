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
    XCTAssertFalse(mirrorContains(platformAlarmId))
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

    XCTAssertEqual((await first.value).status, "success")
    XCTAssertEqual((await second.value).status, "success")
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
    XCTAssertEqual((await bridge.scheduleAlarm(requestB)).status, "success")

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

    XCTAssertEqual((await schedule.value).status, "success")
    let cancelResult = await cancel.value
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
    XCTAssertEqual((await bridge.scheduleAlarm(unrelatedRequest)).status, "success")
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

    XCTAssertEqual((await schedule.value).status, "success")
    await observer.value
    XCTAssertTrue(mirrorContains(id))
    XCTAssertTrue(mirrorContains(unrelatedId))
    XCTAssertEqual(fake.nativeAlarmIds, Set([id.uppercased(), unrelatedId.uppercased()]))
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
    XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), originalData)
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
      XCTAssertEqual(UserDefaults.standard.data(forKey: mirrorKey), originalData)
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
    XCTAssertEqual(collisionResult["status"] as? String, "failure")
    XCTAssertEqual(collisionResult["failureReason"] as? String, "unknown")
    XCTAssertEqual(stableFake.scheduleAttempts, 1)
    XCTAssertTrue(mirrorContains(stablePlatformAlarmId))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeCanonicalizesNativeUuidForLiveScheduleAndInventory() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-native-casing")
    let platformAlarmId = calarmPlatformAlarmId(for: request.reservationId)
    let nativePlatformAlarmId = platformAlarmId.uppercased()
    clearMirror()
    UserDefaults.standard.set(
      mirrorData([
        platformAlarmId: [
          "reservationId": request.reservationId,
          "occurrenceId": request.occurrenceId,
          "wakePlanId": request.wakePlanId,
          "platformAlarmId": platformAlarmId,
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
      UserDefaults.standard.data(forKey: mirrorKey),
      mirrorData([
        platformAlarmId: [
          "reservationId": request.reservationId,
          "occurrenceId": request.occurrenceId,
          "wakePlanId": request.wakePlanId,
          "platformAlarmId": platformAlarmId,
        ]
      ])
    )

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
    XCTAssertEqual(fake.inventoryCalls, 0)
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
    XCTAssertEqual(fake.inventoryCalls, 0)
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
    XCTAssertEqual(fake.inventoryCalls, 0)
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
  var insertBeforeFailFirstSchedule = false
  var cancelCalls = 0
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
    nativeAlarmIds.insert(id.uuidString)
    return id.uuidString
  }

  func cancel(id: UUID) throws {
    cancelCalls += 1
    nativeAlarmIds.remove(id.uuidString)
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
  let date = "2030-04-05T06:07:08Z"
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
}

private func mirrorData(_ records: [String: [String: String]]) -> Data {
  try! JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
}

private func mirrorContains(_ platformAlarmId: String) -> Bool {
  guard let data = UserDefaults.standard.data(forKey: mirrorKey),
    let mirror = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    return false
  }
  return mirror[platformAlarmId] != nil
}

private func pendingMirrorContains(_ platformAlarmId: String) -> Bool {
  guard let data = UserDefaults.standard.data(forKey: pendingMirrorKey),
    let mirror = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    return false
  }
  return mirror[platformAlarmId] != nil
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
