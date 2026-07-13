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

}
