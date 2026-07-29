import XCTest
@testable import parrot

final class HotkeyEventPolicyTests: XCTestCase {
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
