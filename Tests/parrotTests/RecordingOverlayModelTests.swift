import XCTest
@testable import parrot

@MainActor
final class RecordingOverlayModelTests: XCTestCase {
    func testRecordingOverlayGeometryUsesApprovedCompactSize() {
        XCTAssertEqual(RecordingOverlay.Geometry.panelWidth, 144)
        XCTAssertEqual(RecordingOverlay.Geometry.panelHeight, 28)
        XCTAssertEqual(RecordingOverlay.Geometry.buttonWidth, 39)
        XCTAssertEqual(RecordingOverlay.Geometry.waveformWidth, 66)
        XCTAssertEqual(RecordingOverlay.Geometry.waveformHeight, 20)
        XCTAssertEqual(RecordingOverlay.Geometry.iconSize, 11)
        XCTAssertEqual(RecordingOverlay.Geometry.waveformBarWidth, 3)
        XCTAssertEqual(RecordingOverlay.Geometry.waveformSpacing, 3)
    }

    func testRecordingActionsCallInjectedHandler() {
        var actions: [RecordingOverlay.Action] = []
        let model = OverlayModel(onAction: { actions.append($0) })

        model.cancel()
        model.finish()

        XCTAssertEqual(actions, [.cancel, .finish])
    }
}
