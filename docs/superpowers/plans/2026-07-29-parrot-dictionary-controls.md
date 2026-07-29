# Parrot Dictionary and Recording Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add single-tap recording completion, a clickable 96-by-20 recording bar, private personal vocabulary processing, and explicitly confirmed correction learning to the installed Parrot service.

**Architecture:** Keep `DictationController` as the only session orchestrator. Add pure gesture, dictionary, transcript-processing, and correction-diff units around it; keep AppKit/Accessibility adapters thin and injected so behavior is testable without live global input. Reload the JSON dictionary at each transcription, optionally pass its terms to WhisperKit prompt tokens, process final text before history and insertion, and observe only the newly inserted Accessibility range for assisted learning.

**Tech Stack:** Swift 5.9, Swift Package Manager, XCTest, AppKit/SwiftUI, macOS Accessibility APIs, CoreGraphics event taps, WhisperKit.

---

## File structure

Create:

- `Sources/parrot/Dictionary/PersonalDictionary.swift` — Codable schema,
  validation, and starter vocabulary.
- `Sources/parrot/Dictionary/PersonalDictionaryStore.swift` — private file
  creation, reload, invalid-file fallback, and atomic learning merges.
- `Sources/parrot/Dictionary/TranscriptProcessor.swift` — deterministic
  filler, replacement, term, punctuation, and whitespace processing.
- `Sources/parrot/Learning/CorrectionDiff.swift` — pure high-confidence
  single-substitution detection.
- `Sources/parrot/Learning/CorrectionObserver.swift` — bounded
  Accessibility observation of only the freshly inserted range.
- `Sources/parrot/UI/LearningPopoverController.swift` — 30-second
  menu-bar-anchored Learn/Ignore confirmation UI.
- `Tests/parrotTests/PersonalDictionaryStoreTests.swift`
- `Tests/parrotTests/TranscriptProcessorTests.swift`
- `Tests/parrotTests/CorrectionDiffTests.swift`

Modify:

- `Sources/parrot/Input/HotkeyEventPolicy.swift` — state-dependent Fn policy.
- `Sources/parrot/Input/HotkeyMonitor.swift` — emit distinct start, finish, and
  cancel events.
- `Sources/parrot/Session/DictationController.swift` — load/process the
  dictionary and begin bounded correction observation after insertion.
- `Sources/parrot/Transcription/Transcriber.swift` — accept optional
  vocabulary terms.
- `Sources/parrot/Transcription/WhisperKitTranscriber.swift` — encode prompt
  tokens and pass `DecodingOptions`.
- `Sources/parrot/UI/RecordingOverlay.swift` — interactive 96-by-20 panel with
  cancel and finish callbacks.
- `Sources/parrot/UI/MenuBarController.swift` — dictionary open/warning item
  and popover anchor.
- `Sources/parrot/UI/MenuBarModel.swift` — recording single-tap copy and
  dictionary warning state.
- `Sources/parrot/Parrot.swift` — compose the new stores, processor, observer,
  popover, and overlay actions.
- `Tests/parrotTests/HotkeyEventPolicyTests.swift`
- `Tests/parrotTests/DictationControllerTests.swift`
- `Tests/parrotTests/MenuBarModelTests.swift`
- `README.md` — describe controls, dictionary location/schema, filler policy,
  and confirmed learning.

### Task 1: State-dependent Fn gestures

**Files:**

- Modify: `Sources/parrot/Input/HotkeyEventPolicy.swift`
- Modify: `Sources/parrot/Input/HotkeyMonitor.swift`
- Modify: `Sources/parrot/Session/DictationController.swift`
- Test: `Tests/parrotTests/HotkeyEventPolicyTests.swift`
- Test: `Tests/parrotTests/DictationControllerTests.swift`

- [x] **Step 1: Write failing gesture-policy tests**

Add tests that drive release timestamps directly:

