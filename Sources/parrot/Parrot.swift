import AppKit
import ArgumentParser
import Foundation
import WhisperKit

@main
struct Parrot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parrot",
        abstract: "Minimal macOS dictation daemon. Double-tap Fn to start; tap Fn to finish.",
        subcommands: [Run.self, Setup.self, Doctor.self, Models.self, Install.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the daemon (default)."
    )

    @Flag(name: .long, help: "Skip permission checks at startup.")
    var skipDoctor: Bool = false

    @Flag(name: .long, help: "Print every keyboard event the tap sees (debug).")
    var debugHotkey: Bool = false

    @Flag(name: .long, help: "Write each capture to /tmp/parrot-last.wav for inspection.")
    var dumpWav: Bool = false

    @Flag(name: .long, help: "Disable the on-screen recording overlay.")
    var noOverlay: Bool = false

    @Option(name: .long, help: "Model id to use. Defaults to the recommended model.")
    var model: String?

    func run() throws {
        if !skipDoctor {
            let checks = DoctorReport.run()
            if !DoctorReport.allOK(checks) {
                FileHandle.standardError.write(Data("startup checks failed:\n".utf8))
                DoctorReport.print(checks)
                FileHandle.standardError.write(Data("\nfix the above or pass --skip-doctor\n".utf8))
                throw ExitCode(1)
            }
        }

        let chosenModel: TranscriptionModel
        if let id = model {
            guard let m = ModelRegistry.find(id) else {
                FileHandle.standardError.write(Data("unknown model: \(id)\n".utf8))
                FileHandle.standardError.write(Data("run `parrot models list` to see options.\n".utf8))
                throw ExitCode(1)
            }
            chosenModel = m
        } else {
            guard let m = ModelRegistry.recommended() else {
                FileHandle.standardError.write(Data("no models registered\n".utf8))
                throw ExitCode(1)
            }
            chosenModel = m
        }

        let transcriber = WhisperKitTranscriber(model: chosenModel)
        let warmupSemaphore = DispatchSemaphore(value: 0)
        var warmupError: Error?
        Task.detached {
            do {
                try await transcriber.warmUp()
            } catch {
                warmupError = error
            }
            warmupSemaphore.signal()
        }
        warmupSemaphore.wait()
        if let warmupError {
            FileHandle.standardError.write(Data("warmup failed: \(warmupError)\n".utf8))
            throw ExitCode(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let monitor = HotkeyMonitor(debug: debugHotkey)
        let capture = AudioCapture()
        let dumpWav = self.dumpWav
        let overlay: RecordingOverlay? = noOverlay ? nil : MainActor.assumeIsolated { RecordingOverlay() }
        if let overlay {
            capture.onLevel = { level in overlay.pushLevel(level) }
        }
        let historyWriter = HistoryWriter()
        let dictionaryStore = PersonalDictionaryStore()
        let transcriptProcessor = TranscriptProcessor()
        let preferencesStore = PreferencesStore()
        let deviceCatalog = AudioDeviceCatalog()
        let logger = DiagnosticLogger()
        let correctionObserver = MainActor.assumeIsolated {
            CorrectionObserver()
        }
        let learningPopover = MainActor.assumeIsolated {
            LearningPopoverController()
        }
        let menuBar = MainActor.assumeIsolated {
            MenuBarController(
                modelID: chosenModel.id,
                deviceCatalog: deviceCatalog,
                preferencesStore: preferencesStore,
                historyWriter: historyWriter,
                dictionaryStore: dictionaryStore,
                logger: logger
            )
        }
        let controller = MainActor.assumeIsolated {
            DictationController(
                dependencies: DictationDependencies(
                    resolveDevice: {
                        let preferences: ParrotPreferences
                        do {
                            preferences = try preferencesStore.load()
                        } catch {
                            logger.message("preferences load failed: \(error)")
                            preferences = ParrotPreferences()
                        }
                        return deviceCatalog.resolve(savedUID: preferences.microphoneUID)
                    },
                    startCapture: { deviceID in
                        try capture.start(deviceID: deviceID)
                    },
                    stopCapture: {
                        capture.stop()
                    },
                    loadDictionary: {
                        dictionaryStore.loadUsingFallback()
                    },
                    transcribe: { samples, vocabulary in
                        try await transcriber.transcribe(
                            samples,
                            vocabulary: vocabulary
                        )
                    },
                    processTranscript: { text, dictionary in
                        transcriptProcessor.process(text, using: dictionary)
                    },
                    writeHistory: { text, applicationName in
                        _ = try historyWriter.append(
                            text: text,
                            applicationName: applicationName
                        )
                    },
                    destinationApplication: {
                        DestinationApplication.currentName()
                    },
                    prepareInsertion: { text in
                        InsertionBoundaryPolicy().prepare(
                            text,
                            context: AccessibilityInsertionContextReader().read()
                        )
                    },
                    injectText: { text in
                        TextInjector.inject(text)
                    },
                    setRecordingEnabled: { enabled in
                        monitor.setRecordingEnabled(enabled)
                    },
                    dictionaryWarningChanged: { warning in
                        menuBar.setDictionaryWarning(warning)
                    },
                    prepareCorrectionObservation: { text in
                        correctionObserver.prepare(text: text)
                    },
                    beginCorrectionObservation: {
                        correctionObserver.begin { proposal in
                            guard let anchor = menuBar.learningAnchor else {
                                return
                            }
                            learningPopover.present(
                                proposal,
                                relativeTo: anchor
                            ) {
                                do {
                                    try dictionaryStore.learn(
                                        variant: proposal.original,
                                        canonical: proposal.corrected
                                    )
                                    menuBar.setDictionaryWarning(nil)
                                } catch {
                                    menuBar.setDictionaryWarning(
                                        "Personal Dictionary Needs Attention"
                                    )
                                    logger.message("personal dictionary learning failed")
                                }
                            }
                        }
                    },
                    cancelCorrectionObservation: {
                        correctionObserver.cancel()
                        learningPopover.dismiss()
                    },
                    present: { state in
                        menuBar.setState(state)
                        switch state {
                        case .recording:
                            overlay?.show(.recording)
                        case .transcribing:
                            overlay?.hide()
                        case .injecting:
                            break
                        case .idle:
                            overlay?.hide()
                        }
                    }
                ),
                dumpWav: dumpWav,
                logger: logger
            )
        }
        MainActor.assumeIsolated {
            overlay?.setActionHandler { [weak controller] action in
                switch action {
                case .cancel:
                    controller?.handle(.cancelRecording)
                case .finish:
                    controller?.handle(.finishRecording)
                }
            }
        }

        do {
            try monitor.start { event in
                Task { @MainActor in
                    controller.handle(event)
                }
            }
        } catch {
            FileHandle.standardError.write(Data("failed to register hotkey tap: \(error)\n".utf8))
            FileHandle.standardError.write(Data("run `parrot setup` to configure permissions.\n".utf8))
            throw ExitCode(1)
        }

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            FileHandle.standardError.write(Data("\nshutting down\n".utf8))
            monitor.stop()
            NSApp.terminate(nil)
        }
        sigint.resume()
        signal(SIGINT, SIG_IGN)

        FileHandle.standardError.write(
            Data("listening for fn double-tap start and single-tap finish · model: \(chosenModel.id) · ^C to quit\n".utf8)
        )
        app.run()
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, accessibility, and Fn key configuration."
    )

    func run() throws {
        let checks = DoctorReport.run()
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage transcription models.",
        subcommands: [List.self, Download.self]
    )

    struct List: ParsableCommand {
        func run() throws {
            for m in ModelRegistry.shared {
                let star = m.recommended ? "★" : " "
                let id = m.id.padding(toLength: 26, withPad: " ", startingAt: 0)
                let langs = "[\(m.languages.joined(separator: ","))]"
                    .padding(toLength: 9, withPad: " ", startingAt: 0)
                let size = String(format: "%5d MB", m.sizeMB)
                print("\(star) \(id) \(size)  \(langs)  \(m.displayName)")
            }
        }
    }

    struct Download: ParsableCommand {
        @Argument(help: "Model id to download.") var id: String

        func run() throws {
            guard let m = ModelRegistry.find(id) else {
                print("unknown model: \(id)")
                throw ExitCode(1)
            }
            let t = WhisperKitTranscriber(model: m)

            let sem = DispatchSemaphore(value: 0)
            var capturedError: Error?
            Task.detached {
                do { try await t.warmUp() } catch { capturedError = error }
                sem.signal()
            }
            sem.wait()
            if let e = capturedError { throw e }
        }
    }
}
