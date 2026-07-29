import XCTest
@testable import parrot

final class ModelRegistryTests: XCTestCase {
    func testSmallEnglishIsTheMeasuredRecommendation() {
        let recommended = ModelRegistry.shared.filter(\.recommended)

        XCTAssertEqual(recommended.map(\.id), ["whisper-small.en"])
        XCTAssertEqual(ModelRegistry.recommended()?.id, "whisper-small.en")
    }
}
