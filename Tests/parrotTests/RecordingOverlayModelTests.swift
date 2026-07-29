import XCTest
@testable import parrot

@MainActor
final class RecordingOverlayModelTests: XCTestCase {
    func testRecordingOverlayGeometryIsDoubledProportionally() {
        XCTAssertEqual(RecordingOverlay.Geometry.panelWidth, 192)
        XCTAssertEqual(RecordingOverlay.Geometry.panelHeight, 40)
        XCTAssertEqual(RecordingOverlay.Geometry.buttonWidth, 52)
        XCTAssertEqual(RecordingOverlay.Geometry.waveformWidth, 88)
        XCTAssertEqual(RecordingOverlay.Geometry.waveformHeight, 28)
        XCTAssertEqual(RecordingOverlay.Geometry.iconSize, 16)
        XCTAssertEqual(RecordingOverlay.Geometry.waveformBarWidth, 4)
        XCTAssertEqual(RecordingOverlay.Geometry.waveformSpacing, 4)
    }

    func testRecordingActionsCallInjectedHandler() {
        var actions: [RecordingOverlay.Action] = []
        let model = OverlayModel(onAction: { actions.append($0) })

        model.cancel()
        model.finish()

        XCTAssertEqual(actions, [.cancel, .finish])
    }
}
