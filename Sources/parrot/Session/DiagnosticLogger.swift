import Foundation

struct DiagnosticLogger {
    private let sink: (String) -> Void

    init(sink: @escaping (String) -> Void = DiagnosticLogger.standardErrorSink) {
        self.sink = sink
    }

    func message(_ message: String) {
        sink(message)
    }

    func captureCompleted(duration: TimeInterval, rms: Float) {
        sink(String(format: "captured %.2fs · rms %.3f", duration, rms))
    }

    func transcriptionCompleted(duration: TimeInterval) {
        sink(String(format: "transcription completed in %.2fs", duration))
    }

    private static func standardErrorSink(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
