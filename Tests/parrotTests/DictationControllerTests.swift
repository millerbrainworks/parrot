import CoreAudio
import Foundation
import XCTest
@testable import parrot

@MainActor
final class DictationControllerTests: XCTestCase {
    func testStartAndCancelControlsCaptureAndEscape() {
        var startedDevice: AudioDeviceID?
        var stopCount = 0
        var cancellationValues: [Bool] = []
        var presentations: [DictationState] = []
        let controller = makeController(
            startCapture: { startedDevice = $0 },
            stopCapture: {
                stopCount += 1
                return [0.1]
            },
            setRecordingEnabled: { cancellationValues.append($0) },
            present: { presentations.append($0) }
        )

        controller.handle(.startRecording)
        XCTAssertEqual(controller.state, .recording)
        XCTAssertEqual(startedDevice, 42)

        controller.handle(.cancelRecording)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(cancellationValues, [true, false])
        XCTAssertEqual(presentations, [.recording, .idle])
    }

    func testStopWritesHistoryBeforeInjecting() async {
        let injected = expectation(description: "text injected")
        var operations: [String] = []
        let controller = makeController(
            stopCapture: { [0.1, 0.2] },
            transcribe: { _, _ in "Draft the release notes." },
            writeHistory: { text, app in
                operations.append("history:\(app):\(text)")
            },
            injectText: { text in
                operations.append("inject:\(text)")
                injected.fulfill()
            }
        )

        controller.handle(.startRecording)
        controller.handle(.finishRecording)
        await fulfillment(of: [injected], timeout: 1)

        XCTAssertEqual(
            operations,
            [
                "history:Codex:Draft the release notes.",
                "inject:Draft the release notes.",
            ]
        )
        XCTAssertEqual(controller.state, .idle)
    }

    func testHistoryFailureStillInjectsText() async {
        let injected = expectation(description: "text injected")
        var inserted: String?
        let controller = makeController(
            stopCapture: { [0.1] },
            transcribe: { _, _ in "Recoverable text" },
            writeHistory: { _, _ in throw CocoaError(.fileWriteUnknown) },
            injectText: {
                inserted = $0
                injected.fulfill()
            }
        )

        controller.handle(.startRecording)
        controller.handle(.finishRecording)
        await fulfillment(of: [injected], timeout: 1)

        XCTAssertEqual(inserted, "Recoverable text")
        XCTAssertEqual(controller.state, .idle)
    }

    func testEmptyTranscriptWritesAndInjectsNothing() async {
        let idle = expectation(description: "returned idle")
        var historyCount = 0
        var injectionCount = 0
        let controller = makeController(
            stopCapture: { [0.1] },
            transcribe: { _, _ in "  \n" },
            writeHistory: { _, _ in historyCount += 1 },
            injectText: { _ in injectionCount += 1 },
            present: { state in
                if state == .idle { idle.fulfill() }
            }
        )

        controller.handle(.startRecording)
        controller.handle(.finishRecording)
        await fulfillment(of: [idle], timeout: 1)

        XCTAssertEqual(historyCount, 0)
        XCTAssertEqual(injectionCount, 0)
        XCTAssertEqual(controller.state, .idle)
    }

    func testProcessesLatestDictionaryBeforeHistoryAndInjection() async {
        let injected = expectation(description: "processed text injected")
        var vocabulary: [String] = []
        var warnings: [String?] = []
        var operations: [String] = []
        let dictionary = PersonalDictionary(
            version: 1,
            terms: ["Arcqtype"],
            replacements: [
                .init(canonical: "Arcqtype", variants: ["archetype"]),
            ],
            fillerWords: ["um"]
        )
        let controller = makeController(
            stopCapture: { [0.1] },
            loadDictionary: {
                DictionaryLoadResult(
                    dictionary: dictionary,
                    warning: "Personal Dictionary Needs Attention"
                )
            },
            transcribe: { _, terms in
                vocabulary = terms
                return "Um, archetype."
            },
            writeHistory: { text, _ in operations.append("history:\(text)") },
            injectText: {
                operations.append("inject:\($0)")
                injected.fulfill()
            },
            dictionaryWarningChanged: { warnings.append($0) }
        )

        controller.handle(.startRecording)
        controller.handle(.finishRecording)
        await fulfillment(of: [injected], timeout: 1)

        XCTAssertEqual(vocabulary, ["Arcqtype"])
        XCTAssertEqual(operations, ["history:Arcqtype.", "inject:Arcqtype."])
        XCTAssertEqual(warnings, ["Personal Dictionary Needs Attention"])
    }

    func testCorrectionObservationIsBoundedAroundInsertion() async {
        let injected = expectation(description: "observation began")
        var operations: [String] = []
        let controller = makeController(
            stopCapture: { [0.1] },
            transcribe: { _, _ in "Fresh text" },
            injectText: { text in operations.append("inject:\(text)") },
            prepareCorrectionObservation: {
                operations.append("prepare:\($0)")
            },
            beginCorrectionObservation: {
                operations.append("begin")
                injected.fulfill()
            },
            cancelCorrectionObservation: {
                operations.append("cancel")
            }
        )

        controller.handle(.startRecording)
        controller.handle(.finishRecording)
        await fulfillment(of: [injected], timeout: 1)

        XCTAssertEqual(
            operations,
            ["cancel", "prepare:Fresh text", "inject:Fresh text", "begin"]
        )
    }

    private func makeController(
        startCapture: @escaping (AudioDeviceID?) throws -> Void = { _ in },
        stopCapture: @escaping () -> [Float] = { [] },
        loadDictionary: @escaping () -> DictionaryLoadResult = {
            DictionaryLoadResult(dictionary: .starter, warning: nil)
        },
        transcribe: @escaping ([Float], [String]) async throws -> String = { _, _ in "" },
        writeHistory: @escaping (String, String) throws -> Void = { _, _ in },
        injectText: @escaping (String) -> Void = { _ in },
        setRecordingEnabled: @escaping (Bool) -> Void = { _ in },
        dictionaryWarningChanged: @escaping (String?) -> Void = { _ in },
        prepareCorrectionObservation: @escaping (String) -> Void = { _ in },
        beginCorrectionObservation: @escaping () -> Void = {},
        cancelCorrectionObservation: @escaping () -> Void = {},
        present: @escaping (DictationState) -> Void = { _ in }
    ) -> DictationController {
        DictationController(
            dependencies: DictationDependencies(
                resolveDevice: {
                    ResolvedAudioDevice(
                        deviceID: 42,
                        savedUID: nil,
                        displayName: "System Default",
                        isFallback: false
                    )
                },
                startCapture: startCapture,
                stopCapture: stopCapture,
                loadDictionary: loadDictionary,
                transcribe: transcribe,
                processTranscript: { text, dictionary in
                    TranscriptProcessor().process(text, using: dictionary)
                },
                writeHistory: writeHistory,
                destinationApplication: { "Codex" },
                injectText: injectText,
                setRecordingEnabled: setRecordingEnabled,
                dictionaryWarningChanged: dictionaryWarningChanged,
                prepareCorrectionObservation: prepareCorrectionObservation,
                beginCorrectionObservation: beginCorrectionObservation,
                cancelCorrectionObservation: cancelCorrectionObservation,
                present: present
            ),
            logger: DiagnosticLogger { _ in }
        )
    }
}
