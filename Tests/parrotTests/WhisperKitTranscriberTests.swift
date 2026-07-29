import XCTest
@testable import parrot

final class WhisperKitTranscriberTests: XCTestCase {
    func testPromptedDecodingOptionsPreserveTokensAndDisableFirstTokenThreshold() {
        let promptTokens = [10173, 80, 4906]

        let options = WhisperKitTranscriber.makeDecodingOptions(
            promptTokens: promptTokens
        )

        XCTAssertEqual(options.promptTokens, promptTokens)
        XCTAssertNil(options.firstTokenLogProbThreshold)
        XCTAssertEqual(options.logProbThreshold, -1.0)
        XCTAssertEqual(options.noSpeechThreshold, 0.6)
        XCTAssertEqual(options.temperatureFallbackCount, 5)
    }
}
