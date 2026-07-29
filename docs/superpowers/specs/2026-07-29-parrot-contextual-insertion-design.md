# Parrot Contextual Insertion and Compact Controls Design

Date: 2026-07-29

## Goal

Make consecutive Parrot dictations read like naturally typed prose, reduce the
recording bar to the approved 144-by-28 size, and use a one-time exploratory
comparison to inform the local-model decision without weakening privacy or
personal-vocabulary behavior.

## Scope

This loop adds:

- context-aware spacing at the cursor between separate dictation sessions;
- an exact 144-by-28 recording bar with proportionally reduced controls;
- a transient, one-time exploratory comparison of the registered Base English, Small
  English, and Large v3 Turbo models on identical audio; and
- a model change only if a candidate produces a material accuracy improvement
  without exceeding the post-stop latency budget.

It does not add cloud transcription, retain benchmark audio, rewrite text with
an LLM, silently learn dictionary entries, or migrate to the breaking Argmax
1.0 package without a separate compatibility reason.

## Context-aware insertion

### Boundary behavior

Parrot keeps the processed transcript as semantic text for history. Immediately
before injection, it reads only the focused element's selected range and up to
two UTF-16 code units preceding the caret.

Parrot prefixes exactly one space when all of these are true:

1. the field is non-secure and Accessibility exposes the focused range;
2. the selection length is zero;
3. the caret is not at the beginning of the field;
4. the preceding character is a letter, number, sentence-closing punctuation,
   comma, colon, semicolon, closing delimiter, or closing quote; and
5. the new transcript begins with a letter, number, opening quote, or opening
   delimiter.

Parrot does not synthesize a space at an empty field, after existing whitespace
or a newline, after an opening delimiter, before input beginning with separator
punctuation such as a comma or period, while replacing selected text, in a
secure field, or when cursor context is unavailable. An opening quote or
bracket is intentionally word-like, so quote- or bracket-led text can receive a
boundary space. This conservative fallback preserves existing behavior in apps
whose text controls do not implement the required Accessibility attributes.

### Data ownership

The artificial boundary space belongs only to the inserted string:

- history stores the clean processed transcript without a leading space;
- the text injector receives the context-adjusted insertion string; and
- the correction observer tracks the exact adjusted insertion string so its
  range remains aligned with what appeared in the field.

No cursor-adjacent content is written to logs or history.

### Components

- `InsertionBoundaryPolicy` is a pure function from semantic text and an
  `InsertionContext` to the exact insertion string.
- `AccessibilityInsertionContextReader` reads the minimum focused-field range
  needed to construct `InsertionContext`.
- `DictationController` asks an injected preparation closure for the insertion
  string after history persistence and before correction observation/injection.

## Recording bar

The recording panel is exactly 144 points wide by 28 points high. The horizontal
layout is 39 + 66 + 39 points:

- red cancel button: 39 by 28;
- waveform region: 66 by 20; and
- green finish button: 39 by 28.

Icons use an 11-point bold system font. Six waveform bars use 3-point widths
and 3-point spacing. This is the closest clean integer scaling of the approved
192-by-40 geometry to the requested 144-by-28 target.

The panel remains a dark neutral capsule with the existing blue waveform,
red/green actions, transform/opacity animation, bottom-center placement,
clickability, and non-activating focus behavior. No additional decoration,
continuous motion, or focus-stealing interaction is introduced.

## Transcription quality gate

Parrot remains local-first. Current upstream evidence supports retaining
WhisperKit for this workflow:

- the installed 0.18 dependency is the final pre-breaking WhisperKit release;
- Argmax 1.0 is a breaking package/concurrency migration rather than a claimed
  transcription-quality upgrade;
- Apple's SpeechAnalyzer has no documented custom-vocabulary support; and
- personal canonical replacements are a required part of this product.

The registered models are compared on identical transient 16 kHz mono
fixtures containing ordinary prose, punctuation boundaries, and personal
terms. For each model, record:

- normalized word/term errors against the known reference;
- median and maximum transcription time; and
- model download/storage cost.

The original pre-run exploratory gate kept Base English selected unless another
model:

1. reduces total reference errors or personal-term errors;
2. does not regress any ordinary-prose fixture materially; and
3. keeps median post-stop transcription at or below 1.5 seconds for the short
   fixture set on this M4 MacBook Air.

If results tie, Base English wins because it has the smallest 140 MB on-disk
cache footprint, is already the established default, and completes real
recordings near one second. Benchmark fixtures and any captured WAV files are
deleted after the run; cached downloaded models may remain available for later
selection.

### Post-benchmark deployment-review amendment (2026-07-29)

The one-time exploratory run used six synthetic fixtures totaling 82 words on
an M4 Mac with 16 GB of memory. Warmup and download time were excluded. The
temporary audio, harness, and fixtures were not retained, so the run is not
reproducible or auditable from the repository.

- Base: 8/82 word errors, 5/10 personal-term errors, 0.636-second median,
  0.684-second maximum, 140 MB on-disk cache.
- Small: 4/82 word errors, 3/10 personal-term errors, 1.452-second median,
  1.506-second maximum, 464 MB on-disk cache.
- Large: 74/82 word errors, 8/10 personal-term errors, 0.809-second median,
  1.984-second maximum, 1.5 GB on-disk cache.

Small passed the literal exploratory gate: it reduced total and personal-term
errors, showed no observed material ordinary-prose regression, and its
1.452-second median was within the 1.5-second limit. The gate was a screening
rule, not an automatic global-default deployment rule.

Deployment review retained Base because Small's median was 128% slower, left
only 48 ms (3.2%) headroom below the gate, and reached a 1.506-second maximum.
Making uncached Small the global default would also require a one-time 464 MB
download and on-disk cache footprint, which can delay Parrot startup while it
downloads or make startup fail offline before the menu-bar service is
available. Alternative models, including Small and Large, remain selectable
only at startup through the CLI `--model` option. Large's result does not
support production selection and needs separate diagnosis.

## Error handling and privacy

- Accessibility lookup failure returns the original transcript unchanged.
- Secure fields never expose adjacent context.
- Invalid UTF-16 boundary reads return the original transcript unchanged.
- Empty processed transcripts still produce no history or injection.
- Benchmark failure does not change the installed model.
- Logs may contain durations, model identifiers, and aggregate error counts,
  but never dictated text, adjacent field text, or dictionary contents.

## Verification

Automated tests cover:

- period-to-capital and word-to-word boundary spacing;
- no extra space at field start, after whitespace/newline/opening delimiters,
  for selections, before leading separator punctuation such as a comma or
  period, or with secure/unavailable context;
- boundary spaces before quote- or bracket-led text when prior context requires;
- history receiving semantic text while observer/injector receive adjusted text;
- exact 144-by-28 overlay geometry; and
- all existing gesture, dictionary, filler, correction, and privacy behavior.

Live verification covers:

- three consecutive dictations rendering as separate sentences with spaces;
- no doubled space when the cursor already follows whitespace;
- selected-text replacement without a prefixed space;
- the 144-by-28 bar remaining legible and clickable without stealing focus;
- Escape/cancel and check/finish behavior; and
- the selected model's observed post-stop latency.

## Success criteria

The loop is complete when consecutive recordings produce natural boundaries
such as `working. It's`, the bar is 144 by 28, history remains clean, correction
tracking remains aligned, all automated tests and the release build pass, the
deployment-reviewed local-model default is recorded, and the login service
passes a final live dictation check.
