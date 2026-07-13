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

    XCTAssertEqual((await bridge.scheduleAlarm(original)).status, "success")
    let retryResult = await bridge.scheduleAlarm(recreated)
    XCTAssertEqual(retryResult.status, "success")
    XCTAssertEqual(fake.scheduleAttempts, 2)
    XCTAssertEqual(fake.cancelCalls, 1)

    let inventory = await inventoryValue(bridge)
    let rows = (inventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["reservationId"] as? String, original.reservationId)
    XCTAssertEqual(rows?.first?["occurrenceId"] as? String, recreated.occurrenceId)
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, platformAlarmId)
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

    XCTAssertEqual((await scheduleA.value).status, "success")
    XCTAssertEqual((await scheduleB.value).status, "success")
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
    XCTAssertEqual((await bridgeB.scheduleAlarm(requestB)).status, "success")

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

    XCTAssertEqual((await schedule.value).status, "success")
    XCTAssertEqual((await cancel.value)["status"] as? String, "success")
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

    XCTAssertEqual((await schedule.value).status, "success")
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

    XCTAssertEqual((await schedule.value).status, "success")
    let inventoryValueResult = await inventory.value
    XCTAssertEqual(
      ((inventoryValueResult as? [String: Any?])?["reservations"] as? [[String: Any?]])?.count,
      1
    )
    XCTAssertTrue(mirrorContains(id))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeSharedMirrorCoordinatorSerializesCrossInstanceObserverCancel() async {
    let fakeA = FakeAlarmKitNativeClient()
    let fakeB = FakeAlarmKitNativeClient()
    let bridgeA = AlarmKitBridge(nativeClient: fakeA)
    let bridgeB = AlarmKitBridge(nativeClient: fakeB)
    let request = makeScheduleRequest("reservation-cross-observer-cancel", occurrenceId: "occurrence-cross-observer-cancel")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }
    XCTAssertEqual((await bridgeB.scheduleAlarm(request)).status, "success")

    let cancel = Task { @MainActor in
      await bridgeB.cancelAlarm([
        "occurrenceId": request.occurrenceId,
        "reservationId": request.reservationId,
        "platformAlarmId": id.uppercased(),
      ])
    }
    let observer = Task { @MainActor in
      await bridgeA.reconcileMirror(withNativeAlarmIds: [])
    }
    XCTAssertEqual((await cancel.value)["status"] as? String, "success")
    await observer.value
    XCTAssertTrue(fakeB.nativeAlarmIds.isEmpty)
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

    XCTAssertEqual((await failed.value).failureReason, "nativeError")
    XCTAssertEqual((await succeeded.value).status, "success")
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

    XCTAssertEqual((await bridge.scheduleAlarm(request)).failureReason, "nativeError")
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
  func testBridgeQuarantinesInvalidAlternativesWhenProjectionCoversLiveAlarm() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-quarantine-alternatives")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    XCTAssertEqual((await bridge.scheduleAlarm(request)).status, "success")
    UserDefaults.standard.set(
      mirrorEnvelopeData(
        committed: [id: [
          "reservationId": request.reservationId,
          "occurrenceId": request.occurrenceId,
          "wakePlanId": request.wakePlanId,
          "platformAlarmId": id,
        ]],
        pending: [:]
      ),
      forKey: envelopeKey
    )
    UserDefaults.standard.set(
      Data("malformed pending alternative".utf8),
      forKey: pendingMirrorKey
    )
    let value = await inventoryValue(bridge)
    let rows = (value as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, id)
    XCTAssertFalse(pendingMirrorContains(id))
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeQuarantinesNoncanonicalCurrentEnvelopeGeneration() async {
    let fake = FakeAlarmKitNativeClient()
    let bridge = AlarmKitBridge(nativeClient: fake)
    let request = makeScheduleRequest("reservation-lowercase-generation")
    let id = calarmPlatformAlarmId(for: request.reservationId)
    clearMirror()
    defer { clearMirror() }

    XCTAssertEqual((await bridge.scheduleAlarm(request)).status, "success")
    let envelope = try! XCTUnwrap(
      UserDefaults.standard.data(forKey: envelopeKey)
    )
    var object = try! XCTUnwrap(
      JSONSerialization.jsonObject(with: envelope) as? [String: Any]
    )
    object["generation"] = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    UserDefaults.standard.set(
      try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      forKey: envelopeKey
    )

    let value = await inventoryValue(bridge)
    let rows = (value as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(rows?.first?["platformAlarmId"] as? String, id)

    var unsupported = try! XCTUnwrap(
      JSONSerialization.jsonObject(
        with: try! XCTUnwrap(UserDefaults.standard.data(forKey: envelopeKey))
      ) as? [String: Any]
    )
    unsupported["version"] = 99
    UserDefaults.standard.set(
      try! JSONSerialization.data(withJSONObject: unsupported, options: [.sortedKeys]),
      forKey: envelopeKey
    )
    let unsupportedValue = await inventoryValue(bridge)
    let unsupportedRows = (unsupportedValue as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(unsupportedRows?.count, 1)
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

    XCTAssertEqual((await bridge.scheduleAlarm(request)).status, "success")
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
    XCTAssertEqual(collisionResult["status"] as? String, "failure")
    XCTAssertEqual(collisionResult["failureReason"] as? String, "unknown")
    XCTAssertEqual(stableFake.scheduleAttempts, 1)
    XCTAssertTrue(mirrorContains(stablePlatformAlarmId))
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

    // If the native alarm is already present, the same pending tuple is
    // promoted without a second native schedule call.
    clearMirror()
    UserDefaults.standard.set(
      mirrorData([id: sameTupleRecord]),
      forKey: pendingMirrorKey
    )
    fake.inventoryIdsOverride = nil
    fake.nativeAlarmIds.insert(id.uppercased())
    let nativePresentBridge = AlarmKitBridge(nativeClient: fake)
    let nativePresent = await nativePresentBridge.scheduleAlarm(request)
    XCTAssertEqual(nativePresent.status, "success")
    XCTAssertEqual(fake.scheduleAttempts, 1)
    XCTAssertTrue(mirrorContains(id))
    XCTAssertFalse(pendingMirrorContains(id))
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
    XCTAssertNil(UserDefaults.standard.data(forKey: mirrorKey))
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
    XCTAssertEqual(fake.inventoryCalls, 0)
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
      XCTAssertEqual(fake.inventoryCalls, 0)
    }
    clearMirror()
  }

  @available(iOS 26.0, *)
  @MainActor
  func testBridgeEnvelopeWinsAfterInterruptedLegacyCleanup() async {
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
    UserDefaults.standard.set(envelopeData, forKey: mirrorKey)
    UserDefaults.standard.set(Data("stale legacy bytes".utf8), forKey: pendingMirrorKey)

    let result = await inventoryValue(bridge)
    XCTAssertEqual(
      ((result as? [String: Any?])?["reservations"] as? [[String: Any?]])?.count,
      1
    )
    XCTAssertEqual(mirrorEnvelopeVersion(), 1)
    XCTAssertNil(UserDefaults.standard.data(forKey: pendingMirrorKey))
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

    XCTAssertEqual((await bridge.scheduleAlarm(request)).status, "success")
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
      "occurrenceId": "legacy-updated-occurrence",
      "wakePlanId": "legacy-updated-wake-plan",
      "platformAlarmId": id,
    ]
    UserDefaults.standard.set(
      mirrorData([id: legacyUpdatedRecord]),
      forKey: mirrorKey
    )
    let updatedInventory = await inventoryValue(bridge)
    let updatedRows = (updatedInventory as? [String: Any?])?["reservations"]
      as? [[String: Any?]]
    XCTAssertEqual(
      updatedRows?.first?["occurrenceId"] as? String,
      "legacy-updated-occurrence"
    )

    // Simulate an older binary cancelling the committed projection. The new
    // reader must honor that mutation rather than resurrecting the stale row.
    try! fake.cancel(id: UUID(uuidString: id)!)
    UserDefaults.standard.set(mirrorData([:]), forKey: mirrorKey)
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
  func testBridgeUnsupportedEnvelopeFallsBackToLegacyProjectionWithoutLoss() async {
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
    UserDefaults.standard.set(legacyData, forKey: mirrorKey)
    UserDefaults.standard.set(
      Data("{\"version\":2,\"committed\":{},\"pending\":{}}".utf8),
      forKey: envelopeKey
    )
    defer { clearMirror() }

    let inventory = await inventoryValue(bridge)
    let rows = (inventory as? [String: Any?])?["reservations"] as? [[String: Any?]]
    XCTAssertEqual(rows?.count, 1)
    XCTAssertEqual(mirrorEnvelopeVersion(), 1)
    XCTAssertNotNil(UserDefaults.standard.data(forKey: envelopeKey))
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
    let currentRecord: [String: String] = [
      "reservationId": currentRequest.reservationId,
      "occurrenceId": currentRequest.occurrenceId,
      "wakePlanId": currentRequest.wakePlanId,
      "platformAlarmId": currentId,
    ]
    let fake = FakeAlarmKitNativeClient()
    fake.nativeAlarmIds.insert(priorId.uppercased())
    let bridge = AlarmKitBridge(nativeClient: fake)
    clearMirror()
    defer { clearMirror() }

    // This is the exact prior writer shape: a MirrorEnvelope in the legacy
    // key, including a changed occurrence identity, after a current envelope
    // was already published.
    UserDefaults.standard.set(
      mirrorEnvelopeData(committed: [currentId: currentRecord], pending: [:]),
      forKey: envelopeKey
    )
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
    conflictFake.nativeAlarmIds.insert(currentId.uppercased())
    let conflictBridge = AlarmKitBridge(nativeClient: conflictFake)
    let currentEnvelopeData = mirrorEnvelopeData(
      committed: [currentId: currentRecord],
      pending: [:]
    )
    let priorEmptyData = mirrorEnvelopeData(committed: [:], pending: [:])
    UserDefaults.standard.set(currentEnvelopeData, forKey: envelopeKey)
    UserDefaults.standard.set(priorEmptyData, forKey: mirrorKey)
    let conflictResult = await inventoryValue(conflictBridge)
    XCTAssertEqual((conflictResult as? FlutterError)?.code, "corrupt")
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
private let envelopeKey = "net.xpadev.calarm/native_alarm_mirror_envelope"
private let transactionKey = "net.xpadev.calarm/native_alarm_mirror_transaction"

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
  UserDefaults.standard.removeObject(forKey: envelopeKey)
  UserDefaults.standard.removeObject(forKey: transactionKey)
}

private func mirrorData(_ records: [String: [String: String]]) -> Data {
  try! JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
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
