enum EscapeDisposition: Equatable {
    case passThrough
    case cancelAndConsume
    case consume
}

struct HotkeyEventPolicy {
    var cancellationEnabled = false
    private var consumedKeyDown = false

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
