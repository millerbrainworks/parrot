import Foundation
import XCTest
@testable import parrot

final class AccessibilityInsertionContextReaderTests: XCTestCase {
    func testPlansSelectionWithoutReadingAdjacentText() {
        XCTAssertEqual(
            AccessibilityInsertionContextReader.plan(
                for: CFRange(location: 4, length: 3)
            ),
            .selection
        )
    }

    func testPlansDocumentStartWithoutReadingAdjacentText() {
        XCTAssertEqual(
            AccessibilityInsertionContextReader.plan(
                for: CFRange(location: 0, length: 0)
            ),
            .documentStart
        )
    }

    func testPlansAtMostTwoUTF16UnitsImmediatelyBeforeCaret() {
        XCTAssertEqual(
            AccessibilityInsertionContextReader.plan(
                for: CFRange(location: 1, length: 0)
            ),
            .precedingText(location: 0, length: 1)
        )
        XCTAssertEqual(
            AccessibilityInsertionContextReader.plan(
                for: CFRange(location: 7, length: 0)
            ),
            .precedingText(location: 5, length: 2)
        )
    }

    func testRejectsInvalidSelectedRanges() {
        XCTAssertEqual(
            AccessibilityInsertionContextReader.plan(
                for: CFRange(location: -1, length: 0)
            ),
            .unavailable
        )
        XCTAssertEqual(
            AccessibilityInsertionContextReader.plan(
                for: CFRange(location: 1, length: -1)
            ),
            .unavailable
        )
    }

    func testSensitivityCheckAllowsAnAbsentOptionalSubrole() {
        XCTAssertFalse(
            AccessibilityInsertionContextReader.isSensitive(
                role: "AXTextArea",
                subrole: nil
            )
        )
    }

    func testSensitivityCheckRejectsSecureRoleOrSubrole() {
        XCTAssertTrue(
            AccessibilityInsertionContextReader.isSensitive(
                role: "AXPasswordField",
                subrole: nil
            )
        )
        XCTAssertTrue(
            AccessibilityInsertionContextReader.isSensitive(
                role: "AXTextField",
                subrole: "AXSecureTextField"
            )
        )
    }

    func testProtectedContentStopsBeforeSelectedRangeOrAdjacentTextReads() {
        var selectedRangeReadCount = 0
        var adjacentTextReadCount = 0

        let context = AccessibilityInsertionContextReader.resolve(
            role: "AXTextArea",
            subrole: nil,
            protectedContent: .value(true),
            selectedRange: {
                selectedRangeReadCount += 1
                return CFRange(location: 1, length: 0)
            },
            precedingCharacter: { _, _ in
                adjacentTextReadCount += 1
                return "x"
            }
        )

        guard case .unavailable = context else {
            return XCTFail("expected protected content to be unavailable")
        }
        XCTAssertEqual(selectedRangeReadCount, 0)
        XCTAssertEqual(adjacentTextReadCount, 0)
    }

    func testAbsentProtectedContentAttributeKeepsOrdinaryControlsWorking() {
        var selectedRangeReadCount = 0
        var adjacentTextReadCount = 0

        let context = AccessibilityInsertionContextReader.resolve(
            role: "AXTextArea",
            subrole: nil,
            protectedContent: .absent,
            selectedRange: {
                selectedRangeReadCount += 1
                return CFRange(location: 1, length: 0)
            },
            precedingCharacter: { _, _ in
                adjacentTextReadCount += 1
                return "x"
            }
        )

        guard case let .caret(previous) = context else {
            return XCTFail("expected ordinary content to return caret context")
        }
        XCTAssertEqual(previous, "x")
        XCTAssertEqual(selectedRangeReadCount, 1)
        XCTAssertEqual(adjacentTextReadCount, 1)
    }

    func testProtectedContentAttributeParsingFailsClosed() {
        XCTAssertEqual(
            AccessibilityInsertionContextReader.parseOptionalBoolean(
                result: .success,
                value: kCFBooleanTrue
            ),
            .value(true)
        )
        XCTAssertEqual(
            AccessibilityInsertionContextReader.parseOptionalBoolean(
                result: .noValue,
                value: nil
            ),
            .absent
        )
        XCTAssertEqual(
            AccessibilityInsertionContextReader.parseOptionalBoolean(
                result: .attributeUnsupported,
                value: nil
            ),
            .absent
        )
        XCTAssertEqual(
            AccessibilityInsertionContextReader.parseOptionalBoolean(
                result: .success,
                value: "true" as CFString
            ),
            .failure
        )
        XCTAssertEqual(
            AccessibilityInsertionContextReader.parseOptionalBoolean(
                result: .cannotComplete,
                value: nil
            ),
            .failure
        )
    }
}
