import XCTest
@testable import QuickTray

final class SettingsBehaviorTests: XCTestCase {
    func testCloseAfterEveryActionDismissesForCopyAndPaste() {
        XCTAssertTrue(LauncherDismissBehavior.afterCopyOrPaste.shouldDismiss(afterPaste: false))
        XCTAssertTrue(LauncherDismissBehavior.afterCopyOrPaste.shouldDismiss(afterPaste: true))
    }

    func testCloseAfterPasteLeavesLauncherOpenForCopy() {
        XCTAssertFalse(LauncherDismissBehavior.afterPaste.shouldDismiss(afterPaste: false))
        XCTAssertTrue(LauncherDismissBehavior.afterPaste.shouldDismiss(afterPaste: true))
    }

    func testNeverCloseLeavesLauncherOpen() {
        XCTAssertFalse(LauncherDismissBehavior.never.shouldDismiss(afterPaste: false))
        XCTAssertFalse(LauncherDismissBehavior.never.shouldDismiss(afterPaste: true))
    }

    func testAllSettingsChoicesHaveStableRawValuesAndLabels() {
        XCTAssertEqual(Set(ClipboardDuplicateBehavior.allCases.map(\.rawValue)).count, ClipboardDuplicateBehavior.allCases.count)
        XCTAssertEqual(Set(LauncherWindowPlacement.allCases.map(\.rawValue)).count, LauncherWindowPlacement.allCases.count)
        XCTAssertTrue(ClipboardDuplicateBehavior.allCases.allSatisfy { !$0.title.isEmpty })
        XCTAssertTrue(LauncherWindowPlacement.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
