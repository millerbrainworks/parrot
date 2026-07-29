import XCTest
@testable import parrot

final class CorrectionObservationPolicyTests: XCTestCase {
    func testObservationExpiresAndRejectsSecureOrChangedFocus() {
        let policy = CorrectionObservationPolicy(timeout: 30)

        XCTAssertFalse(
            policy.canObserve(elapsed: 31, sameElement: true, secure: false)
        )
        XCTAssertFalse(
            policy.canObserve(elapsed: 1, sameElement: false, secure: false)
        )
        XCTAssertFalse(
            policy.canObserve(elapsed: 1, sameElement: true, secure: true)
        )
        XCTAssertTrue(
            policy.canObserve(elapsed: 1, sameElement: true, secure: false)
        )
    }

    func testPrefixResolverFindsLengthChangingCorrectionWithoutReadingSuffix() {
        XCTAssertEqual(
            CorrectionPrefixResolver.proposal(
                original: "Build the archetype app.",
                observedPrefix: "Build the Arcqtype"
            ),
            CorrectionProposal(original: "archetype", corrected: "Arcqtype")
        )
    }

    func testPrefixResolverRejectsTypingAppendedAfterInsertion() {
        XCTAssertNil(
            CorrectionPrefixResolver.proposal(
                original: "Build it.",
                observedPrefix: "Build it. More"
            )
        )
    }
}
