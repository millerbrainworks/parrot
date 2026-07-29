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
existing whitespace or an opening delimiter, before dictation beginning with
separator punctuation such as a comma or period, while replacing a selection,
when cursor context is unavailable, or in protected controls. An opening quote
or bracket is intentionally word-like, so quote- or bracket-led dictation can
receive a boundary space. Unicode text is injected without splitting surrogate
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
Large v3 Turbo remain selectable only at startup through the CLI `--model`
option and use cached copies when available.

A one-time exploratory synthetic run on six fixtures (82 words) measured Base
at 8/82 word errors, 5/10 personal-term errors, 0.636-second median latency,
and 0.684-second maximum latency; Small at 4/82, 3/10, a 1.452-second median,
and a 1.506-second maximum; and Large at 74/82, 8/10, a 0.809-second median,
and a 1.984-second maximum. Its harness and fixtures were not retained, so the
run is not reproducible or auditable from the repository. These aggregate
results are not statistically robust and do not establish a universally best
model.

Small passed the literal exploratory gate: it reduced errors, showed no
observed material ordinary-prose regression, and kept median latency at 1.452
seconds, within the 1.5-second limit. A post-benchmark deployment review still
retained Base: Small's median was 128% slower, had only 48 ms (3.2%) headroom,
and reached a 1.506-second maximum. Making uncached Small the global default
would also require a one-time 464 MB download and on-disk cache footprint,
which can delay Parrot startup while it downloads or make startup fail offline
before the menu-bar service is available. Small remains an explicit startup
CLI `--model` selection. Large's result does not support production selection
and needs separate diagnosis.

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
updates the dictionary only after Learn. Observation uses the exact inserted
text (including any boundary space) as its reference. For at most 30 seconds,
while the same non-secure control remains focused, it reads from the insertion
start to the current caret, capped at the original insertion's UTF-16 length
plus 64. That bounded range may include appended edit context; Parrot never
requests the complete field value or unrelated whole-document text.
Observation is disabled for secure fields and apps that do not expose a safe
Accessibility text range.

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
