import SwiftUI
import XCTest
@testable import ArchipelagoClient

final class AppearanceModeTests: XCTestCase {
    func testDefaultModeIsDark() {
        XCTAssertEqual(AppearanceMode.defaultMode, .dark)
    }

    func testColorSchemeMapping() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }
}
