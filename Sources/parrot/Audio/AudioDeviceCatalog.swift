import CoreAudio
import Foundation

struct AudioInputDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

struct ResolvedAudioDevice: Equatable {
    let deviceID: AudioDeviceID?
    let savedUID: String?
    let displayName: String
    let isFallback: Bool
}

enum AudioDeviceSelection {
    static func resolve(
        savedUID: String?,
        devices: [AudioInputDevice],
        defaultDeviceID: AudioDeviceID?
    ) -> ResolvedAudioDevice {
        guard let savedUID else {
            return ResolvedAudioDevice(
                deviceID: defaultDeviceID,
                savedUID: nil,
                displayName: "System Default",
                isFallback: false
            )
        }

        if let device = devices.first(where: { $0.uid == savedUID }) {
            return ResolvedAudioDevice(
                deviceID: device.id,
                savedUID: savedUID,
                displayName: device.name,
                isFallback: false
            )
        }

        return ResolvedAudioDevice(
            deviceID: defaultDeviceID,
            savedUID: savedUID,
            displayName: "System Default",
            isFallback: true
        )
    }
}

struct AudioDeviceCatalog {
    func inputDevices() -> [AudioInputDevice] {
        allDeviceIDs()
            .filter(hasInputStreams)
            .compactMap { id in
                guard
                    let uid = stringProperty(
                        deviceID: id,
                        selector: kAudioDevicePropertyDeviceUID
                    ),
                    let name = stringProperty(
                        deviceID: id,
                        selector: kAudioObjectPropertyName
                    )
                else {
                    return nil
                }
                return AudioInputDevice(id: id, uid: uid, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    func resolve(savedUID: String?) -> ResolvedAudioDevice {
        AudioDeviceSelection.resolve(
            savedUID: savedUID,
            devices: inputDevices(),
            defaultDeviceID: defaultInputDeviceID()
        )
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else {
            return []
        }
        return devices
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &size
        ) == noErr && size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private func stringProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}
