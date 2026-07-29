import Foundation

struct DoubleTapRecognizer {
    let maxInterval: TimeInterval
    private var previousTap: TimeInterval?

    init(maxInterval: TimeInterval) {
        self.maxInterval = maxInterval
    }

    mutating func registerTap(at timestamp: TimeInterval) -> Bool {
        guard let previousTap else {
            self.previousTap = timestamp
            return false
        }

        let interval = timestamp - previousTap
        if interval >= 0, interval <= maxInterval {
            self.previousTap = nil
            return true
        }

        self.previousTap = timestamp
        return false
    }
}
