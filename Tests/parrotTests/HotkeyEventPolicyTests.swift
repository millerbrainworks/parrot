import XCTest
@testable import parrot

final class HotkeyEventPolicyTests: XCTestCase {
    func testIdleRequiresDoubleTapAndStartingTapCannotAlsoFinish() {
        var policy = HotkeyEventPolicy()

        XCTAssertEqual(policy.fnReleased(at: 1.00), .none)
        XCTAssertEqual(policy.fnReleased(at: 1.20), .start)

        policy.recordingEnabled = true
        XCTAssertEqual(policy.fnReleased(at: 1.20), .none)
        XCTAssertEqual(policy.fnReleased(at: 1.60), .finish)
    }

    func testRecordingUsesOneNewTapToFinish() {
        var policy = HotkeyEventPolicy()
        policy.recordingEnabled = true

        XCTAssertEqual(policy.fnReleased(at: 2.0), .finish)
    }

    func testEscapePassesThroughWhenCancellationIsDisabled() {
        var policy = HotkeyEventPolicy()

        XCTAssertEqual(policy.escapeKeyDown(), .passThrough)
        XCTAssertEqual(policy.escapeKeyUp(), .passThrough)
    }

    func testEscapeIsConsumedWhenCancellationIsEnabled() {
        var policy = HotkeyEventPolicy()
        policy.cancellationEnabled = true

        XCTAssertEqual(policy.escapeKeyDown(), .cancelAndConsume)
        XCTAssertEqual(policy.escapeKeyUp(), .consume)
    }

    func testKeyUpRemainsConsumedAfterCancellationDisables() {
        var policy = HotkeyEventPolicy()
        policy.cancellationEnabled = true

        XCTAssertEqual(policy.escapeKeyDown(), .cancelAndConsume)
        policy.cancellationEnabled = false
        XCTAssertEqual(policy.escapeKeyUp(), .consume)
        XCTAssertEqual(policy.escapeKeyDown(), .passThrough)
    }
}
