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

  @MainActor
  func testProductionScheduleCoordinatorKeepsDuplicateRetryRecoverable() async {
    let coordinator = AlarmScheduleCoordinator<Bool>()
    let state = AlarmScheduleRaceState()
    let nativeAlarmId = "native-alarm"
    let operation: @MainActor () async -> Bool = {
      await state.performOperation(nativeAlarmId: nativeAlarmId)
    }

    let first = Task { @MainActor in
      await coordinator.run(for: "reservation-1", operation: operation)
    }
    while !state.firstOperationStarted {
      await Task.yield()
    }

    let second = Task { @MainActor in
      await coordinator.run(for: "reservation-1", operation: operation)
    }
    await Task.yield()
    state.allowFirstOperationToFinish = true

    let firstResult = await first.value
    let secondResult = await second.value
    XCTAssertFalse(firstResult)
    XCTAssertTrue(secondResult)
    XCTAssertEqual(state.attempts, 2)
    XCTAssertEqual(state.maxActiveOperations, 1)
    XCTAssertTrue(state.nativeAlarmPresent)
    XCTAssertTrue(state.mirrorPresent)
    XCTAssertTrue(state.retrySawAbsentNativeAndMirror)
    XCTAssertFalse(
      calarmShouldRemoveMirrorAfterScheduleFailure(
        currentNativeAlarmIds: nil,
        platformAlarmId: nativeAlarmId
      )
    )
    XCTAssertFalse(
      calarmShouldRemoveMirrorAfterScheduleFailure(
        currentNativeAlarmIds: Set([nativeAlarmId]),
        platformAlarmId: nativeAlarmId
      )
    )
  }

}

@MainActor
private final class AlarmScheduleRaceState {
  var attempts = 0
  var activeOperations = 0
  var maxActiveOperations = 0
  var firstOperationStarted = false
  var allowFirstOperationToFinish = false
  var mirrorPresent = false
  var nativeAlarmPresent = false
  var retrySawAbsentNativeAndMirror = false

  func performOperation(nativeAlarmId: String) async -> Bool {
    attempts += 1
    activeOperations += 1
    maxActiveOperations = max(maxActiveOperations, activeOperations)
    defer { activeOperations -= 1 }

    mirrorPresent = true
    if attempts == 1 {
      firstOperationStarted = true
      while !allowFirstOperationToFinish {
        await Task.yield()
      }
      nativeAlarmPresent = false
      if calarmShouldRemoveMirrorAfterScheduleFailure(
        currentNativeAlarmIds: Set<String>(),
        platformAlarmId: nativeAlarmId
      ) {
        mirrorPresent = false
      }
      return false
    }

    retrySawAbsentNativeAndMirror = !nativeAlarmPresent && !mirrorPresent
    nativeAlarmPresent = true
    mirrorPresent = true
    return true
  }
}
