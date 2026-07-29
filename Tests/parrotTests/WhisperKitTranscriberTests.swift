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
    }
}
