import Foundation
import Flutter
import UIKit
import XCTest

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

}
