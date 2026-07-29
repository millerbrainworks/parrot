struct MenuBarModel: Equatable {
    var state: DictationState
    var microphoneName: String
    var microphoneFallback: Bool

    var stateTitle: String {
        switch state {
        case .idle:
            return "Idle — double-tap Fn to dictate"
        case .recording:
            return "● Recording — double-tap Fn to finish"
        case .transcribing:
            return "Transcribing…"
        case .injecting:
            return "Inserting…"
        }
    }

    var microphoneTitle: String {
        microphoneFallback ? "\(microphoneName) ⚠" : microphoneName
    }

    var canChangeMicrophone: Bool {
        state == .idle
    }
}
