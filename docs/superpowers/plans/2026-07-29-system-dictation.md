# System-wide Dictation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and install a login-started Parrot daemon with Fn double-tap recording control, Escape cancellation, private daily history, persistent microphone selection, and menu-bar controls.

**Architecture:** Keep Parrot as one Swift executable and extract pure gesture/state/persistence units that can be tested without macOS permissions. The AppKit daemon composes those units with AVAudioEngine, CoreAudio device discovery, WhisperKit, global event taps, history persistence, text injection, and the existing overlay/menu bar.

**Tech Stack:** Swift 5.9, Swift Package Manager, AppKit, SwiftUI, AVFoundation, CoreAudio/AudioToolbox, ApplicationServices, WhisperKit, XCTest, launchd.

---

## File map

- `Package.swift`: add an XCTest target.
- `Sources/parrot/Input/DoubleTapRecognizer.swift`: pure Fn double-tap timing.
- `Sources/parrot/Input/HotkeyMonitor.swift`: emit toggle/cancel gestures and consume Escape only during recording.
- `Sources/parrot/Session/DictationStateMachine.swift`: pure lifecycle transitions and busy-state rejection.
- `Sources/parrot/History/HistoryWriter.swift`: daily private Markdown persistence.
- `Sources/parrot/History/DestinationApplication.swift`: obtain the frontmost app display name.
- `Sources/parrot/Preferences/PreferencesStore.swift`: JSON microphone preference under Application Support.
- `Sources/parrot/Audio/AudioDeviceCatalog.swift`: enumerate CoreAudio inputs and resolve saved/default selection.
- `Sources/parrot/Audio/AudioCapture.swift`: select the requested input device before capture.
- `Sources/parrot/UI/MenuBarController.swift`: state, microphone submenu, history shortcut, permission warning, and deliberate quit.
- `Sources/parrot/Session/DictationController.swift`: orchestrate capture, transcription, history, and injection.
- `Sources/parrot/Parrot.swift`: compose the daemon and remove transcript logging.
- `Sources/parrot/Install.swift`: user-local binary support and launchd behavior.
- `Sources/parrot/Setup.swift`: accurate double-tap and permission guidance.
- `README.md`: customized usage, privacy, history, microphone, and login setup.
- `Tests/parrotTests/*.swift`: pure and filesystem tests.

### Task 1: Test target and double-tap recognizer

**Files:**
- Modify: `Package.swift`
- Create: `Sources/parrot/Input/DoubleTapRecognizer.swift`
- Create: `Tests/parrotTests/DoubleTapRecognizerTests.swift`

- [ ] **Step 1: Add the test target and failing gesture tests**

Add `.testTarget(name: "parrotTests", dependencies: ["parrot"])` to
`Package.swift`, then create:

```swift
import XCTest
@testable import parrot

final class DoubleTapRecognizerTests: XCTestCase {
    func testSecondTapInsideWindowRecognizesAndResets() {
        var recognizer = DoubleTapRecognizer(maxInterval: 0.35)
        XCTAssertFalse(recognizer.registerTap(at: 10.0))
        XCTAssertTrue(recognizer.registerTap(at: 10.34))
        XCTAssertFalse(recognizer.registerTap(at: 10.50))
    }

    func testTapOutsideWindowStartsANewPair() {
        var recognizer = DoubleTapRecognizer(maxInterval: 0.35)
        XCTAssertFalse(recognizer.registerTap(at: 10.0))
        XCTAssertFalse(recognizer.registerTap(at: 10.36))
        XCTAssertTrue(recognizer.registerTap(at: 10.60))
    }
}
```

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter DoubleTapRecognizerTests`

Expected: compilation fails because `DoubleTapRecognizer` does not exist.

- [ ] **Step 3: Implement the pure recognizer**

```swift
struct DoubleTapRecognizer {
    let maxInterval: TimeInterval
    private var previousTap: TimeInterval?

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
```

The explicit assignments ensure a recognized pair resets cleanly.

- [ ] **Step 4: Verify the tests pass**

Run: `swift test --filter DoubleTapRecognizerTests`

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/parrot/Input/DoubleTapRecognizer.swift Tests/parrotTests/DoubleTapRecognizerTests.swift
git commit -m "feat: recognize fn double taps"
```

### Task 2: Dictation lifecycle state machine

**Files:**
- Create: `Sources/parrot/Session/DictationStateMachine.swift`
- Create: `Tests/parrotTests/DictationStateMachineTests.swift`

- [ ] **Step 1: Write failing transition tests**

```swift
import XCTest
@testable import parrot

final class DictationStateMachineTests: XCTestCase {
    func testToggleStartsAndStopsRecording() {
        var machine = DictationStateMachine()
        XCTAssertEqual(machine.handleToggle(), .startCapture)
        XCTAssertEqual(machine.state, .recording)
        XCTAssertEqual(machine.handleToggle(), .stopCapture)
        XCTAssertEqual(machine.state, .transcribing)
    }

    func testCancelOnlyWorksWhileRecording() {
        var machine = DictationStateMachine()
        XCTAssertEqual(machine.handleCancel(), .none)
        _ = machine.handleToggle()
        XCTAssertEqual(machine.handleCancel(), .cancelCapture)
        XCTAssertEqual(machine.state, .idle)
    }

    func testBusyStatesIgnoreGesturesAndCompletionReturnsIdle() {
        var machine = DictationStateMachine()
        _ = machine.handleToggle()
        _ = machine.handleToggle()
        XCTAssertEqual(machine.handleToggle(), .none)
        XCTAssertEqual(machine.handleCancel(), .none)
        machine.transcriptionSucceeded()
        XCTAssertEqual(machine.state, .injecting)
        machine.finish()
        XCTAssertEqual(machine.state, .idle)
    }
}
```

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter DictationStateMachineTests`

Expected: compilation fails because the state machine types do not exist.

- [ ] **Step 3: Implement minimal lifecycle types**

```swift
enum DictationState: Equatable { case idle, recording, transcribing, injecting }
enum DictationCommand: Equatable { case none, startCapture, stopCapture, cancelCapture }

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
        if state == .transcribing { state = .injecting }
    }

    mutating func captureFailed() { state = .idle }
    mutating func transcriptionFailed() { state = .idle }
    mutating func emptyCapture() { state = .idle }
    mutating func finish() { state = .idle }
}
```

These failure methods make every terminal path return to idle.

- [ ] **Step 4: Run lifecycle tests**

Run: `swift test --filter DictationStateMachineTests`

Expected: all transition tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/parrot/Session/DictationStateMachine.swift Tests/parrotTests/DictationStateMachineTests.swift
git commit -m "feat: model dictation session lifecycle"
```

### Task 3: Private daily history

**Files:**
- Create: `Sources/parrot/History/HistoryWriter.swift`
- Create: `Sources/parrot/History/DestinationApplication.swift`
- Create: `Tests/parrotTests/HistoryWriterTests.swift`

- [ ] **Step 1: Write failing history tests**

Use a fixed Gregorian calendar/time zone, a temporary root, and:

```swift
func testAppendCreatesPrivateDatedMarkdown() throws {
    let root = temporaryDirectory()
    let writer = HistoryWriter(rootDirectory: root, calendar: fixedCalendar)
    let date = Date(timeIntervalSince1970: 1_774_805_442)
    let url = try writer.append(
        text: "Draft the release notes.",
        applicationName: "Codex",
        at: date
    )
    XCTAssertTrue(url.path.hasSuffix("/2026/03/2026-03-29.md"))
    let content = try String(contentsOf: url)
    XCTAssertEqual(content, "## 12:37:22 — Codex\n\nDraft the release notes.\n\n")
    XCTAssertEqual(try permissions(url), 0o600)
    XCTAssertEqual(try permissions(url.deletingLastPathComponent()), 0o700)
}

func testBlankTextIsNotWritten() throws {
    XCTAssertNil(try writer.append(text: " \n", applicationName: "Codex", at: date))
}
```

Also test a second append, `Unknown Application`, and Markdown text preservation.

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter HistoryWriterTests`

Expected: compilation fails because `HistoryWriter` does not exist.

- [ ] **Step 3: Implement history persistence**

Implement:

```swift
final class HistoryWriter {
    init(
        rootDirectory: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Parrot/history"),
        calendar: Calendar = .current
    )

