import XCTest
@testable import parrot

final class TranscriptProcessorTests: XCTestCase {
    func testConservativeFillersAndCanonicalReplacements() {
        let dictionary = PersonalDictionary(
            version: 1,
            terms: ["Arcqtype"],
            replacements: [
                .init(canonical: "Arcqtype", variants: ["archetype", "arc type"]),
            ],
            fillerWords: ["um", "uh", "erm", "ah"]
        )
        let processor = TranscriptProcessor()

        XCTAssertEqual(
            processor.process("Um, archetype is, uh, actually useful.", using: dictionary),
            "Arcqtype is actually useful."
        )
        XCTAssertEqual(
            processor.process(
                "Human-like behavior, you know, matters. I mean, it actually does.",
                using: dictionary
            ),
            "Human-like behavior, you know, matters. I mean, it actually does."
        )
    }

    func testPhraseBoundariesAndLongestVariantWin() {
        let dictionary = PersonalDictionary(
            version: 1,
            terms: [],
            replacements: [
                .init(canonical: "ARQ", variants: ["arq"]),
                .init(canonical: "ARQ Score", variants: ["arq score"]),
            ],
            fillerWords: []
        )

        XCTAssertEqual(
            TranscriptProcessor().process("Show arq score, not marquee.", using: dictionary),
            "Show ARQ Score, not marquee."
        )
    }

    func testReplacementDoesNotMatchInsideLargerWord() {
        let dictionary = PersonalDictionary(
            version: 1,
            terms: [],
            replacements: [.init(canonical: "pane", variants: ["pain"])],
            fillerWords: []
        )

        XCTAssertEqual(
            TranscriptProcessor().process("The pain is not painstaking.", using: dictionary),
            "The pane is not painstaking."
        )
    }

    func testTermsNormalizeCaseAndPreserveAdjacentPunctuation() {
        let dictionary = PersonalDictionary(
            version: 1,
            terms: ["Codex", "ARQ Score", ".env"],
            replacements: [],
            fillerWords: []
        )

        XCTAssertEqual(
            TranscriptProcessor().process("codex, show arq score in .ENV.", using: dictionary),
            "Codex, show ARQ Score in .env."
        )
    }

    func testOnlyFillersProducesEmptyText() {
        let dictionary = PersonalDictionary(
            version: 1,
            terms: [],
            replacements: [],
            fillerWords: ["um", "uh"]
        )

        XCTAssertEqual(
            TranscriptProcessor().process("um, uh.", using: dictionary),
            ""
        )
    }

    func testLineBreaksRemainWhileHorizontalWhitespaceCollapses() {
        let dictionary = PersonalDictionary(
            version: 1,
            terms: [],
            replacements: [],
            fillerWords: []
        )

        XCTAssertEqual(
            TranscriptProcessor().process("first   line \n second\tline", using: dictionary),
            "first line\nsecond line"
        )
    }
}
