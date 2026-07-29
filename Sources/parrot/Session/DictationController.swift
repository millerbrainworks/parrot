import CoreAudio
import Foundation

struct DictationDependencies {
    let resolveDevice: () -> ResolvedAudioDevice
    let startCapture: (AudioDeviceID?) throws -> Void
    let stopCapture: () -> [Float]
    let transcribe: ([Float]) async throws -> String
    let writeHistory: (String, String) throws -> Void
    let destinationApplication: () -> String
    let injectText: (String) -> Void
    let setRecordingEnabled: (Bool) -> Void
    let present: (DictationState) -> Void
}

@MainActor
final class DictationController {
    private var machine = DictationStateMachine()
    private let dependencies: DictationDependencies
    private let dumpWav: Bool
    private let logger: DiagnosticLogger

    var state: DictationState { machine.state }

    init(
        dependencies: DictationDependencies,
        dumpWav: Bool = false,
        logger: DiagnosticLogger = DiagnosticLogger()
    ) {
        self.dependencies = dependencies
        self.dumpWav = dumpWav
        self.logger = logger
    }

    func handle(_ event: HotkeyMonitor.Event) {
        switch event {
        case .startRecording, .finishRecording:
            execute(machine.handleToggle())
        case .cancelRecording:
            execute(machine.handleCancel())
        }
    }

    private func execute(_ command: DictationCommand) {
        switch command {
        case .none:
            return
        case .startCapture:
            startCapture()
        case .stopCapture:
            stopAndTranscribe()
        case .cancelCapture:
            cancelCapture()
        }
    }

    private func startCapture() {
        let device = dependencies.resolveDevice()
        do {
            try dependencies.startCapture(device.deviceID)
            dependencies.setRecordingEnabled(true)
            dependencies.present(.recording)
            logger.message("recording started · microphone: \(device.displayName)")
        } catch {
            machine.captureFailed()
            dependencies.setRecordingEnabled(false)
            dependencies.present(.idle)
            logger.message("capture failed: \(error)")
        }
    }

    private func stopAndTranscribe() {
        dependencies.setRecordingEnabled(false)
        let samples = dependencies.stopCapture()
        let duration = Double(samples.count) / AudioCapture.targetSampleRate
        logger.captureCompleted(duration: duration, rms: computeRMS(samples))

        if dumpWav, !samples.isEmpty {
            do {
                try WAVWriter.write(
                    samples: samples,
                    sampleRate: Int(AudioCapture.targetSampleRate),
                    to: "/tmp/parrot-last.wav"
                )
                logger.message("debug audio written to /tmp/parrot-last.wav")
            } catch {
                logger.message("debug audio write failed: \(error)")
            }
        }

        guard !samples.isEmpty else {
            machine.emptyCapture()
            dependencies.present(.idle)
            return
        }

        dependencies.present(.transcribing)
        Task { [weak self] in
            await self?.transcribeAndInject(samples)
        }
    }

    private func cancelCapture() {
        dependencies.setRecordingEnabled(false)
        _ = dependencies.stopCapture()
        dependencies.present(.idle)
        logger.message("recording canceled")
    }

    private func transcribeAndInject(_ samples: [Float]) async {
        let started = Date()
        do {
            let rawText = try await dependencies.transcribe(samples)
            let elapsed = Date().timeIntervalSince(started)
            logger.transcriptionCompleted(duration: elapsed)

            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                machine.emptyCapture()
                dependencies.present(.idle)
                return
            }

            machine.transcriptionSucceeded()
            dependencies.present(.injecting)
            let applicationName = dependencies.destinationApplication()

            do {
                try dependencies.writeHistory(text, applicationName)
            } catch {
                logger.message("history write failed: \(error)")
            }

            dependencies.injectText(text)
            machine.finish()
            dependencies.present(.idle)
        } catch {
            machine.transcriptionFailed()
            dependencies.present(.idle)
            logger.message("transcription failed: \(error)")
        }
    }
}
