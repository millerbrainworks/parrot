# Parrot — personal system dictation

A private macOS dictation daemon. Double-tap Fn to start recording, tap Fn once
to transcribe and insert at the cursor, or press Escape to cancel.
Transcription runs on-device.

## Requirements

- macOS 14 or newer
- Apple Silicon
- Swift toolchain capable of building Swift 5.9 packages

## How to use

1. Focus a text field in Codex or any other app.
2. Double-tap Fn. The 96×20 recording bar appears and remains active through
   silence.
3. Speak.
4. Tap Fn once or click `✓`. Parrot transcribes, processes your personal
   vocabulary, saves a history entry, and inserts the text at the current
   cursor.
5. Press Escape or click `×` instead to discard the recording.

A single Fn tap does nothing while Parrot is idle. While Parrot is transcribing
or inserting, additional gestures are ignored.

Set System Settings → Keyboard → “Press 🌐 key to” to “Do Nothing” so macOS
does not perform another action on Fn.

## Menu bar

Parrot lives in the top-right menu bar and starts at login. The menu shows its
current state and model and provides:

- System Default or a specific microphone
- Open Today’s History
- Open Personal Dictionary
- launch-at-login status
- permission guidance
- Quit

A missing saved microphone falls back to System Default while retaining the
saved device preference for reconnection.

## Personal dictionary and filler cleanup

Parrot creates and reloads this private file before every transcription:

```text
~/Library/Application Support/Parrot/personal-dictionary.json
```

Its `terms` array biases Whisper toward your preferred vocabulary.
`replacements` maps multiple recognized variants to one canonical spelling:

```json
{
  "canonical": "Arcqtype",
  "variants": ["archetype", "arc type", "ark type"]
}
```

Matching is case-insensitive, respects word boundaries, preserves surrounding
punctuation, and applies longer phrases first. The starter `fillerWords` list
removes only standalone `um`, `uh`, `erm`, and `ah`; it preserves phrases such
as `actually`, `like`, `you know`, and `I mean`.

If you correct one localized word or phrase shortly after insertion, supported
text fields show a Learn/Ignore popover beneath the menu-bar bird. Parrot
updates the dictionary only after Learn. Observation lasts at most 30 seconds,
is restricted to the freshly inserted range, and is disabled for secure fields
and apps that do not expose a safe Accessibility text range.

Invalid JSON never disables dictation. Parrot keeps using its last valid
dictionary and shows a menu warning without overwriting the invalid file.

## History and privacy

Completed dictations are appended to private daily Markdown files:

```text
~/Library/Application Support/Parrot/history/YYYY/MM/YYYY-MM-DD.md
```

Entries include local time, destination application, and dictated text.
Canceled and empty recordings are not saved. Raw audio remains in memory and is
discarded after transcription or cancellation. Diagnostic logs do not contain
transcripts, dictionary entries, field contents, or learning proposals. The
explicit `--dump-wav` debugging flag is the only option that writes captured
audio.

## Build and install

```sh
swift test
swift build -c release
mkdir -p ~/.local/bin
cp .build/release/parrot ~/.local/bin/parrot
chmod +x ~/.local/bin/parrot
~/.local/bin/parrot setup
~/.local/bin/parrot install --launch-at-login
```

The first setup requires interactive Microphone and Accessibility approval.
Parrot then runs through `~/Library/LaunchAgents/com.digimata.parrot.plist`.

## CLI

```sh
parrot                                  # run in the foreground
parrot setup                            # request and verify permissions
parrot install --launch-at-login        # register and start the LaunchAgent
parrot install --uninstall              # remove the LaunchAgent
parrot doctor                           # check permissions and Fn configuration
parrot models list                      # list transcription models
parrot models download <id>             # download a model
parrot --model whisper-large-v3-turbo   # choose a model
parrot --no-overlay                     # disable the recording pill
parrot --dump-wav                       # debug only: write /tmp/parrot-last.wav
```

## Stack

- Swift Package Manager
- WhisperKit and CoreML
- AVAudioEngine and CoreAudio
- CGEventTap and CGEvent
- AppKit and SwiftUI

See [docs/architecture.md](docs/architecture.md) for upstream design notes and
[the customization specification](docs/superpowers/specs/2026-07-29-parrot-system-dictation-design.md)
plus [the recording and dictionary specification](docs/superpowers/specs/2026-07-29-parrot-dictionary-controls-design.md)
for this implementation.
