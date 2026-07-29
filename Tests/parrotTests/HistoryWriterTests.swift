import Foundation
import XCTest
@testable import parrot

final class HistoryWriterTests: XCTestCase {
    private var root: URL!
    private var calendar: Calendar!
    private var date: Date!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("parrot-history-\(UUID().uuidString)", isDirectory: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        date = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 29,
            hour: 14,
            minute: 37,
            second: 22
        ))!
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func testAppendCreatesPrivateDatedMarkdown() throws {
        let writer = HistoryWriter(rootDirectory: root, calendar: calendar)

        let url = try XCTUnwrap(writer.append(
            text: "Draft the release notes.",
            applicationName: "Codex",
            at: date
        ))

        XCTAssertTrue(url.path.hasSuffix("/2026/07/2026-07-29.md"))
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8),
            "## 14:37:22 — Codex\n\nDraft the release notes.\n\n"
        )
        XCTAssertEqual(try permissions(of: url), 0o600)
        XCTAssertEqual(try permissions(of: url.deletingLastPathComponent()), 0o700)
    }

    func testAppendPreservesTextAndAppendsAnotherEntry() throws {
        let writer = HistoryWriter(rootDirectory: root, calendar: calendar)

        _ = try writer.append(text: "- First\n- Second", applicationName: "Codex", at: date)
        _ = try writer.append(text: "Follow up", applicationName: "Unknown Application", at: date)

        let url = root.appendingPathComponent("2026/07/2026-07-29.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("## 14:37:22 — Codex\n\n- First\n- Second\n\n"))
        XCTAssertTrue(content.hasSuffix("## 14:37:22 — Unknown Application\n\nFollow up\n\n"))
    }

    func testBlankTextIsNotWritten() throws {
        let writer = HistoryWriter(rootDirectory: root, calendar: calendar)

        XCTAssertNil(try writer.append(
            text: " \n\t",
            applicationName: "Codex",
            at: date
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
