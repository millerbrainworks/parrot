import Foundation

enum EscapeDisposition: Equatable {
    case passThrough
    case cancelAndConsume
    case consume
}

enum FnDisposition: Equatable {
    case none
    case start
    case finish
}

struct HotkeyEventPolicy {
    var cancellationEnabled = false
    var recordingEnabled = false
    private var consumedKeyDown = false
    private var doubleTap = DoubleTapRecognizer(maxInterval: 0.35)
    private var lastStartTimestamp: TimeInterval?

    mutating func fnReleased(at timestamp: TimeInterval) -> FnDisposition {
        if recordingEnabled {
            guard lastStartTimestamp != timestamp else { return .none }
            return .finish
        }

        guard doubleTap.registerTap(at: timestamp) else { return .none }
        lastStartTimestamp = timestamp
        return .start
    }

    mutating func escapeKeyDown() -> EscapeDisposition {
        guard cancellationEnabled else { return .passThrough }
        guard !consumedKeyDown else { return .consume }
        consumedKeyDown = true
        return .cancelAndConsume
    }

    mutating func escapeKeyUp() -> EscapeDisposition {
        guard consumedKeyDown else { return .passThrough }
        consumedKeyDown = false
        return .consume
    }
}
