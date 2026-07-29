# Parrot Recording Controls, Personal Dictionary, and Assisted Learning Design

Date: 2026-07-29

## Goal

Refine the installed Parrot dictation service so stopping a recording is
faster, the recording overlay has dependable mouse controls, dictated text can
use a private personal vocabulary, and Parrot can suggest new replacement
rules after the user corrects freshly inserted text.

This design amends the interaction model in
`2026-07-29-parrot-system-dictation-design.md`. Requirements not changed here,
including login startup, microphone selection, private daily history, and
transcript-free diagnostic logs, remain in force.

## Scope

This change adds:

- a state-dependent Fn gesture: double-tap to start and single-tap to finish;
- a compact interactive recording bar with cancel and finish buttons;
- a local JSON personal dictionary;
- deterministic term, phrase, and conservative filler cleanup;
- optional Whisper vocabulary bias from the personal dictionary;
- explicit, user-confirmed learning suggestions after localized corrections;
  and
- menu-bar access to the dictionary and its current health.

It does not add silent automatic learning, cloud synchronization, a general
settings window, document-wide monitoring, AI rewriting, or aggressive removal
of conversational phrases.

## Recording interaction

### Keyboard controls

While idle, two Fn taps completed within the existing 350-millisecond window
start recording. A single Fn tap while idle has no Parrot action.

Once recording has started, the next single Fn tap stops capture immediately,
transcribes the audio, processes the transcript, saves it to history, and
inserts it at the current cursor. Parrot does not wait for a second Fn tap while
recording. The second tap that completed the starting double-tap belongs only
to the start gesture; its release cannot also trigger stop. Stop requires a new
Fn press after the start gesture has completed.

Escape cancels while recording. Cancellation discards the audio and produces
no transcription, history entry, or inserted text.

Fn and Escape events received while transcribing, processing, persisting, or
injecting are ignored. Parrot continues to prohibit overlapping sessions.

### Recording bar

The recording bar is a non-activating, always-on-top panel centered near the
bottom of the active screen. Its panel frame is 192 points wide by 40 points
high and contains, from left to right:

1. a red cancel button marked `×`;
2. the existing recording waveform or activity indicator; and
3. a green finish button marked `✓`.

The panel accepts clicks but does not become the key application or move text
focus away from the destination field. The cancel button has the same behavior
as Escape. The finish button has the same behavior as a single Fn tap during
recording.

The recording bar is visible only while recording. Existing menu-bar status
continues to represent idle, recording, and transcribing states.

## Personal dictionary

### Storage and schema

Parrot stores the personal dictionary at:

`~/Library/Application Support/Parrot/personal-dictionary.json`

The containing directory uses mode `0700` and the file uses mode `0600`. The
file is UTF-8 JSON with this versioned shape:

```json
{
  "version": 1,
  "terms": [
    "Arcqtype",
    "ARQ",
    "Supabase"
  ],
  "replacements": [
    {
      "canonical": "Arcqtype",
      "variants": [
        "archetype",
        "arc type",
        "ark type"
      ]
    },
    {
      "canonical": "want to",
      "variants": [
        "wanna"
      ]
    }
  ],
  "fillerWords": [
    "um",
    "uh",
    "erm",
    "ah"
  ]
}
```

`terms` contains spellings that should be favored and normalized when Whisper
already recognizes the same term without an explicit variant. `replacements`
contains one canonical spelling and one or more recognized variants.
`fillerWords` contains standalone tokens that should be removed.

Parrot creates a starter dictionary on first use. It seeds the non-email
vocabulary and explicit arrow mappings shown in the supplied Wispr Flow
screenshots. Email addresses are excluded. Screenshot entries that are
ordinary words may remain in `terms`, but Parrot does not invent replacement
rules for them.

The starter `terms` list is:

```text
Ambra
AmbrasWorkspace
queue
arq anchor scale
BodyPark
ARQ
ARQ Score
a2
now.w
poller
Backbrief
TmUX
env vars
TMUX pane
Adversarially verify, merge, and advance
Wispr Flow
ARCQTYPE-API
SIWA
Dhermi
Sarande
neumorphic
guardrail
guardrailed
cuesYouTube
SSD1
DeepSeek
spint
Termius
Vercel
don
simulator
Cron
execute
spec this out
run the sim
Opus
carvana
coach
sprints
metabase
main
.env
Maestro
don miller
sim
xcode
Arcqtype
as applicable
spec
use subagents
spawn subagents
Codex
spawn
subagents
agents.md
claude.md
seed-report
forth
openAI
seedBAC
MIAU
chaminade
openclaw
MillerBrainworks
claude
Macmini
Idle
Scrapling
Supabase
SafeDose
revenuecat
dcos
```

