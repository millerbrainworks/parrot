import XCTest
@testable import parrot

final class VocabularyPromptBuilderTests: XCTestCase {
    func testBuildsUniquePromptAndKeepsMostRecentTokenWindow() {
        var encodedText: String?
        let tokens = VocabularyPromptBuilder.tokens(
            for: [" Arcqtype ", "", "ARQ", "arcqtype"],
            maximumCount: 3
        ) { text in
            encodedText = text
            return [1, 2, 3, 4, 5]
        }

        XCTAssertEqual(encodedText, " Arcqtype, ARQ")
        XCTAssertEqual(tokens, [3, 4, 5])
    }

    func testEmptyVocabularyDoesNotInvokeTokenizer() {
        var invoked = false
        let tokens = VocabularyPromptBuilder.tokens(for: [" ", ""]) { _ in
            invoked = true
            return [1]
        }

        XCTAssertNil(tokens)
        XCTAssertFalse(invoked)
    }
}
