import XCTest
@testable import parrot

final class DictationStateMachineTests: XCTestCase {
    func testToggleStartsAndStopsRecording() {
        var machine = DictationStateMachine()

        XCTAssertEqual(machine.handleToggle(), .startCapture)
        XCTAssertEqual(machine.state, .recording)
        XCTAssertEqual(machine.handleToggle(), .stopCapture)
        XCTAssertEqual(machine.state, .transcribing)
    }

    func testCancelOnlyWorksWhileRecording() {
        var machine = DictationStateMachine()

        XCTAssertEqual(machine.handleCancel(), .none)
        _ = machine.handleToggle()
        XCTAssertEqual(machine.handleCancel(), .cancelCapture)
        XCTAssertEqual(machine.state, .idle)
    }

    func testBusyStatesIgnoreGesturesAndCompletionReturnsIdle() {
        var machine = DictationStateMachine()

        _ = machine.handleToggle()
        _ = machine.handleToggle()
        XCTAssertEqual(machine.handleToggle(), .none)
        XCTAssertEqual(machine.handleCancel(), .none)

        machine.transcriptionSucceeded()
        XCTAssertEqual(machine.state, .injecting)
        XCTAssertEqual(machine.handleToggle(), .none)

        machine.finish()
        XCTAssertEqual(machine.state, .idle)
    }

    func testFailuresAndEmptyCaptureReturnIdle() {
        var captureFailure = DictationStateMachine()
        _ = captureFailure.handleToggle()
        captureFailure.captureFailed()
        XCTAssertEqual(captureFailure.state, .idle)

        var emptyCapture = DictationStateMachine()
        _ = emptyCapture.handleToggle()
        _ = emptyCapture.handleToggle()
        emptyCapture.emptyCapture()
        XCTAssertEqual(emptyCapture.state, .idle)

        var transcriptionFailure = DictationStateMachine()
        _ = transcriptionFailure.handleToggle()
        _ = transcriptionFailure.handleToggle()
        transcriptionFailure.transcriptionFailed()
        XCTAssertEqual(transcriptionFailure.state, .idle)
    }
}