The starter replacement rules include the explicitly supplied mappings,
including:

- `archetype`, `arc type`, and `ark type` to `Arcqtype`;
- `wanna` to `want to`;
- `env` to `.env`;
- `speck` to `spec`;
- `btw` to `by the way`;
- `pain` to `pane`;
- `teemux` to `TMUX`;
- `A T` to `AT`;
- `Cloud` to `Claude`; and
- `O T` to `OT`.

Exact canonical capitalization comes from the JSON file. The starter uses
`Arcqtype` for the product name. The user can change it to `ARCQTYPE` or define
separate canonical phrases such as `ARCQTYPE-API`.

### Loading and editing

The dictionary is loaded before each recording is transcribed, so a valid edit
takes effect on the next dictation without restarting Parrot. Parrot keeps the
last successfully loaded dictionary in memory.

The menu includes `Open Personal Dictionary`, which creates the starter file
when needed and opens it in the user's default JSON editor. The menu also shows
a concise warning when the file is invalid.

If parsing or validation fails, Parrot leaves the file untouched, records a
content-free diagnostic error, and uses the last valid in-memory dictionary.
If no valid dictionary has ever loaded, it uses the built-in starter values.
Dictionary errors never prevent recording, transcription, history, or text
insertion.

## Transcript processing

A focused transcript processor owns deterministic cleanup. The session
controller supplies raw Whisper output and receives final text; it does not
implement replacement details itself.

Processing occurs in this order:

1. sanitize known non-speech markers and trim surrounding whitespace;
2. remove configured filler words;
3. apply configured replacement variants;
4. normalize recognized dictionary terms where an unambiguous
   case-insensitive whole-term match exists;
5. repair whitespace left by removals without rewriting punctuation; and
6. reject the result if it is empty.

Filler removal is deliberately conservative. The starter list removes only the
standalone tokens `um`, `uh`, `erm`, and `ah`, case-insensitively. It preserves
`actually`, `like`, `you know`, `I mean`, and other potentially meaningful
phrases. Word boundaries prevent a filler such as `um` from altering `human`.

Replacement variants are matched case-insensitively on word or phrase
boundaries. Longer variants take precedence over shorter overlapping variants.
A replacement never matches inside a larger alphanumeric word. Punctuation
adjacent to a match is preserved.

Personal terms are also supplied to Whisper as prompt vocabulary when the
installed WhisperKit API supports prompt tokens. Prompt bias is an aid, not the
source of truth: deterministic post-processing remains responsible for
canonical variants. Prompt text follows WhisperKit's native CLI convention:
it begins with one leading space and excludes special tokens. Prompted
decoding also disables WhisperKit's first-token confidence cutoff because
that cutoff otherwise evaluates a forced prompt token and terminates decoding
before speech output. The average-confidence, no-speech, and temperature
fallback safeguards remain enabled. If prompt token construction fails,
transcription continues without bias.

Only the final processed text is written to history and inserted. Diagnostic
logs never include raw text, processed text, dictionary entries, or correction
content.

## Assisted learning

### Observation boundary

After a successful insertion, Parrot may observe only the Accessibility value
and selection information needed to re-read the range it just inserted. It
does not inspect unrelated document text, window titles, clipboard history, or
other applications.

Observation lasts for 30 seconds or until one of these occurs:

- the user changes focus or destination application;
- the inserted range can no longer be identified safely;
- Parrot starts another recording;
- the user accepts or ignores a suggestion; or
- the destination is a secure or password field.

If the destination application does not expose reliable Accessibility text
range information, Parrot skips assisted learning for that insertion. This
failure is silent and does not affect dictation.

### Correction detection

Parrot compares the originally inserted range with the current value of that
same range. It offers a suggestion only when it can isolate one localized,
non-empty substitution with a clear original and corrected phrase. Broad
rewrites, deletions without a replacement, ambiguous multi-region edits, and
changes outside the inserted range do not produce suggestions.

Parrot never writes a learned rule without confirmation.

### Confirmation popover

When a correction is detected, a popover anchored beneath the Parrot menu-bar
icon displays:

`Learn this correction? "archetype" → "Arcqtype"`

The popover provides `Learn` and `Ignore` actions and remains available for up
to 30 seconds. `Learn` merges the original phrase into the variant list for
the corrected canonical spelling, writes the JSON atomically, retains mode
`0600`, and refreshes the in-memory dictionary. Duplicate variants are not
added. `Ignore` and timeout discard the proposal.

If the dictionary changed on disk after the suggestion was created, Learn
reloads and validates the current file before merging. If that reload is
invalid or the atomic write fails, Parrot preserves the existing file and
shows a menu warning rather than losing user edits.

Correction strings may appear in the transient popover, but they are not sent
to diagnostic logs. Ignored and expired suggestions are not persisted.

