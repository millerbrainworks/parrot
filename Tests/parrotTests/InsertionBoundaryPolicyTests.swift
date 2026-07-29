import XCTest
@testable import parrot

final class InsertionBoundaryPolicyTests: XCTestCase {
    private let policy = InsertionBoundaryPolicy()

    func testPrefixesSpaceBetweenPeriodAndCapitalizedWord() {
        XCTAssertEqual(
            policy.prepare("Next", context: .caret(previous: ".")),
            " Next"
        )
    }

    func testPrefixesSpaceBetweenWords() {
        XCTAssertEqual(
            policy.prepare("world", context: .caret(previous: "o")),
            " world"
        )
    }

    func testPrefixesSpaceBetweenCommaAndWord() {
        XCTAssertEqual(
            policy.prepare("next", context: .caret(previous: ",")),
            " next"
        )
    }

    func testPrefixesSpaceBetweenClosingQuoteAndWord() {
        XCTAssertEqual(
            policy.prepare("next", context: .caret(previous: "”")),
            " next"
        )
    }

    func testDoesNotPrefixSpaceAfterWhitespace() {
        XCTAssertEqual(
            policy.prepare("next", context: .caret(previous: " ")),
            "next"
        )
        XCTAssertEqual(
            policy.prepare("next", context: .caret(previous: "\n")),
            "next"
        )
    }

    func testDoesNotPrefixSpaceAfterOpeningDelimiter() {
        XCTAssertEqual(
            policy.prepare("next", context: .caret(previous: "(")),
            "next"
        )
    }

    func testDoesNotPrefixSpaceAtDocumentStart() {
        XCTAssertEqual(
            policy.prepare("next", context: .documentStart),
            "next"
        )
    }

    func testDoesNotPrefixSpaceWhenReplacingSelection() {
        XCTAssertEqual(
            policy.prepare("next", context: .selection),
            "next"
        )
    }

    func testDoesNotPrefixSpaceWhenContextIsUnavailable() {
        XCTAssertEqual(
            policy.prepare("next", context: .unavailable),
            "next"
        )
    }

    func testDoesNotPrefixSpaceBeforePunctuationOnlyText() {
        XCTAssertEqual(
            policy.prepare("?!", context: .caret(previous: "d")),
            "?!"
        )
    }

    func testEmptyTextRemainsEmpty() {
        XCTAssertEqual(
            policy.prepare("", context: .caret(previous: "d")),
            ""
        )
    }
}
