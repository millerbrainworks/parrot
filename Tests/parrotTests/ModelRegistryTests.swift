import XCTest
@testable import parrot

final class ModelRegistryTests: XCTestCase {
    func testBaseEnglishIsTheResilientLowLatencyDefault() {
        let recommended = ModelRegistry.shared.filter(\.recommended)

        XCTAssertEqual(recommended.count, 1)
        XCTAssertEqual(ModelRegistry.recommended()?.id, "whisper-base.en")
    }
}
