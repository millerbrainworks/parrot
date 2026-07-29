import XCTest
@testable import parrot

@MainActor
final class RecordingOverlayModelTests: XCTestCase {
    func testRecordingActionsCallInjectedHandler() {
        var actions: [RecordingOverlay.Action] = []
        let model = OverlayModel(onAction: { actions.append($0) })

        model.cancel()
        model.finish()

        XCTAssertEqual(actions, [.cancel, .finish])
    }
}