## Components and responsibilities

- `HotkeyMonitor` and its pure gesture policy translate idle Fn double-taps,
  recording Fn single-taps, and recording Escape presses into controller
  commands.
- `RecordingPanelController` owns the 192-by-40 non-activating panel and exposes
  cancel and finish callbacks without owning session state.
- `PersonalDictionaryStore` creates, loads, validates, atomically updates, and
  opens the JSON file.
- `TranscriptProcessor` performs filler removal, replacement matching, term
  normalization, and whitespace repair.
- `VocabularyPromptBuilder` converts terms to optional Whisper prompt tokens
  without making transcription depend on prompt generation.
- `CorrectionObserver` owns the bounded post-insertion Accessibility
  observation and emits only high-confidence correction proposals.
- `LearningPopoverController` presents Learn and Ignore and delegates
  persistence to the dictionary store.
- `DictationController` remains the sole session orchestrator and connects
  these components in sequence.

Each component exposes behavior through a small interface so matching,
storage, gesture, and learning decisions are testable without a live
microphone or foreground application.

## Data flow

For a completed recording:

1. the single Fn tap or finish button asks `DictationController` to stop;
2. audio capture ends and Whisper produces a raw transcript;
3. `TranscriptProcessor` produces final text using the current dictionary;
4. Parrot identifies the destination application;
5. the final text is appended to private daily history;
6. the final text is inserted at the cursor;
7. when reliable and non-secure Accessibility range information is available,
   `CorrectionObserver` watches only the inserted range for up to 30 seconds;
8. a high-confidence correction opens the confirmation popover; and
9. Learn atomically merges the new rule, while Ignore or timeout changes
   nothing.

History remains a recovery copy before injection. A history failure continues
to warn but does not block insertion, consistent with the original design.

## Error handling and privacy

- Invalid JSON uses the last valid or built-in dictionary and produces a menu
  warning.
- Dictionary read, tokenization, or prompt-bias failures do not block
  transcription.
- Dictionary writes are atomic and never replace a valid file with partial
  content.
- Recording bar actions are ignored unless the session is recording.
- A failed finish returns Parrot to idle through the existing error path.
- Assisted learning is disabled for secure fields and unsupported application
  controls.
- Ambiguous corrections are ignored rather than guessed.
- Accessibility observation is bounded to the fresh insertion and two
  30-second windows: one for detecting a correction and, once shown, one for
  responding to the popover.
- Audio, raw transcripts, final transcripts, dictionary contents, destination
  field contents, and proposed corrections never appear in diagnostic logs.

## Verification strategy

Automated tests cover:

- idle double-tap start and recording single-tap finish;
- single idle taps, Escape cancellation, busy-state rejection, and prevention
  of overlapping sessions;
- cancel and finish recording-bar callbacks;
- dictionary creation, permissions, decoding, validation, reload, and atomic
  learned-rule merging;
- invalid JSON fallback without overwriting the invalid file;
- case-insensitive whole-word and whole-phrase matching;
- longest-variant precedence, punctuation preservation, and substring
  rejection;
- conservative filler removal, including preservation of `human`, `actually`,
  `like`, `you know`, and `I mean`;
- whitespace repair and empty-result rejection;
- final processed text, rather than raw text, reaching history and injection;
- correction diff acceptance for one localized substitution and rejection of
  ambiguous, deletion-only, multi-region, secure-field, expired, and
  focus-changed cases;
- duplicate learning proposals merging without duplicate variants; and
- operational logs remaining content-free on every new error path.

Manual macOS verification covers:

- a release build, ad-hoc signing, installation, and LaunchAgent restart;
- any renewed Microphone or Accessibility permission request;
- double-tap Fn start followed by single-tap Fn finish;
- Escape and the red button canceling without insertion;
- the green button finishing without stealing destination focus;
- the 192-by-40 bar's legibility and placement;
- live dictionary editing and next-dictation reload;
- `Arcqtype` and explicit phrase replacement in Codex and another Mac app;
- conservative filler removal in a natural dictation;
- a supported-field correction producing a menu-bar popover and Learn updating
  the JSON file;
- Ignore and timeout leaving the dictionary unchanged;
- history containing final processed text; and
- diagnostic logs containing none of the dictated or learned text.

## Success criteria

The change is complete when Parrot starts with the existing login service,
starts recording on an idle Fn double-tap, finishes on one recording-state Fn
tap or the green button, cancels on Escape or the red button, displays a
usable 192-by-40 recording bar, applies the local dictionary and conservative
filler cleanup before history and insertion, safely reloads manual dictionary
edits, and offers explicit menu-bar learning confirmation for supported
localized corrections without monitoring or logging unrelated text.
