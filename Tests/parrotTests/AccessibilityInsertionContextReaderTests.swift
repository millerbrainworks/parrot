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
}