    @discardableResult
    func append(
        text: String,
        applicationName: String,
        at date: Date = Date()
    ) throws -> URL?
}
```

Create year/month directories with POSIX permissions `0700`, create files with
`0600`, and perform serialized appends. `DestinationApplication.currentName()`
returns `NSWorkspace.shared.frontmostApplication?.localizedName ??
"Unknown Application"`.

- [ ] **Step 4: Run history tests**

Run: `swift test --filter HistoryWriterTests`

Expected: all history tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/parrot/History Tests/parrotTests/HistoryWriterTests.swift
git commit -m "feat: keep private daily dictation history"
```

### Task 4: Microphone preference and device resolution

**Files:**
- Create: `Sources/parrot/Preferences/PreferencesStore.swift`
- Create: `Sources/parrot/Audio/AudioDeviceCatalog.swift`
- Create: `Tests/parrotTests/PreferencesStoreTests.swift`
- Create: `Tests/parrotTests/AudioDeviceSelectionTests.swift`
- Modify: `Sources/parrot/Audio/AudioCapture.swift`

- [ ] **Step 1: Write failing preference and selection tests**

```swift
func testMicrophoneUIDRoundTrips() throws {
    let url = temporaryDirectory().appendingPathComponent("preferences.json")
    let store = PreferencesStore(url: url)
    try store.save(ParrotPreferences(microphoneUID: "device-123"))
    XCTAssertEqual(try store.load(), ParrotPreferences(microphoneUID: "device-123"))
    XCTAssertEqual(try permissions(url), 0o600)
}

func testMissingSavedDeviceFallsBackWithoutForgettingUID() {
    let result = AudioDeviceSelection.resolve(
        savedUID: "missing",
        devices: [.init(id: 7, uid: "built-in", name: "MacBook Microphone")],
        defaultDeviceID: 7
    )
    XCTAssertEqual(result.deviceID, 7)
    XCTAssertTrue(result.isFallback)
    XCTAssertEqual(result.savedUID, "missing")
}
```

