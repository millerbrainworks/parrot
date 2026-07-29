import XCTest
@testable import parrot

final class MenuBarModelTests: XCTestCase {
    func testIdleStateExplainsActivationGesture() {
        let model = MenuBarModel(
            state: .idle,
            microphoneName: "System Default",
            microphoneFallback: false,
            dictionaryWarning: nil
        )

        XCTAssertEqual(model.stateTitle, "Idle — double-tap Fn to dictate")
        XCTAssertEqual(model.microphoneTitle, "System Default")
        XCTAssertTrue(model.canChangeMicrophone)
    }

    func testUnavailableSavedMicrophoneShowsFallbackWarning() {
        let model = MenuBarModel(
            state: .idle,
            microphoneName: "System Default",
            microphoneFallback: true,
            dictionaryWarning: nil
        )

        XCTAssertEqual(model.microphoneTitle, "System Default ⚠")
    }

    func testBusyStatesDisableMicrophoneSelection() {
        XCTAssertFalse(MenuBarModel(
            state: .recording,
            microphoneName: "USB",
            microphoneFallback: false,
            dictionaryWarning: nil
        ).canChangeMicrophone)
        XCTAssertFalse(MenuBarModel(
            state: .transcribing,
            microphoneName: "USB",
            microphoneFallback: false,
            dictionaryWarning: nil
        ).canChangeMicrophone)
        XCTAssertEqual(
            MenuBarModel(
                state: .injecting,
                microphoneName: "USB",
                microphoneFallback: false,
                dictionaryWarning: nil
            ).stateTitle,
            "Inserting…"
        )
    }

    func testRecordingExplainsSingleTapAndDictionaryWarning() {
        let model = MenuBarModel(
            state: .recording,
            microphoneName: "System Default",
            microphoneFallback: false,
            dictionaryWarning: "Personal Dictionary Needs Attention"
        )

        XCTAssertEqual(model.stateTitle, "● Recording — tap Fn to finish")
        XCTAssertTrue(model.showsDictionaryWarning)
    }
}
