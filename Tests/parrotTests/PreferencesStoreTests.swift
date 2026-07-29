import Foundation
import XCTest
@testable import parrot

final class PreferencesStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parrot-preferences-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testMissingFileLoadsDefaults() throws {
        let store = PreferencesStore(url: directory.appendingPathComponent("preferences.json"))

        XCTAssertEqual(try store.load(), ParrotPreferences())
    }

    func testMicrophoneUIDRoundTripsInPrivateFile() throws {
        let url = directory.appendingPathComponent("preferences.json")
        let store = PreferencesStore(url: url)

        try store.save(ParrotPreferences(microphoneUID: "device-123"))

        XCTAssertEqual(
            try store.load(),
            ParrotPreferences(microphoneUID: "device-123")
        )
        XCTAssertEqual(try permissions(of: url), 0o600)
        XCTAssertEqual(try permissions(of: directory), 0o700)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
