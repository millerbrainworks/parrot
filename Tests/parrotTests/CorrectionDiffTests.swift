import XCTest
@testable import parrot

final class CorrectionDiffTests: XCTestCase {
    func testFindsOneLocalizedSubstitution() {
        XCTAssertEqual(
            CorrectionDiff.proposal(
                original: "Build the archetype app.",
                corrected: "Build the Arcqtype app."
            ),
            CorrectionProposal(original: "archetype", corrected: "Arcqtype")
        )
    }

    func testFindsMultiwordToCanonicalSubstitution() {
        XCTAssertEqual(
            CorrectionDiff.proposal(
                original: "Open the arc type dashboard.",
                corrected: "Open the Arcqtype dashboard."
            ),
            CorrectionProposal(original: "arc type", corrected: "Arcqtype")
        )
    }

    func testFindsCapitalizationOnlyCorrection() {
        XCTAssertEqual(
            CorrectionDiff.proposal(
                original: "Use arcqtype.",
                corrected: "Use Arcqtype."
            ),
            CorrectionProposal(original: "arcqtype", corrected: "Arcqtype")
        )
    }

    func testRejectsInsertionDeletionAndUnchangedText() {
        XCTAssertNil(CorrectionDiff.proposal(original: "hello", corrected: "hello world"))
        XCTAssertNil(CorrectionDiff.proposal(original: "hello world", corrected: "hello"))
        XCTAssertNil(CorrectionDiff.proposal(original: "hello", corrected: "hello"))
    }

    func testRejectsBroadRewriteAndNewlines() {
        XCTAssertNil(
            CorrectionDiff.proposal(
                original: "red archetype app",
                corrected: "blue Arcqtype tool"
            )
        )
        XCTAssertNil(
            CorrectionDiff.proposal(
                original: "first archetype",
                corrected: "first Arcqtype\nsecond"
            )
        )
    }
}