```swift
func testIdleRequiresDoubleTapAndStartingTapCannotAlsoFinish() {
    var policy = HotkeyEventPolicy()
    XCTAssertEqual(policy.fnReleased(at: 1.00), .none)
    XCTAssertEqual(policy.fnReleased(at: 1.20), .start)
    policy.recordingEnabled = true
    XCTAssertEqual(policy.fnReleased(at: 1.20), .none)
    XCTAssertEqual(policy.fnReleased(at: 1.60), .finish)
}

func testRecordingUsesOneNewTapToFinish() {
    var policy = HotkeyEventPolicy()
    policy.recordingEnabled = true
    XCTAssertEqual(policy.fnReleased(at: 2.0), .finish)
}
```

- [x] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
swift test --filter HotkeyEventPolicyTests
```

Expected: compilation fails because `FnDisposition`, `recordingEnabled`, and
`fnReleased(at:)` do not exist.

- [x] **Step 3: Implement the pure Fn policy and distinct monitor events**

Add:

```swift
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
            if lastStartTimestamp == timestamp { return .none }
            return .finish
        }
        if doubleTap.registerTap(at: timestamp) {
            lastStartTimestamp = timestamp
            return .start
        }
        return .none
    }

    // Retain the existing escapeKeyDown/escapeKeyUp behavior.
}
```

Change `HotkeyMonitor.Event` to `.startRecording`, `.finishRecording`, and
`.cancelRecording`. On each Fn release, emit the action returned by
`eventPolicy.fnReleased(at:)`. Replace `setCancellationEnabled(_:)` with
`setRecordingEnabled(_:)`, which updates both escape and Fn recording state
under the existing lock. Map start and finish to the existing state machine's
toggle command inside `DictationController`.

- [x] **Step 4: Run gesture and controller tests and confirm GREEN**

Run:

```bash
swift test --filter HotkeyEventPolicyTests
swift test --filter DictationControllerTests
```

Expected: both suites pass and a new controller test proves start followed by
finish reaches transcription.

- [x] **Step 5: Commit**

```bash
git add Sources/parrot/Input Sources/parrot/Session/DictationController.swift Tests/parrotTests/HotkeyEventPolicyTests.swift Tests/parrotTests/DictationControllerTests.swift
git commit -m "feat: finish recording with one fn tap"
```

### Task 2: Personal dictionary schema and private store

**Files:**

- Create: `Sources/parrot/Dictionary/PersonalDictionary.swift`
- Create: `Sources/parrot/Dictionary/PersonalDictionaryStore.swift`
- Create: `Tests/parrotTests/PersonalDictionaryStoreTests.swift`

- [x] **Step 1: Write failing store tests**

Cover first-use creation, `0700` directory and `0600` file permissions, exact
starter replacements, reload after external edit, invalid JSON fallback
without overwrite, validation of blank/duplicate fields, and atomic learned
variant merge:

```swift
func testInvalidEditUsesLastValidDictionaryWithoutOverwritingFile() throws {
    let root = temporaryRoot()
    let store = PersonalDictionaryStore(rootDirectory: root)
    let first = try store.load()
    try Data("{broken".utf8).write(to: store.fileURL)

    let fallback = store.loadUsingFallback()

    XCTAssertEqual(fallback.dictionary, first)
    XCTAssertNotNil(fallback.warning)
    XCTAssertEqual(try String(contentsOf: store.fileURL), "{broken")
}

func testLearningMergesVariantWithoutDuplicates() throws {
    let store = PersonalDictionaryStore(rootDirectory: temporaryRoot())
    _ = try store.load()
    try store.learn(variant: "ark type", canonical: "Arcqtype")
    try store.learn(variant: "ARK TYPE", canonical: "Arcqtype")

    let arcqtype = try store.load().replacements.first {
        $0.canonical == "Arcqtype"
    }
    XCTAssertEqual(arcqtype?.variants.filter {
        $0.caseInsensitiveCompare("ark type") == .orderedSame
    }.count, 1)
}
```

- [x] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
swift test --filter PersonalDictionaryStoreTests
```

Expected: compilation fails because the dictionary types do not exist.

- [x] **Step 3: Implement schema, starter data, validation, and storage**

Define:

