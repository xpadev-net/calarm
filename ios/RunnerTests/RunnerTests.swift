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
    XCTAssertEqual(fake.nativeAlarmIds, Set([platformAlarmId]))
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
        "platformAlarmId": platformAlarmId,
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
    XCTAssertEqual(fake.nativeAlarmIds, Set([platformAlarmId]))
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
      "platformAlarmId": platformAlarmId,
    ])
    XCTAssertEqual(result["status"] as? String, "success")
    XCTAssertEqual(result["reservationId"] as? String, request.occurrenceId)
    XCTAssertTrue(fake.nativeAlarmIds.isEmpty)
    XCTAssertFalse(mirrorContains(platformAlarmId))
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

@MainActor
private final class FakeAlarmKitNativeClient: AlarmKitNativeClient {
  enum FakeError: Error {
    case scheduleFailed
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
  var cancelCalls = 0
  var inventoryCalls = 0

  func inventory() throws -> [NativeAlarmSnapshot] {
    inventoryCalls += 1
    nativeAlarmIds.map {
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
    if failFirstSchedule && scheduleAttempts == 1 {
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

private func makeScheduleRequest(_ reservationId: String = "reservation-1") -> ScheduleRequest {
  let date = Date(timeIntervalSince1970: 1_900_000_000)
  return ScheduleRequest(
    occurrenceId: "occurrence-1",
    reservationId: reservationId,
    wakePlanId: "wake-plan-1",
    scheduledAt: date,
    targetAt: date,
    soundId: "default",
    vibrationEnabled: true
  )
}

private func clearMirror() {
  UserDefaults.standard.removeObject(forKey: mirrorKey)
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

@MainActor
private func inventoryValue(_ bridge: AlarmKitBridge) async -> Any? {
  await withCheckedContinuation {
    (continuation: CheckedContinuation<Any?, Never>) in
    bridge.getInventory { result in
      continuation.resume(returning: result)
    }
  }
}
