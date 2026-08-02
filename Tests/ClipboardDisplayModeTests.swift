import XCTest
@testable import QuickTray

final class ClipboardDisplayModeTests: XCTestCase {
    func testOnlyListAndTileModesAreAvailable() {
        XCTAssertEqual(ClipboardDisplayMode.allCases, [.list, .tiles])
    }

    func testListIsTheDefaultForMissingAndLegacyCompactPreferences() {
        XCTAssertEqual(ClipboardDisplayMode.restored(from: nil), .list)
        XCTAssertEqual(ClipboardDisplayMode.restored(from: "compact"), .list)
    }

    func testSavedTilePreferenceIsPreserved() {
        XCTAssertEqual(ClipboardDisplayMode.restored(from: "tiles"), .tiles)
    }
}