```swift
struct DictionaryReplacement: Codable, Equatable {
    var canonical: String
    var variants: [String]
}

struct PersonalDictionary: Codable, Equatable {
    var version: Int
    var terms: [String]
    var replacements: [DictionaryReplacement]
    var fillerWords: [String]

    static let starter = PersonalDictionary(
        version: 1,
        terms: PersonalDictionary.starterTerms,
        replacements: PersonalDictionary.starterReplacements,
        fillerWords: ["um", "uh", "erm", "ah"]
    )
}

struct DictionaryLoadResult {
    let dictionary: PersonalDictionary
    let warning: String?
}
```

Implement `PersonalDictionaryStore` with:

```swift
final class PersonalDictionaryStore {
    let rootDirectory: URL
    var fileURL: URL {
        rootDirectory.appendingPathComponent("personal-dictionary.json")
    }

    func load() throws -> PersonalDictionary
    func loadUsingFallback() -> DictionaryLoadResult
    func learn(variant: String, canonical: String) throws
}
```

Encode the complete non-email starter term list and explicit replacements from
the approved spec. Use sorted-key pretty JSON with a trailing newline. Create
the root with `0700`, write to a same-directory temporary file with `0600`,
then replace or move atomically. Reject unsupported versions, blank canonical
values, empty variants, and blank fillers. Preserve the last valid in-memory
value on read failure.

- [x] **Step 4: Run store tests and confirm GREEN**

Run:

```bash
swift test --filter PersonalDictionaryStoreTests
```

Expected: all store tests pass.

- [x] **Step 5: Commit**

```bash
git add Sources/parrot/Dictionary Tests/parrotTests/PersonalDictionaryStoreTests.swift
git commit -m "feat: add private personal dictionary"
```

### Task 3: Deterministic transcript processing

**Files:**

- Create: `Sources/parrot/Dictionary/TranscriptProcessor.swift`
- Create: `Tests/parrotTests/TranscriptProcessorTests.swift`

- [x] **Step 1: Write failing processing tests**

Use table-driven cases for case-insensitive matching, punctuation, longest
variant first, no substring replacement, filler cleanup, protected
conversational phrases, and empty results:

```swift
func testConservativeFillersAndCanonicalReplacements() {
    let dictionary = PersonalDictionary(
        version: 1,
        terms: ["Arcqtype"],
        replacements: [
            .init(canonical: "Arcqtype", variants: ["archetype", "arc type"])
        ],
        fillerWords: ["um", "uh", "erm", "ah"]
    )
    let processor = TranscriptProcessor()

    XCTAssertEqual(
        processor.process("Um, archetype is, uh, actually useful.", using: dictionary),
        "Arcqtype is actually useful."
    )
    XCTAssertEqual(
        processor.process("Human-like behavior, you know, matters.", using: dictionary),
        "Human-like behavior, you know, matters."
    )
}

func testPhraseBoundariesAndLongestVariantWin() {
    let dictionary = PersonalDictionary(
        version: 1,
        terms: [],
        replacements: [
            .init(canonical: "ARQ Score", variants: ["arq score"]),
            .init(canonical: "ARQ", variants: ["arq"])
        ],
        fillerWords: []
    )
    XCTAssertEqual(
        TranscriptProcessor().process("Show arq score, not marquee.", using: dictionary),
        "Show ARQ Score, not marquee."
    )
}
```

