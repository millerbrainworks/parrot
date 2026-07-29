import Foundation
import XCTest
@testable import parrot

final class PersonalDictionaryStoreTests: XCTestCase {
    func testFirstLoadCreatesPrivateStarterDictionary() throws {
        let root = temporaryRoot()
        let store = PersonalDictionaryStore(rootDirectory: root)

        let dictionary = try store.load()

        XCTAssertTrue(dictionary.terms.contains("Arcqtype"))
        XCTAssertEqual(
            dictionary.replacements.first(where: { $0.canonical == "Arcqtype" })?.variants,
            ["archetype", "arc type", "ark type"]
        )
        XCTAssertEqual(dictionary.fillerWords, ["um", "uh", "erm", "ah"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(permissions(at: root), 0o700)
        XCTAssertEqual(permissions(at: store.fileURL), 0o600)
    }

    func testExternalValidEditReloadsOnNextLoad() throws {
        let root = temporaryRoot()
        let store = PersonalDictionaryStore(rootDirectory: root)
        _ = try store.load()
        let edited = PersonalDictionary(
            version: 1,
            terms: ["NewTerm"],
            replacements: [],
            fillerWords: ["um"]
        )
        let data = try JSONEncoder().encode(edited)
        try data.write(to: store.fileURL, options: .atomic)

        XCTAssertEqual(try store.load(), edited)
    }

    func testInvalidEditUsesLastValidDictionaryWithoutOverwritingFile() throws {
        let root = temporaryRoot()
        let store = PersonalDictionaryStore(rootDirectory: root)
        let first = try store.load()
        try Data("{broken".utf8).write(to: store.fileURL)

        let fallback = store.loadUsingFallback()

        XCTAssertEqual(fallback.dictionary, first)
        XCTAssertNotNil(fallback.warning)
        XCTAssertEqual(try String(contentsOf: store.fileURL, encoding: .utf8), "{broken")
    }

    func testInvalidFirstEditUsesBuiltInStarter() throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let file = root.appendingPathComponent("personal-dictionary.json")
        try Data("[]".utf8).write(to: file)
        let store = PersonalDictionaryStore(rootDirectory: root)

        let fallback = store.loadUsingFallback()

        XCTAssertEqual(fallback.dictionary, .starter)
        XCTAssertNotNil(fallback.warning)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "[]")
    }

    func testValidationRejectsBlankValues() throws {
        let store = PersonalDictionaryStore(rootDirectory: temporaryRoot())
        let invalid = PersonalDictionary(
            version: 1,
            terms: [""],
            replacements: [.init(canonical: "Arcqtype", variants: [])],
            fillerWords: [" "]
        )
        try FileManager.default.createDirectory(
            at: store.rootDirectory,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(invalid).write(to: store.fileURL)

        XCTAssertThrowsError(try store.load())
    }

    func testLearningMergesVariantWithoutDuplicates() throws {
        let store = PersonalDictionaryStore(rootDirectory: temporaryRoot())
        _ = try store.load()

        try store.learn(variant: "ark type", canonical: "Arcqtype")
        try store.learn(variant: "ARK TYPE", canonical: "Arcqtype")
        try store.learn(variant: "cloud", canonical: "Claude")

        let dictionary = try store.load()
        let arcqtype = dictionary.replacements.first { $0.canonical == "Arcqtype" }
        XCTAssertEqual(
            arcqtype?.variants.filter {
                $0.caseInsensitiveCompare("ark type") == .orderedSame
            }.count,
            1
        )
        XCTAssertEqual(
            dictionary.replacements.first { $0.canonical == "Claude" }?.variants,
            ["Cloud"]
        )
        XCTAssertEqual(permissions(at: store.fileURL), 0o600)
    }

    private func temporaryRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parrot-dictionary-tests-\(UUID().uuidString)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func permissions(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