Also test System Default (`savedUID == nil`) and a connected saved device.

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter 'PreferencesStoreTests|AudioDeviceSelectionTests'`

Expected: compilation fails because persistence and device types do not exist.

- [ ] **Step 3: Implement preferences and CoreAudio catalog**

Define:

```swift
struct ParrotPreferences: Codable, Equatable { var microphoneUID: String? }
struct AudioInputDevice: Equatable { let id: AudioDeviceID; let uid: String; let name: String }
struct ResolvedAudioDevice: Equatable {
    let deviceID: AudioDeviceID?
    let savedUID: String?
    let displayName: String
    let isFallback: Bool
}
```

`PreferencesStore` reads/writes JSON under Application Support with private
permissions. `AudioDeviceCatalog` uses CoreAudio property APIs to enumerate
devices with input streams, their UIDs/names, and the current default input.
Keep selection resolution pure and separately tested.

- [ ] **Step 4: Apply the resolved device in AudioCapture**

Change `start()` to `start(deviceID: AudioDeviceID?)`. Before reading the input
format, set `kAudioOutputUnitProperty_CurrentDevice` on the input node's audio
unit when an explicit device ID is supplied. Preserve System Default behavior
when the ID is nil.

- [ ] **Step 5: Run tests and compile the executable**

Run: `swift test`

Expected: all tests pass.

Run: `swift build`

Expected: the executable builds with CoreAudio device selection.

- [ ] **Step 6: Commit**

```bash
git add Sources/parrot/Preferences Sources/parrot/Audio Package.swift Tests/parrotTests
git commit -m "feat: persist and select microphone input"
```

### Task 5: Global toggle and Escape cancellation

**Files:**
- Modify: `Sources/parrot/Input/HotkeyMonitor.swift`
- Create: `Tests/parrotTests/HotkeyEventPolicyTests.swift`

- [ ] **Step 1: Write failing event-policy tests**

Extract a pure `HotkeyEventPolicy` that tracks whether Escape should be
consumed and verifies:

```swift
func testEscapeIsConsumedOnlyWhenCancellationEnabled() {
    var policy = HotkeyEventPolicy()
    XCTAssertEqual(policy.escapeKeyDown(), .passThrough)
    policy.cancellationEnabled = true
    XCTAssertEqual(policy.escapeKeyDown(), .cancelAndConsume)
    policy.cancellationEnabled = false
    XCTAssertEqual(policy.escapeKeyUp(), .consume)
    XCTAssertEqual(policy.escapeKeyDown(), .passThrough)
}
```

- [ ] **Step 2: Verify the policy test fails**

Run: `swift test --filter HotkeyEventPolicyTests`

Expected: compilation fails because `HotkeyEventPolicy` does not exist.

- [ ] **Step 3: Implement policy and update the event tap**

Change monitor events to:

```swift
enum Event { case toggleRecording, cancelRecording }
```

Use `.defaultTap` rather than `.listenOnly`. Feed Fn release timestamps to
`DoubleTapRecognizer(maxInterval: 0.35)`. Return `nil` for Escape down/up when
the policy says consume, emit one cancel event on key-down, and pass all other
events through.

Expose `setCancellationEnabled(_:)` so the session controller can synchronize
Escape handling with the recording state.

- [ ] **Step 4: Run tests and build**

Run: `swift test && swift build`

Expected: tests pass and the global event tap compiles.

- [ ] **Step 5: Commit**

```bash
git add Sources/parrot/Input Tests/parrotTests/HotkeyEventPolicyTests.swift
git commit -m "feat: toggle recording and cancel with escape"
```

### Task 6: Dictation controller and transcript-safe logging

**Files:**
- Create: `Sources/parrot/Session/DictationController.swift`
- Modify: `Sources/parrot/Parrot.swift`
- Modify: `Sources/parrot/UI/RecordingOverlay.swift`
- Create: `Tests/parrotTests/DiagnosticLoggerTests.swift`

- [ ] **Step 1: Write the failing log privacy test**

Define `DiagnosticLogger` around a supplied sink and verify:

```swift
func testTranscriptionCompletionLogsTimingButNotText() {
    var messages: [String] = []
    let logger = DiagnosticLogger { messages.append($0) }
    logger.transcriptionCompleted(duration: 0.42)
    XCTAssertEqual(messages, ["transcription completed in 0.42s"])
    XCTAssertFalse(messages.joined().contains("secret prompt"))
}
```

- [ ] **Step 2: Verify the test fails**

Run: `swift test --filter DiagnosticLoggerTests`

Expected: compilation fails because `DiagnosticLogger` does not exist.

- [ ] **Step 3: Implement orchestration**

`DictationController` owns `DictationStateMachine` and receives the monitor's
toggle/cancel events. It:

- starts capture and enables cancellation;
- stops or cancels capture and disables cancellation;
- moves the overlay/menu through recording and transcribing;
- transcribes stopped nonempty audio asynchronously;
- obtains the destination app name;
- writes history before injection;
- continues injection if history writing fails;
- injects nothing on empty/failed transcription; and
- returns every terminal path to idle.

Inject protocols/closures for capture, transcription, history, destination,
injection, and UI so the state machine remains testable.

- [ ] **Step 4: Replace inline orchestration**

Update `Parrot.swift` to compose `DictationController`, device preferences, and
the monitor. Remove the line that prints transcript text. The release
LaunchAgent must never pass `--dump-wav`.

- [ ] **Step 5: Run tests and build**

Run: `swift test && swift build`

Expected: all tests pass; no production log call accepts transcript text.

Run: `rg -n 'elapsed, text|%@.*text|dump-wav' Sources/parrot`

Expected: no transcript logging; only the opt-in debug flag definition may
mention dump WAV.

- [ ] **Step 6: Commit**

```bash
git add Sources/parrot/Session Sources/parrot/Parrot.swift Sources/parrot/UI/RecordingOverlay.swift Tests/parrotTests
git commit -m "feat: orchestrate private toggle dictation sessions"
```

### Task 7: Menu-bar controls and microphone menu

**Files:**
- Modify: `Sources/parrot/UI/MenuBarController.swift`
- Create: `Tests/parrotTests/MenuBarModelTests.swift`

- [ ] **Step 1: Write failing menu-model tests**

Extract a pure model and test:

```swift
func testUnavailableSavedMicrophoneShowsFallbackWarning() {
    let model = MenuBarModel(
        state: .idle,
        microphoneName: "System Default",
        microphoneFallback: true
    )
    XCTAssertEqual(model.stateTitle, "Idle")
    XCTAssertEqual(model.microphoneTitle, "System Default ⚠")
}
```

Also test Recording and Transcribing titles.

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter MenuBarModelTests`

