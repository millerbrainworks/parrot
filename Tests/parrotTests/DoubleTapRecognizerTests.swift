import XCTest
@testable import parrot

final class DoubleTapRecognizerTests: XCTestCase {
    func testSecondTapInsideWindowRecognizesAndResets() {
        var recognizer = DoubleTapRecognizer(maxInterval: 0.35)

        XCTAssertFalse(recognizer.registerTap(at: 10.0))
        XCTAssertTrue(recognizer.registerTap(at: 10.34))
        XCTAssertFalse(recognizer.registerTap(at: 10.50))
    }

    func testTapOutsideWindowStartsANewPair() {
        var recognizer = DoubleTapRecognizer(maxInterval: 0.35)

        XCTAssertFalse(recognizer.registerTap(at: 10.0))
        XCTAssertFalse(recognizer.registerTap(at: 10.36))
        XCTAssertTrue(recognizer.registerTap(at: 10.60))
    }
}
