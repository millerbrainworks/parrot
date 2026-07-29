import XCTest
@testable import parrot

final class MenuBarModelTests: XCTestCase {
    func testIdleStateExplainsActivationGesture() {
        let model = MenuBarModel(
            state: .idle,
            microphoneName: "System Default",
            microphoneFallback: false
        )

        XCTAssertEqual(model.stateTitle, "Idle — double-tap Fn to dictate")
        XCTAssertEqual(model.microphoneTitle, "System Default")
        XCTAssertTrue(model.canChangeMicrophone)
    }

    func testUnavailableSavedMicrophoneShowsFallbackWarning() {
        let model = MenuBarModel(
            state: .idle,
            microphoneName: "System Default",
            microphoneFallback: true
        )

        XCTAssertEqual(model.microphoneTitle, "System Default ⚠")
    }

    func testBusyStatesDisableMicrophoneSelection() {
        XCTAssertFalse(MenuBarModel(
            state: .recording,
            microphoneName: "USB",
            microphoneFallback: false
        ).canChangeMicrophone)
        XCTAssertFalse(MenuBarModel(
            state: .transcribing,
            microphoneName: "USB",
            microphoneFallback: false
        ).canChangeMicrophone)
        XCTAssertEqual(
            MenuBarModel(
                state: .injecting,
                microphoneName: "USB",
                microphoneFallback: false
            ).stateTitle,
            "Inserting…"
        )
    }
}
