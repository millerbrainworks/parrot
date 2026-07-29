# System-wide Parrot Dictation Design

Date: 2026-07-29

## Goal

Customize Parrot into an always-available, user-level macOS dictation service
for Codex and other applications. A double-tap of the Fn key starts recording,
a second double-tap stops and inserts the transcription at the active cursor,
and Escape cancels the recording. Completed dictations are retained in a
private, date-organized local history.

## Scope

This change extends the existing single-process Parrot executable. It does not
add cloud transcription, prompt submission awareness, continuous listening,
silence-based stopping, or a separate helper application.

The service starts at login and remains available in the background. "Always
available" does not mean that the microphone is always active: audio capture
occurs only during an explicitly started recording session.

## Installation and source management

The local fork lives at `/Users/don/Developer/parrot` on branch
`custom/double-tap-history`, with `origin` retained as the upstream Parrot
repository. This keeps the customization isolated while preserving the option
to pull upstream fixes.

The project will be built from source as a release binary rather than installed
through the upstream `curl | sh` command. The binary will run as the current
macOS user through a LaunchAgent and will be available across applications in
that user's graphical login session.

The LaunchAgent will:

- start Parrot at login;
- keep it available after an unexpected process failure;
- write operational output to diagnostic logs that never contain dictated
  text; and
- allow a deliberate menu-bar Quit action to stop Parrot for the remainder of
  the current login session without disabling launch at login.

Microphone and Accessibility permissions require interactive approval in
macOS. Setup must take the user to the appropriate System Settings panes and
verify both permissions before the service is considered ready.

## Interaction model

Parrot has four explicit session states:

1. `idle`
2. `recording`
3. `transcribing`
4. `injecting`

### Start

While idle, two Fn taps completed within a 350-millisecond double-tap window
start recording. A single Fn tap has no Parrot action. Starting a recording
opens the microphone and displays the recording overlay and menu-bar state.

### Stop and insert

While recording, another Fn double-tap stops capture. Parrot transcribes the
captured audio, writes the completed history entry, and injects the text at the
current cursor. Recording has no silence timeout and no fixed duration limit.
The expected use case is normally 5 seconds to 1 minute, so the existing
in-memory audio representation is appropriate.

### Cancel

While recording, Escape immediately stops capture, discards all captured
audio, hides the recording UI, and returns to idle. Canceled recordings are not
transcribed, stored, or inserted.

Escape is intercepted only during the recording state. It must not also reach
the foreground application in that state. At all other times, Escape behaves
normally.

### Busy behavior

Fn and Escape gestures received while Parrot is transcribing or injecting are
ignored. Parrot never runs overlapping recording or transcription sessions.
After success or failure, it returns to idle.

## Components and responsibilities

### Activation gesture recognizer

The hotkey layer continues to observe global keyboard events but delegates
timing and gesture interpretation to a focused recognizer. The recognizer turns
Fn press/release edges into double-tap events and identifies Escape only when
the session controller reports that cancellation is available.

The event tap must support consuming Escape during recording. Other observed
events, including single Fn taps, pass through without modification.

### Session controller

A session controller owns the four-state lifecycle and is the only component
allowed to start or stop audio capture, begin transcription, request history
writes, or inject text. This keeps timing input separate from dictation
orchestration and makes state transitions independently testable.

### Audio capture and transcription

Audio remains in memory for the lifetime of a recording. The debug WAV-writing
option is not enabled by the LaunchAgent. On cancellation, the sample buffer is
released without transcription. On stop, the existing WhisperKit transcriber
handles the captured samples.

An empty transcript or a transcript containing only sanitized non-speech
tokens produces no history entry and no text injection.

### Destination application context

Immediately before history persistence and text injection, Parrot reads the
frontmost application's localized display name through macOS workspace APIs.
It stores only that display name, such as `Codex`, `Safari`, or `Messages`.
Window titles, document names, bundle identifiers, and cursor context are not
stored. If macOS does not report a frontmost application, the entry uses
`Unknown Application`.

### History writer

Completed dictations are appended to daily Markdown files under:

`~/Library/Application Support/Parrot/history/YYYY/MM/YYYY-MM-DD.md`

Each entry uses local time and this format:

```markdown
## 14:37:22 — Codex

Draft an implementation plan for the authentication changes.
```

The history writer:

- creates missing year and month directories;
- serializes all writes on one queue and issues one append operation per
  complete entry, preventing entries from interleaving;
- creates directories with mode `0700` and files with mode `0600`;
- retains entries indefinitely with no automatic deletion;
- provides the saved entry as a recovery copy before text injection begins;
  and
- never writes canceled, empty, or failed transcriptions.

Parrot records dictated text, not submitted prompts. It does not attempt to
observe whether the destination application's user later sends or deletes the
inserted text.

### Diagnostic logging

Operational logs may include state transitions, durations, selected device
names, model identifiers, and errors. They must never include transcripts,
captured audio, window titles, document names, or surrounding cursor content.
The current source line that emits the completed transcription to standard
error will be removed.

## Menu-bar experience

Parrot remains a menu-bar application with no Dock icon. Its menu presents:

- current state: Idle, Recording, or Transcribing;
- the selected microphone;
- a microphone submenu;
- Open Today's History;
- launch-at-login status; and
- Quit.

The microphone submenu lists currently available input devices and a
recommended `System Default` option. The selected choice is checked and
persists across process and login restarts.

When `System Default` is selected, each new recording uses the current macOS
default input. When a named device is selected, Parrot requests that device for
new recordings. Named devices are persisted by stable CoreAudio device UID and
shown by their current display name. Device selection is disabled while
recording or transcribing. If a saved named device is unavailable, Parrot falls
back to System Default, keeps the saved UID for future reconnects, and exposes
a warning in the menu.

Open Today's History opens the current date's Markdown file when it exists. If
no entry has been recorded that day, it opens the history directory instead.

## Configuration persistence

User preferences are stored under
`~/Library/Application Support/Parrot/`. The persisted settings cover:

- selected microphone identity, with `System Default` as the default;
- launch-at-login status where needed for menu display.

The 350-millisecond double-tap interval is a code constant in the first
version, not a user preference.

The first version does not add a general settings window. Menu choices and the
existing CLI remain the configuration surfaces.

## Error handling

- If microphone permission or Accessibility permission is missing, Parrot
  displays a menu warning and offers a shortcut to the corresponding System
  Settings location.
- If the selected microphone disappears, Parrot uses System Default and marks
  the fallback in the menu.
- If audio capture cannot start, Parrot returns to idle, inserts nothing, and
  writes no history entry.
- If transcription fails, Parrot returns to idle, inserts nothing, and writes
  no history entry.
- If history persistence fails, Parrot warns through the menu and operational
  log but still injects the transcription so dictation remains usable.
- If injection cannot be confirmed, the pre-injection history entry remains
  available for recovery.
- Escape cancellation always takes precedence while recording and leaves no
  audio or history artifact.

## Verification strategy

Automated tests will cover:

- double-tap recognition inside and outside the 350-millisecond window;
- single Fn taps producing no action;
- idle, recording, transcribing, injecting, success, failure, and cancellation
  transitions;
- busy-state gesture rejection and prevention of overlapping sessions;
- Escape consumption during recording and normal pass-through otherwise;
- history paths across date boundaries;
- Markdown entry formatting and destination application labeling;
- directory and file permissions;
- canceled, empty, and failed transcriptions producing no entry;
- microphone preference persistence;
- unavailable-device fallback behavior; and
- transcript content never reaching diagnostic log messages.

Manual macOS verification will cover:

- clean release build from the fork;
- first-run Microphone and Accessibility permission setup;
- LaunchAgent startup after login;
- start, stop, and cancellation from the physical Fn and Escape keys;
- menu-bar state and controls;
- microphone switching between available devices;
- text insertion in Codex and at least one unrelated macOS application; and
- history creation, Open Today's History, and absence of transcript text from
  `/tmp/parrot.err.log`.

## Success criteria

The integration is complete when Parrot starts at login, remains available in
the menu bar, records only after an Fn double-tap, continues through silence,
inserts text only after a second Fn double-tap, cancels cleanly on Escape,
supports persistent microphone selection with safe fallback, and maintains
private daily history files containing timestamp, destination application, and
dictated text without leaking transcripts into diagnostic logs.
