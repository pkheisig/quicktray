import XCTest
@testable import QuickTray

final class ClipboardExclusionTests: XCTestCase {
    private let typeless = ExcludedApplication(
        bundleIdentifier: AppSettings.typelessBundleIdentifier,
        displayName: "Typeless"
    )
    private let parrot = ExcludedApplication(
        bundleIdentifier: AppSettings.parrotBundleIdentifier,
        displayName: "Parrot"
    )

    func testDirectClipboardWritesFromExcludedBundleAreIgnored() {
        XCTAssertTrue(
            ClipboardExclusionRules.shouldIgnore(
                sourceName: "Parrot",
                sourceBundleIdentifier: AppSettings.parrotBundleIdentifier,
                excludedApplications: [parrot],
                recentlyInjectedByExcludedApplication: false,
                typelessFallbackActive: false
            )
        )
    }

    func testExcludedAppNameMatchesWhenBundleIdentifierIsUnavailable() {
        XCTAssertTrue(
            ClipboardExclusionRules.shouldIgnore(
                sourceName: "parrot",
                sourceBundleIdentifier: nil,
                excludedApplications: [parrot],
                recentlyInjectedByExcludedApplication: false,
                typelessFallbackActive: false
            )
        )
    }

    func testInjectedPasteFromExcludedAppIsIgnoredWhenTargetAppIsFrontmost() {
        XCTAssertTrue(
            ClipboardExclusionRules.shouldIgnore(
                sourceName: "Codex",
                sourceBundleIdentifier: "com.openai.codex",
                excludedApplications: [parrot],
                recentlyInjectedByExcludedApplication: true,
                typelessFallbackActive: false
            )
        )
    }

    func testOrdinaryClipboardWriteRemainsVisible() {
        XCTAssertFalse(
            ClipboardExclusionRules.shouldIgnore(
                sourceName: "Safari",
                sourceBundleIdentifier: "com.apple.Safari",
                excludedApplications: [typeless, parrot],
                recentlyInjectedByExcludedApplication: false,
                typelessFallbackActive: false
            )
        )
    }

    func testLegacyDisabledTypelessSettingMigratesWithoutTypelessButKeepsParrot() throws {
        let suiteName = "ClipboardExclusionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "settings.ignoreTypelessTranscriptions")

        let restored = AppSettings.restoredExcludedApplications(from: defaults)

        XCTAssertFalse(restored.contains(typeless))
        XCTAssertTrue(restored.contains(parrot))
    }
}