- [x] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
swift test --filter TranscriptProcessorTests
```

Expected: compilation fails because `TranscriptProcessor` does not exist.

- [x] **Step 3: Implement boundary-aware cleanup**

Implement:

```swift
struct TranscriptProcessor {
    func process(_ rawText: String, using dictionary: PersonalDictionary) -> String {
        var text = rawText
        text = removeFillers(from: text, words: dictionary.fillerWords)
        text = applyReplacements(to: text, replacements: dictionary.replacements)
        text = normalizeTerms(in: text, terms: dictionary.terms)
        text = repairWhitespace(in: text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

Build escaped `NSRegularExpression` patterns sorted by descending variant
length. Treat an alphanumeric character on either side as a failed boundary,
including variants with punctuation such as `.env`. Remove a filler plus one
adjacent comma only when that comma becomes orphaned. Repair spaces before
`. , ! ? ; :`, collapse repeated horizontal whitespace, and preserve line
breaks only if present in the raw transcript.

- [x] **Step 4: Run processing tests and confirm GREEN**

Run:

```bash
swift test --filter TranscriptProcessorTests
```

Expected: all processing tests pass.

- [x] **Step 5: Commit**

```bash
git add Sources/parrot/Dictionary/TranscriptProcessor.swift Tests/parrotTests/TranscriptProcessorTests.swift
git commit -m "feat: process personal vocabulary and fillers"
```

### Task 4: Vocabulary-aware transcription and processed insertion

**Files:**

- Modify: `Sources/parrot/Transcription/Transcriber.swift`
- Modify: `Sources/parrot/Transcription/WhisperKitTranscriber.swift`
- Modify: `Sources/parrot/Session/DictationController.swift`
- Modify: `Tests/parrotTests/DictationControllerTests.swift`

- [x] **Step 1: Write failing controller tests**

Add a test proving dictionary reload happens per transcription and only final
processed text reaches history and insertion:

```swift
func testProcessesLatestDictionaryBeforeHistoryAndInjection() async {
    let injected = expectation(description: "processed text injected")
    var vocabulary: [String] = []
    var operations: [String] = []
    let controller = makeController(
        loadDictionary: {
            DictionaryLoadResult(
                dictionary: .init(
                    version: 1,
                    terms: ["Arcqtype"],
                    replacements: [.init(canonical: "Arcqtype", variants: ["archetype"])],
                    fillerWords: ["um"]
                ),
                warning: nil
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
        }
    )

    controller.handle(.startRecording)
    controller.handle(.finishRecording)
    await fulfillment(of: [injected], timeout: 1)

    XCTAssertEqual(vocabulary, ["Arcqtype"])
    XCTAssertEqual(operations, ["history:Arcqtype.", "inject:Arcqtype."])
}
```

- [x] **Step 2: Run controller tests and confirm RED**

Run:

```bash
swift test --filter DictationControllerTests
```

Expected: compilation fails on the new dependency signatures.

- [x] **Step 3: Add vocabulary terms to transcription**

Change:

```swift
protocol Transcriber {
    var modelID: String { get }
    func transcribe(_ audio: [Float], vocabulary: [String]) async throws -> String
}
```

In `WhisperKitTranscriber`, construct prompt text by joining non-empty unique
terms with `", "`, cap encoded prompt tokens to the last 224 tokens, and call:

```swift
let promptTokens = pipeline.tokenizer?.encode(text: promptText)
let options = DecodingOptions(promptTokens: promptTokens.map {
    Array($0.suffix(224))
})
let results: [TranscriptionResult] = try await pipeline.transcribe(
    audioArray: audio,
    decodeOptions: options
)
```

An empty term list passes `nil` prompt tokens. Keep existing non-speech
sanitization.

- [x] **Step 4: Process the dictionary inside session orchestration**

Add `loadDictionary`, `processTranscript`, and `dictionaryWarningChanged`
closures to `DictationDependencies`. Load immediately before calling
`transcribe`, pass `dictionary.terms`, process the raw result, publish the
warning without its contents, and use only processed text for history and
injection. An empty processed result follows the existing empty path.

- [x] **Step 5: Run focused and full tests and confirm GREEN**

Run:

```bash
swift test --filter DictationControllerTests
swift test
```

Expected: controller tests and the complete suite pass.

- [x] **Step 6: Commit**

```bash
git add Sources/parrot/Transcription Sources/parrot/Session/DictationController.swift Tests/parrotTests/DictationControllerTests.swift
git commit -m "feat: apply vocabulary before dictation insertion"
```

### Task 5: Interactive 96-by-20 recording bar

**Files:**

- Modify: `Sources/parrot/UI/RecordingOverlay.swift`
- Modify: `Sources/parrot/Parrot.swift`
- Create: `Tests/parrotTests/RecordingOverlayModelTests.swift`

- [x] **Step 1: Write failing overlay-model callback tests**

Make overlay actions testable without displaying a window:

```swift
@MainActor
func testRecordingActionsCallInjectedHandlers() {
    var actions: [RecordingOverlay.Action] = []
    let model = OverlayModel(onAction: { actions.append($0) })
    model.cancel()
    model.finish()
    XCTAssertEqual(actions, [.cancel, .finish])
}
```

- [x] **Step 2: Run the focused test and confirm RED**

Run:

```bash
swift test --filter RecordingOverlayModelTests
```

Expected: compilation fails because overlay actions and handlers do not exist.

- [x] **Step 3: Implement the non-activating interactive panel**

Give `RecordingOverlay` `onCancel` and `onFinish` closures. Set the panel frame
to exactly `96 × 20`, `panel.ignoresMouseEvents = false`, and keep
`.nonactivatingPanel`. Use a zero-padding `HStack` with 20-point-high controls:

```swift
HStack(spacing: 0) {
    Button(action: model.cancel) {
        Image(systemName: "xmark").foregroundStyle(.red)
    }
    .buttonStyle(.plain)
    .frame(width: 26, height: 20)

    Waveform(levels: model.levels)
        .frame(width: 44, height: 14)

    Button(action: model.finish) {
        Image(systemName: "checkmark").foregroundStyle(.green)
    }
    .buttonStyle(.plain)
    .frame(width: 26, height: 20)
}
.frame(width: 96, height: 20)
.background(Color(red: 16 / 255, green: 18 / 255, blue: 18 / 255))
.clipShape(Capsule())
```

Show the bar only for `.recording`; hide it while transcribing so the two
actions cannot be clicked in a busy state. In `Parrot.swift`, route callbacks
to `controller.handle(.cancelRecording)` and
`controller.handle(.finishRecording)` on the main actor.

- [x] **Step 4: Run focused and full tests and confirm GREEN**

Run:

```bash
swift test --filter RecordingOverlayModelTests
swift test
```

Expected: all tests pass.

- [x] **Step 5: Commit**

```bash
git add Sources/parrot/UI/RecordingOverlay.swift Sources/parrot/Parrot.swift Tests/parrotTests/RecordingOverlayModelTests.swift
git commit -m "feat: add recording bar finish and cancel controls"
```

### Task 6: High-confidence correction proposals

**Files:**

- Create: `Sources/parrot/Learning/CorrectionDiff.swift`
- Create: `Tests/parrotTests/CorrectionDiffTests.swift`

- [x] **Step 1: Write failing correction-diff tests**

```swift
func testFindsOneLocalizedSubstitution() {
    XCTAssertEqual(
        CorrectionDiff.proposal(
            original: "Build the archetype app.",
            corrected: "Build the Arcqtype app."
        ),
        CorrectionProposal(original: "archetype", corrected: "Arcqtype")
    )
}

func testRejectsInsertionDeletionAndMultipleEdits() {
    XCTAssertNil(CorrectionDiff.proposal(original: "hello", corrected: "hello world"))
    XCTAssertNil(CorrectionDiff.proposal(original: "hello world", corrected: "hello"))
    XCTAssertNil(
        CorrectionDiff.proposal(
            original: "red archetype app",
            corrected: "blue Arcqtype tool"
        )
    )
}
```

- [x] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
swift test --filter CorrectionDiffTests
```

Expected: compilation fails because the correction types do not exist.

- [x] **Step 3: Implement the pure proposal detector**

Define:

```swift
struct CorrectionProposal: Equatable {
    let original: String
    let corrected: String
}

enum CorrectionDiff {
    static func proposal(original: String, corrected: String) -> CorrectionProposal?
}
```

Compute the longest equal Unicode-scalar prefix and suffix, then isolate the
changed middles. Require both middles to be non-empty, at most 80 characters,
trimmed on token boundaries, and separated from unchanged alphanumeric text.
Reject changes containing a newline or edits where either middle contains
more than eight whitespace-delimited words. This accepts one localized
substitution while rejecting pure insertions, deletions, and broad rewrites.

- [x] **Step 4: Run correction tests and confirm GREEN**

Run:

```bash
swift test --filter CorrectionDiffTests
```

Expected: all correction-diff tests pass.

- [x] **Step 5: Commit**

```bash
git add Sources/parrot/Learning/CorrectionDiff.swift Tests/parrotTests/CorrectionDiffTests.swift
git commit -m "feat: detect localized dictation corrections"
```

### Task 7: Bounded Accessibility observation and learning popover

**Files:**

- Create: `Sources/parrot/Learning/CorrectionObserver.swift`
- Create: `Sources/parrot/UI/LearningPopoverController.swift`
- Modify: `Sources/parrot/Input/TextInjector.swift`
- Modify: `Sources/parrot/UI/MenuBarController.swift`
- Modify: `Sources/parrot/UI/MenuBarModel.swift`
- Modify: `Sources/parrot/Session/DictationController.swift`
- Modify: `Sources/parrot/Parrot.swift`
- Test: `Tests/parrotTests/MenuBarModelTests.swift`
- Create: `Tests/parrotTests/CorrectionObservationPolicyTests.swift`

- [x] **Step 1: Write failing observation-policy and menu tests**

Extract time, focus, security, and bounds decisions into a pure policy:

```swift
func testObservationExpiresAndRejectsSecureOrChangedFocus() {
    let policy = CorrectionObservationPolicy(timeout: 30)
    XCTAssertFalse(policy.canObserve(elapsed: 31, sameElement: true, secure: false))
    XCTAssertFalse(policy.canObserve(elapsed: 1, sameElement: false, secure: false))
    XCTAssertFalse(policy.canObserve(elapsed: 1, sameElement: true, secure: true))
    XCTAssertTrue(policy.canObserve(elapsed: 1, sameElement: true, secure: false))
}

func testRecordingMenuExplainsSingleTapFinishAndDictionaryWarning() {
    let model = MenuBarModel(
        state: .recording,
        microphoneName: "System Default",
        microphoneFallback: false,
        dictionaryWarning: "Invalid personal dictionary"
    )
    XCTAssertEqual(model.stateTitle, "● Recording — tap Fn to finish")
    XCTAssertTrue(model.showsDictionaryWarning)
}
```

- [x] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
swift test --filter CorrectionObservationPolicyTests
swift test --filter MenuBarModelTests
```

Expected: compilation fails on the new policy and model field.

- [x] **Step 3: Implement bounded Accessibility observation**

Before injection, capture the focused `AXUIElement`, its selected text range,
role/subrole, and insertion start. Reject `AXSecureTextField` and secure
subroles. After injection, poll at 400 milliseconds for at most 30 seconds,
using `kAXSelectedTextRangeAttribute` and
`kAXStringForRangeParameterizedAttribute` only for a range beginning at the
insertion start and ending at the current caret. Never request the element's
complete value. Stop on focus change, new recording, unsupported parameterized
range access, timeout, or proposal emission.

Expose:

```swift
@MainActor
final class CorrectionObserver {
    func prepare(text: String) -> InsertionObservation?
    func begin(
        _ observation: InsertionObservation,
        onProposal: @escaping (CorrectionProposal) -> Void
    )
    func cancel()
}
```

Use a pure `CorrectionObservationPolicy` for elapsed/focus/security decisions.
When the currently observable prefix is shorter than the original insertion,
compare it against candidate original prefixes within 64 characters of the
caret and accept only if exactly one candidate yields the same localized
proposal. This supports corrections that change length without reading beyond
the inserted range.

- [x] **Step 4: Implement the anchored confirmation popover**

Expose the status-item button from `MenuBarController` as the popover anchor.
Build `LearningPopoverController` with a transient SwiftUI/AppKit view:

```swift
@MainActor
func present(
    _ proposal: CorrectionProposal,
    relativeTo anchor: NSView,
    onLearn: @escaping () -> Void
)
```

The popover says `Learn this correction?`, displays escaped original and
corrected phrases, and provides `Ignore` and `Learn` buttons. A 30-second timer
closes it. Learn calls `PersonalDictionaryStore.learn`, refreshes menu warning
state, and never logs proposal content.

Add `Open Personal Dictionary` to the menu. Its action calls `store.load()` to
create the starter if necessary and opens `store.fileURL`. Add a disabled
`Personal Dictionary: Needs Attention ⚠` item only when a content-free warning
is active.

- [x] **Step 5: Wire observation around insertion**

Change text injection orchestration to:

```swift
let observation = dependencies.prepareCorrectionObservation(text)
dependencies.injectText(text)
dependencies.beginCorrectionObservation(observation)
```

Cancel any active observation when a recording begins. If preparation returns
`nil`, insertion remains unchanged. On a proposal, present the popover and
merge only after Learn.

- [x] **Step 6: Run focused and full tests and confirm GREEN**

Run:

```bash
swift test --filter CorrectionObservationPolicyTests
swift test --filter MenuBarModelTests
swift test
```

Expected: all tests pass.

- [x] **Step 7: Commit**

```bash
git add Sources/parrot/Learning Sources/parrot/UI Sources/parrot/Input/TextInjector.swift Sources/parrot/Session/DictationController.swift Sources/parrot/Parrot.swift Tests/parrotTests
git commit -m "feat: confirm learned dictation corrections"
```

### Task 8: Documentation, build, installation, and live verification

**Files:**

- Modify: `README.md`
- Modify if needed: `Sources/parrot/Parrot.swift`

- [x] **Step 1: Update user-facing documentation**

Document:

- double-tap Fn starts; one new Fn tap or `✓` finishes;
- Escape or `×` cancels;
- recording continues through silence;
- `personal-dictionary.json` path and schema;
- starter filler policy and how to edit it;
- corrections require Learn confirmation;
- secure/unsupported fields skip learning; and
- history and diagnostic-log privacy guarantees.

- [x] **Step 2: Run source hygiene and complete tests**

Run:

```bash
git diff --check
swift test
rg -n 'print\\(.*(text|transcript|proposal)|logger\\..*(text|transcript|proposal)' Sources/parrot
```

Expected: no whitespace errors, every test passes, and the content-leak scan
has no unsafe diagnostic logging.

- [x] **Step 3: Build release and sign the exact artifact**

Run:

```bash
swift build -c release
codesign --force --sign - --identifier com.digimata.parrot .build/release/parrot
codesign --verify --verbose=2 .build/release/parrot
```

Expected: release build succeeds and codesign verification reports the binary
is valid on disk.

- [x] **Step 4: Install and restart the existing LaunchAgent**

Run:

```bash
install -m 755 .build/release/parrot /Users/don/.local/bin/parrot
codesign --verify --verbose=2 /Users/don/.local/bin/parrot
launchctl bootout gui/$(id -u) /Users/don/Library/LaunchAgents/com.digimata.parrot.plist
launchctl bootstrap gui/$(id -u) /Users/don/Library/LaunchAgents/com.digimata.parrot.plist
launchctl kickstart -k gui/$(id -u)/com.digimata.parrot
launchctl print gui/$(id -u)/com.digimata.parrot
```

Expected: the installed binary verifies and the service reports a running PID.
If Accessibility or Microphone access is denied after re-signing, stop and ask
the user to approve that exact permission before continuing.

- [x] **Step 5: Verify private files and content-free diagnostics**

Run:

```bash
/Users/don/.local/bin/parrot doctor
stat -f '%Sp %N' '/Users/don/Library/Application Support/Parrot' '/Users/don/Library/Application Support/Parrot/personal-dictionary.json'
tail -80 /tmp/parrot.err.log
```

Expected: doctor reports all checks okay, directory/file modes are private,
and the service log shows readiness without transcript or correction text.

- [ ] **Step 6: Perform live interaction checks**

Verify on the physical Mac:

1. double-tap Fn opens the 96-by-20 recording bar;
2. one new Fn tap finishes and inserts;
3. Escape and `×` cancel;
4. `✓` finishes without stealing cursor focus;
5. saying `um archetype` produces `Arcqtype`;
6. editing a freshly inserted supported-field phrase produces the top-right
   Learn/Ignore popover; and
7. Learn updates JSON while Ignore leaves it unchanged.

- [ ] **Step 7: Commit documentation and any verification fixes**

```bash
git add README.md Sources Tests
git commit -m "docs: explain personal dictation workflow"
```

- [ ] **Step 8: Run final verification**

Run:

```bash
swift test
swift build -c release
git status --short
launchctl print gui/$(id -u)/com.digimata.parrot
```

Expected: tests and release build pass, the worktree is clean, and the
LaunchAgent remains running.
