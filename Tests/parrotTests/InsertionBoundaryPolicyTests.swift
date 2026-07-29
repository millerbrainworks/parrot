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

    func testPrefixesExactlyOneSpaceAfterNumber() {
        XCTAssertEqual(
            policy.prepare("next", context: .caret(previous: "7")),
            " next"
        )
    }

    func testPrefixesExactlyOneSpaceAfterClosingDelimiters() {
        XCTAssertEqual(
            policy.prepare("next", context: .caret(previous: ")")),
            " next"
        )
        XCTAssertEqual(
            policy.prepare("next", context: .caret(previous: "]")),
            " next"
        )
        XCTAssertEqual(
            policy.prepare("next", context: .caret(previous: "}")),
            " next"
        )
    }

    func testPrefixesExactlyOneSpaceBeforeNumber() {
        XCTAssertEqual(
            policy.prepare("7 items", context: .caret(previous: ".")),
            " 7 items"
        )
        XCTAssertEqual(
            policy.prepare("7 items", context: .caret(previous: "d")),
            " 7 items"
        )
    }

    func testPrefixesExactlyOneSpaceBeforeOpeningQuotes() {
        XCTAssertEqual(
            policy.prepare("\"quoted\"", context: .caret(previous: ".")),
            " \"quoted\""
        )
        XCTAssertEqual(
            policy.prepare("'quoted'", context: .caret(previous: ".")),
            " 'quoted'"
        )
        XCTAssertEqual(
            policy.prepare("“quoted”", context: .caret(previous: ".")),
            " “quoted”"
        )
        XCTAssertEqual(
            policy.prepare("‘quoted’", context: .caret(previous: ".")),
            " ‘quoted’"
        )
    }

    func testPrefixesExactlyOneSpaceBeforeOpeningDelimiter() {
        XCTAssertEqual(
            policy.prepare("(aside)", context: .caret(previous: ".")),
            " (aside)"
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
