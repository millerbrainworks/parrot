import XCTest
@testable import parrot

final class CorrectionObservationPolicyTests: XCTestCase {
    func testObservationExpiresAndRejectsSecureOrChangedFocus() {
        let policy = CorrectionObservationPolicy(timeout: 30)
        let ordinaryAccess = AccessibilityTextAccess(
            role: "AXTextArea",
            subrole: .absent,
            protectedContent: .absent
        )
        let secureAccess = AccessibilityTextAccess(
            role: "AXTextField",
            subrole: .value("AXSecureTextField"),
            protectedContent: .absent
        )
        let selection = { CFRange(location: 0, length: 0) }

        XCTAssertNil(
            policy.selectedRangeForPoll(
                elapsed: 31,
                sameElement: true,
                access: ordinaryAccess,
                readSelectedRange: selection
            )
        )
        XCTAssertNil(
            policy.selectedRangeForPoll(
                elapsed: 1,
                sameElement: false,
                access: ordinaryAccess,
                readSelectedRange: selection
            )
        )
        XCTAssertNil(
            policy.selectedRangeForPoll(
                elapsed: 1,
                sameElement: true,
                access: secureAccess,
                readSelectedRange: selection
            )
        )
        XCTAssertNotNil(
            policy.selectedRangeForPoll(
                elapsed: 1,
                sameElement: true,
                access: ordinaryAccess,
                readSelectedRange: selection
            )
        )
    }

    func testPreparationAndPollingRejectProtectedOrInvalidContentBeforeRangeRead() {
        let policy = CorrectionObservationPolicy(timeout: 30)
        var selectedRangeReadCount = 0

        for protectedContent: AccessibilityOptionalAttribute<Bool> in [
            .value(true),
            .failure,
        ] {
            let access = AccessibilityTextAccess(
                role: "AXTextArea",
                subrole: .absent,
                protectedContent: protectedContent
            )
            XCTAssertNil(
                policy.selectedRangeForPreparation(access: access) {
                    selectedRangeReadCount += 1
                    return CFRange(location: 3, length: 0)
                }
            )
            XCTAssertNil(
                policy.selectedRangeForPoll(
                    elapsed: 1,
                    sameElement: true,
                    access: access
                ) {
                    selectedRangeReadCount += 1
                    return CFRange(location: 3, length: 0)
                }
            )
        }
        XCTAssertEqual(selectedRangeReadCount, 0)
    }

    func testAbsentOptionalAccessAttributesAllowPreparationAndPollingRangeRead() {
        let policy = CorrectionObservationPolicy(timeout: 30)
        let access = AccessibilityTextAccess(
            role: "AXTextArea",
            subrole: .absent,
            protectedContent: .absent
        )
        var selectedRangeReadCount = 0

        let preparationRange = policy.selectedRangeForPreparation(
            access: access
        ) {
            selectedRangeReadCount += 1
            return CFRange(location: 3, length: 0)
        }
        let pollingRange = policy.selectedRangeForPoll(
            elapsed: 1,
            sameElement: true,
            access: access
        ) {
            selectedRangeReadCount += 1
            return CFRange(location: 4, length: 0)
        }

        XCTAssertEqual(preparationRange?.location, 3)
        XCTAssertEqual(pollingRange?.location, 4)
        XCTAssertEqual(selectedRangeReadCount, 2)
    }

    func testRangePolicyRejectsNegativeSelectedRanges() {
        XCTAssertNil(
            CorrectionObservationRangePolicy.validatedSelection(
                CFRange(location: -1, length: 0)
            )
        )
        XCTAssertNil(
            CorrectionObservationRangePolicy.validatedSelection(
                CFRange(location: 0, length: -1)
            )
        )
        XCTAssertEqual(
            CorrectionObservationRangePolicy.readPlan(
                selection: CFRange(location: -1, length: 0),
                insertionStart: 0,
                originalLength: 1
            ),
            .cancel
        )
    }

    func testRangePolicyRejectsOverflowWithoutTrapping() {
        XCTAssertNil(
            CorrectionObservationRangePolicy.validatedSelection(
                CFRange(location: Int.max, length: 1)
            )
        )
        XCTAssertEqual(
            CorrectionObservationRangePolicy.readPlan(
                selection: CFRange(location: 0, length: 0),
                insertionStart: 0,
                originalLength: Int.max
            ),
            .cancel
        )
        XCTAssertEqual(
            CorrectionObservationRangePolicy.readPlan(
                selection: CFRange(location: Int.max - 3, length: 0),
                insertionStart: Int.max - 3,
                originalLength: 4,
                allowance: 0
            ),
            .cancel
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
