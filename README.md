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
2. Double-tap Fn. The 144×28 recording bar appears and remains active through
   silence.
3. Speak.
4. Tap Fn once or click `✓`. Parrot transcribes, processes your personal
   vocabulary, saves a history entry, and inserts the text at the current
   cursor.
5. Press Escape or click `×` instead to discard the recording.

A single Fn tap does nothing while Parrot is idle. While Parrot is transcribing
or inserting, additional gestures are ignored.

Separate dictations receive one context-aware boundary space when the cursor
follows text. Parrot does not add a space at the start of a field, after
existing whitespace or an opening delimiter, before punctuation-only
dictation, while replacing a selection, when cursor context is unavailable, or
in protected controls. Unicode text is injected without splitting surrogate
pairs.

The recording bar is exactly 144×28 points, with `×` to cancel and `✓` to
finish.

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

## Model choice

Base English remains the resilient, low-latency default. Small English and
Large v3 Turbo remain explicitly selectable and use cached copies when
available.

An exploratory synthetic evaluation on six fixtures (82 words) measured Base
at 8/82 word errors, 5/10 personal-term errors, and 0.636-second median
latency; Small at 4/82, 3/10, and 1.452 seconds; and Large at 74/82, 8/10,
0.809-second median, and 1.984-second maximum latency. These aggregate results
are not statistically robust and do not establish a universally best model.
Small is not the global default because its median latency increased 128%,
leaving only 48 ms below the gate, and its first download/offline-startup cost
is 464 MB. Large's exploratory quality failure rules it out as a production
selection.

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
tracks the exact inserted text (including any boundary space), is restricted to
the freshly inserted range, and is disabled for secure fields and apps that do
not expose a safe Accessibility text range.

Invalid JSON never disables dictation. Parrot keeps using its last valid
dictionary and shows a menu warning without overwriting the invalid file.

## History and privacy

Completed dictations are appended to private daily Markdown files:

```text
~/Library/Application Support/Parrot/history/YYYY/MM/YYYY-MM-DD.md
```

Entries include local time, destination application, and dictated text.
History remains semantic: an automatically inserted boundary space is not
stored as part of the transcript. Canceled and empty recordings are not saved.
Raw audio remains in memory and is discarded after transcription or
cancellation. Diagnostic logs do not contain transcripts, dictionary entries,
field contents, or learning proposals. The explicit `--dump-wav` debugging
flag is the only option that writes captured audio.

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
