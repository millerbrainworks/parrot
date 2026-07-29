enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case injecting
}

enum DictationCommand: Equatable {
    case none
    case startCapture
    case stopCapture
    case cancelCapture
}

struct DictationStateMachine {
    private(set) var state: DictationState = .idle

    mutating func handleToggle() -> DictationCommand {
        switch state {
        case .idle:
            state = .recording
            return .startCapture
        case .recording:
            state = .transcribing
            return .stopCapture
        case .transcribing, .injecting:
            return .none
        }
    }

    mutating func handleCancel() -> DictationCommand {
        guard state == .recording else { return .none }
        state = .idle
        return .cancelCapture
    }

    mutating func transcriptionSucceeded() {
        guard state == .transcribing else { return }
        state = .injecting
    }

    mutating func captureFailed() {
        state = .idle
    }

    mutating func transcriptionFailed() {
        state = .idle
    }

    mutating func emptyCapture() {
        state = .idle
    }

    mutating func finish() {
        state = .idle
    }
}
