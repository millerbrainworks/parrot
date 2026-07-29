import XCTest
@testable import parrot

final class TextInjectorTests: XCTestCase {
    func testChunkingDoesNotSplitEmojiAfterNineteenASCIICharacters() {
        let text = String(repeating: "a", count: 19) + "😀"

        let chunks = TextInjector.utf16Chunks(for: text)

        XCTAssertEqual(chunks.map(\.count), [19, 2])
        assertValidChunks(chunks, reconstruct: text)
    }

    func testChunkingPreservesSurrogatePairsAcrossMultipleBoundaries() {
        let text = String(repeating: "a", count: 19)
            + "😀"
            + String(repeating: "b", count: 18)
            + "🚀"
            + String(repeating: "c", count: 18)
            + "🧠"

        let chunks = TextInjector.utf16Chunks(for: text)

        XCTAssertGreaterThan(chunks.count, 2)
        assertValidChunks(chunks, reconstruct: text)
    }

    private func assertValidChunks(
        _ chunks: [[UniChar]],
        reconstruct expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            chunks.allSatisfy { !$0.isEmpty && $0.count <= 20 },
            file: file,
            line: line
        )
        for chunk in chunks {
            XCTAssertFalse(
                chunk.first.map(isLowSurrogate) ?? false,
                file: file,
                line: line
            )
            XCTAssertFalse(
                chunk.last.map(isHighSurrogate) ?? false,
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            String(decoding: chunks.flatMap { $0 }, as: UTF16.self),
            expectedText,
            file: file,
            line: line
        )
    }

    private func isHighSurrogate(_ unit: UniChar) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    private func isLowSurrogate(_ unit: UniChar) -> Bool {
        (0xDC00...0xDFFF).contains(unit)
    }
}