Expected: compilation fails because `MenuBarModel` does not exist.

- [ ] **Step 3: Expand MenuBarController**

Add state, selected-microphone display, a dynamic microphone submenu,
Open Today's History, Launch at Login status, permission warning/action, and
Quit. Disable microphone choices while recording/transcribing. Selecting a
device updates `PreferencesStore` and the next capture; selecting System
Default saves `nil`.

Quit must terminate successfully so launchd's
`KeepAlive.SuccessfulExit = false` does not restart it.

- [ ] **Step 4: Run tests and build**

Run: `swift test && swift build`

Expected: all tests pass and AppKit menu code compiles.

- [ ] **Step 5: Commit**

```bash
git add Sources/parrot/UI Tests/parrotTests/MenuBarModelTests.swift
git commit -m "feat: add microphone and history menu controls"
```

### Task 8: Setup, installation, documentation, and end-to-end verification

**Files:**
- Modify: `Sources/parrot/Install.swift`
- Modify: `Sources/parrot/Setup.swift`
- Modify: `Sources/parrot/Doctor.swift`
- Modify: `README.md`

- [ ] **Step 1: Update install and setup behavior**

Teach binary resolution to accept `~/.local/bin/parrot`, update setup language
from hold/release to double-tap toggle, and ensure doctor remediation describes
the daemon binary/launcher accurately. Keep:

```swift
"RunAtLoad": true
"KeepAlive": ["SuccessfulExit": false]
```

and never include `--dump-wav`.

- [ ] **Step 2: Update user documentation**

Document double-tap start/stop, Escape cancellation, menu-bar microphone
selection, daily history location and privacy, build-from-source installation,
launch at login, and uninstall commands.

- [ ] **Step 3: Run automated verification**

Run: `swift test`

Expected: all tests pass.

Run: `swift build -c release`

Expected: `.build/release/parrot` is produced.

Run: `.build/release/parrot --help`

Expected: CLI help describes double-tap dictation.

Run:

```bash
rg -n '→.*%@|transcript.*standardError|parrot-last.wav' Sources/parrot
```

Expected: no transcript logging; WAV output exists only behind the explicit
debug option.

- [ ] **Step 4: Install the user-local release binary**

Copy the verified release binary to `~/.local/bin/parrot`, preserving executable
mode. Run `~/.local/bin/parrot install --launch-at-login` only after interactive
permissions are granted or when ready to trigger the permission checkpoint.

- [ ] **Step 5: Permission checkpoint**

Run `~/.local/bin/parrot setup`. Ask the user to approve Accessibility and
Microphone access when macOS opens those prompts. Re-run setup and
`~/.local/bin/parrot doctor` until both permissions pass.

- [ ] **Step 6: LaunchAgent and manual verification**

Run:

```bash
~/.local/bin/parrot install --launch-at-login
launchctl print "gui/$(id -u)/com.digimata.parrot"
```

Expected: the agent is running and points at `~/.local/bin/parrot`.

Manually verify Fn double-tap start/stop, Escape cancellation, text insertion
in Codex and TextEdit, microphone menu switching, history creation and opening,
and absence of dictated text in `/tmp/parrot.err.log`.

- [ ] **Step 7: Commit**

```bash
git add Sources/parrot/Install.swift Sources/parrot/Setup.swift Sources/parrot/Doctor.swift README.md
git commit -m "docs: finish custom dictation setup"
```

## Final verification

- [ ] Run `swift test` and confirm every test passes.
- [ ] Run `swift build -c release` and confirm the release binary exists.
- [ ] Run `git diff --check master...HEAD`.
- [ ] Run `git status --short` and confirm only intentional state remains.
- [ ] Confirm no transcript text is written to diagnostic logs.
- [ ] Confirm the LaunchAgent starts the installed binary.
- [ ] Confirm the user has approved Microphone and Accessibility permissions.
- [ ] Perform physical-key end-to-end checks in Codex and another application.
