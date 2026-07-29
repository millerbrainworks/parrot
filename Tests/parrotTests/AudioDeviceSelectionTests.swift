import CoreAudio
import XCTest
@testable import parrot

final class AudioDeviceSelectionTests: XCTestCase {
    private let devices = [
        AudioInputDevice(id: 7, uid: "built-in", name: "MacBook Microphone"),
        AudioInputDevice(id: 9, uid: "usb", name: "USB Microphone"),
    ]

    func testSystemDefaultUsesCurrentDefaultDevice() {
        let result = AudioDeviceSelection.resolve(
            savedUID: nil,
            devices: devices,
            defaultDeviceID: 7
        )

        XCTAssertEqual(result.deviceID, 7)
        XCTAssertNil(result.savedUID)
        XCTAssertEqual(result.displayName, "System Default")
        XCTAssertFalse(result.isFallback)
    }

    func testConnectedSavedDeviceIsSelected() {
        let result = AudioDeviceSelection.resolve(
            savedUID: "usb",
            devices: devices,
            defaultDeviceID: 7
        )

        XCTAssertEqual(result.deviceID, 9)
        XCTAssertEqual(result.savedUID, "usb")
        XCTAssertEqual(result.displayName, "USB Microphone")
        XCTAssertFalse(result.isFallback)
    }

    func testMissingSavedDeviceFallsBackWithoutForgettingUID() {
        let result = AudioDeviceSelection.resolve(
            savedUID: "missing",
            devices: devices,
            defaultDeviceID: 7
        )

        XCTAssertEqual(result.deviceID, 7)
        XCTAssertEqual(result.savedUID, "missing")
        XCTAssertEqual(result.displayName, "System Default")
        XCTAssertTrue(result.isFallback)
    }
}
