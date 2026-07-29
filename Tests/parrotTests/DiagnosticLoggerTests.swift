import XCTest
@testable import parrot

final class DiagnosticLoggerTests: XCTestCase {
    func testTranscriptionCompletionLogsTimingWithoutText() {
        var messages: [String] = []
        let logger = DiagnosticLogger { messages.append($0) }

        logger.transcriptionCompleted(duration: 0.42)

        XCTAssertEqual(messages, ["transcription completed in 0.42s"])
        XCTAssertFalse(messages.joined().contains("secret prompt"))
    }

    func testCaptureCompletionLogsMetricsWithoutAudioContent() {
        var messages: [String] = []
        let logger = DiagnosticLogger { messages.append($0) }

        logger.captureCompleted(duration: 1.25, rms: 0.123)

        XCTAssertEqual(messages, ["captured 1.25s · rms 0.123"])
    }
}
