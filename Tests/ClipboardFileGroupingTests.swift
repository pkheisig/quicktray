import XCTest
@testable import QuickTray

final class ClipboardFileGroupingTests: XCTestCase {
    func testFileGroupMetadataRoundTripsThroughHistoryEncoding() throws {
        let groupID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let item = ClipboardItem(
            fileURL: URL(fileURLWithPath: "/tmp/report.pdf"),
            fileGroupID: groupID,
            fileGroupIndex: 2,
            timestamp: timestamp
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)

        XCTAssertEqual(decoded.fileGroupID, groupID)
        XCTAssertEqual(decoded.fileGroupIndex, 2)
        XCTAssertEqual(decoded.timestamp, timestamp)
        XCTAssertEqual(decoded.filePath, "/tmp/report.pdf")
    }

    func testCapturedFilesBecomeOneListGroupEvenWhenSortingSeparatesThem() {
        let groupID = UUID()
        let timestamp = Date()
        let first = makeFile("a.txt", groupID: groupID, index: 0, timestamp: timestamp)
        let second = makeFile("b.pdf", groupID: groupID, index: 1, timestamp: timestamp)
        let standalone = makeFile("single.png")

        let entries = LauncherListEntry.grouped([first, standalone, second])

        XCTAssertEqual(entries.count, 2)
        guard case .fileGroup(let group) = entries[0] else {
            return XCTFail("Expected the capture batch to render as a file group")
        }
        XCTAssertEqual(group.id, groupID)
        XCTAssertEqual(group.items.map(\.id), [first.id, second.id])
        guard case .item(let item) = entries[1] else {
            return XCTFail("Expected the unrelated file to remain a normal list item")
        }
        XCTAssertEqual(item.id, standalone.id)
    }

    func testSingleVisibleGroupMemberFallsBackToNormalRow() {
        let item = makeFile("only-visible.txt", groupID: UUID(), index: 1)

        let entries = LauncherListEntry.grouped([item])

        XCTAssertEqual(entries.count, 1)
        guard case .item(let renderedItem) = entries[0] else {
            return XCTFail("A filtered group with one member should not show a group wrapper")
        }
        XCTAssertEqual(renderedItem.id, item.id)
    }

    func testLegacySingleFileHistoryStillDecodesWithoutGroupMetadata() throws {
        let item = makeFile("legacy.txt")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
        )
        object.removeValue(forKey: "fileGroupID")
        object.removeValue(forKey: "fileGroupIndex")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: legacyData)

        XCTAssertNil(decoded.fileGroupID)
        XCTAssertNil(decoded.fileGroupIndex)
    }

    private func makeFile(
        _ name: String,
        groupID: UUID? = nil,
        index: Int? = nil,
        timestamp: Date = Date()
    ) -> ClipboardItem {
        ClipboardItem(
            fileURL: URL(fileURLWithPath: "/tmp/\(name)"),
            fileGroupID: groupID,
            fileGroupIndex: index,
            timestamp: timestamp
        )
    }
}
