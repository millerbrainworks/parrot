# Parrot Contextual Insertion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add conservative cursor-aware spacing, resize the recording bar to 144 by 28, and select the best qualifying local model through a repeatable benchmark.

**Architecture:** Keep semantic transcript processing independent from insertion formatting. Add a pure boundary policy plus a thin Accessibility context reader, inject the prepared string through `DictationController`, and retain clean history. Keep model selection behind an evidence gate so benchmark failure or a latency regression cannot change the installed default.

**Tech Stack:** Swift 5.9, AppKit, ApplicationServices Accessibility APIs, SwiftUI, WhisperKit 0.18, XCTest, Swift Package Manager.

---

## File map

- `Sources/parrot/Input/InsertionBoundaryPolicy.swift` — pure spacing rules and
  context value.
- `Sources/parrot/Input/AccessibilityInsertionContextReader.swift` — minimal,
  secure-aware focused-caret lookup.
- `Sources/parrot/Session/DictationController.swift` — preserve semantic
  history text while preparing the exact insertion string.
- `Sources/parrot/Parrot.swift` — wire the Accessibility reader and policy.
- `Sources/parrot/UI/RecordingOverlay.swift` — 144-by-28 geometry.
- `Tests/parrotTests/InsertionBoundaryPolicyTests.swift` — boundary matrix.
- `Tests/parrotTests/DictationControllerTests.swift` — semantic-versus-inserted
  text orchestration.
- `Tests/parrotTests/RecordingOverlayModelTests.swift` — exact compact geometry.
- `Sources/parrot/Models/ModelRegistry.swift` — change recommendation only if a
  benchmark candidate clears the quality gate.
- `README.md` — document automatic boundary spacing and current dimensions.

### Task 1: Pure insertion-boundary policy

**Files:**
- Create: `Sources/parrot/Input/InsertionBoundaryPolicy.swift`
- Create: `Tests/parrotTests/InsertionBoundaryPolicyTests.swift`

- [ ] **Step 1: Write the failing boundary matrix**

Create table-driven tests requiring:

```swift
XCTAssertEqual(policy.prepare("It's ready.", context: .caret(previous: ".")), " It's ready.")
XCTAssertEqual(policy.prepare("next", context: .caret(previous: "d")), " next")
XCTAssertEqual(policy.prepare("next", context: .caret(previous: " ")), "next")
XCTAssertEqual(policy.prepare("next", context: .caret(previous: "\n")), "next")
XCTAssertEqual(policy.prepare("next", context: .caret(previous: "(")), "next")
XCTAssertEqual(policy.prepare("next", context: .documentStart), "next")
XCTAssertEqual(policy.prepare("next", context: .selection), "next")
XCTAssertEqual(policy.prepare("next", context: .unavailable), "next")
XCTAssertEqual(policy.prepare(",", context: .caret(previous: "d")), ",")
```

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter InsertionBoundaryPolicyTests
```

Expected: compilation fails because the policy and context do not exist.

- [ ] **Step 3: Implement the minimum pure policy**

Add `InsertionContext` cases for unavailable, document start, selection, and a
caret with one preceding `Character`. Add `InsertionBoundaryPolicy.prepare`
with the exact conservative rules in the design.

- [ ] **Step 4: Run GREEN**

Run:

```bash
swift test --filter InsertionBoundaryPolicyTests
```

Expected: all boundary cases pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/parrot/Input/InsertionBoundaryPolicy.swift Tests/parrotTests/InsertionBoundaryPolicyTests.swift
git commit -m "feat: format dictation insertion boundaries"
```

### Task 2: Accessibility context and controller integration

**Files:**
- Create: `Sources/parrot/Input/AccessibilityInsertionContextReader.swift`
- Modify: `Sources/parrot/Session/DictationController.swift`
- Modify: `Sources/parrot/Parrot.swift`
- Modify: `Tests/parrotTests/DictationControllerTests.swift`

- [ ] **Step 1: Write the failing orchestration test**

Add an injected `prepareInsertion` dependency and require:

```swift
XCTAssertEqual(
    operations,
    [
        "history:Codex:It's ready.",
        "prepare:It's ready.",
        "observe: It's ready.",
        "inject: It's ready.",
        "begin",
    ]
)
```

The preparation stub returns `" " + text`. This proves history stays semantic
while correction observation and injection use the exact adjusted string.

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter DictationControllerTests
```

Expected: compilation fails because `prepareInsertion` is missing.

- [ ] **Step 3: Integrate preparation at the insertion boundary**

Add `prepareInsertion: (String) -> String` to `DictationDependencies`. After
history persistence, compute `insertionText`, prepare correction observation
with it, inject it, and begin observation. Preserve all existing error and
state transitions.

- [ ] **Step 4: Add the Accessibility reader**

Implement a thin reader that:

- rejects secure/password controls;
- returns `.selection` when selected length is nonzero;
- returns `.documentStart` at location zero;
- requests at most two UTF-16 code units immediately before the caret;
- returns the final valid `Character` as `.caret(previous:)`; and
- returns `.unavailable` on every unsupported/error path.

Wire `Parrot.swift` so the preparation closure reads context and applies the
pure policy on the main actor. Do not log adjacent text.

- [ ] **Step 5: Run focused and full tests**

Run:

```bash
swift test --filter DictationControllerTests
swift test
```

Expected: all controller and full-suite tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/parrot/Input/AccessibilityInsertionContextReader.swift Sources/parrot/Session/DictationController.swift Sources/parrot/Parrot.swift Tests/parrotTests/DictationControllerTests.swift
git commit -m "feat: space consecutive dictations"
```

### Task 3: Compact 144-by-28 recording bar

**Files:**
- Modify: `Sources/parrot/UI/RecordingOverlay.swift`
- Modify: `Tests/parrotTests/RecordingOverlayModelTests.swift`

- [ ] **Step 1: Change geometry expectations first**

Require:

```swift
XCTAssertEqual(RecordingOverlay.Geometry.panelWidth, 144)
XCTAssertEqual(RecordingOverlay.Geometry.panelHeight, 28)
XCTAssertEqual(RecordingOverlay.Geometry.buttonWidth, 39)
XCTAssertEqual(RecordingOverlay.Geometry.waveformWidth, 66)
XCTAssertEqual(RecordingOverlay.Geometry.waveformHeight, 20)
XCTAssertEqual(RecordingOverlay.Geometry.iconSize, 11)
XCTAssertEqual(RecordingOverlay.Geometry.waveformBarWidth, 3)
XCTAssertEqual(RecordingOverlay.Geometry.waveformSpacing, 3)
```

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter RecordingOverlayModelTests/testRecordingOverlayGeometryIsDoubledProportionally
```

Expected: failures report the existing 192-by-40 values.

- [ ] **Step 3: Apply exact compact geometry**

Update only `Geometry` constants. Keep all layout consumers, colors, actions,
animation, AppKit panel flags, and placement behavior unchanged. Rename the
geometry test to describe the compact approved size.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
swift test --filter RecordingOverlayModelTests
swift test
git diff --check
```

Expected: focused and full tests pass with a clean diff check.

- [ ] **Step 5: Commit**

```bash
git add Sources/parrot/UI/RecordingOverlay.swift Tests/parrotTests/RecordingOverlayModelTests.swift
git commit -m "feat: compact recording controls"
```

### Task 4: Benchmark registered local models

**Files:**
- Modify only if a winner clears the gate:
  `Sources/parrot/Models/ModelRegistry.swift`
- Modify only if recommendation changes:
  `Tests/parrotTests/ModelRegistryTests.swift`

- [ ] **Step 1: Generate transient fixtures**

Use macOS `say` and `afconvert` in a temporary directory to create 16 kHz mono
audio for ordinary prose, punctuation boundaries, and personal terms. Keep the
reference strings beside the temporary files for scoring; do not add audio to
git.

- [ ] **Step 2: Run identical model comparisons**

Warm and run Base English, Small English, and Large v3 Turbo against the same
fixtures with the current vocabulary prompt. Record normalized errors, personal
term errors, median latency, maximum latency, and downloaded size.

- [ ] **Step 3: Apply the quality gate**

Keep Base English unless a candidate reduces errors, avoids material prose
regression, and has median latency no greater than 1.5 seconds. Delete the
temporary fixture directory after results are captured.

- [ ] **Step 4: Change recommendation with TDD only if justified**

If a winner clears the gate, first add a failing registry test asserting the
new recommended model, observe RED, change exactly the `recommended` flags,
then run the focused and full suite. If no candidate clears the gate, make no
registry code change.

- [ ] **Step 5: Commit only justified source changes**

If the recommendation changes:

```bash
git add Sources/parrot/Models/ModelRegistry.swift Tests/parrotTests/ModelRegistryTests.swift
git commit -m "perf: select measured dictation model"
```

If Base remains recommended, record benchmark evidence in the final
verification documentation commit only.

### Task 5: Documentation, release, and live verification

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-07-29-parrot-contextual-insertion.md`
- Replace: `/Users/don/.local/bin/parrot`

- [ ] **Step 1: Update user documentation**

Document cursor-aware spacing, the 144-by-28 bar, semantic history behavior,
and the measured model decision without exposing benchmark phrase content.

- [ ] **Step 2: Run the completion gate**

Run:

```bash
swift test
swift build -c release
git diff --check
git status --short
```

Expected: all tests pass, the release build succeeds, and only intended
documentation/checklist changes remain.

- [ ] **Step 3: Commit documentation**

```bash
git add README.md docs/superpowers
git commit -m "docs: explain contextual dictation spacing"
```

- [ ] **Step 4: Sign and install once**

Ad-hoc sign the final release with identifier `com.digimata.parrot`, preserve
the current installed executable as `.previous`, install the new executable,
verify its signature, and restart `com.digimata.parrot`.

- [ ] **Step 5: Restore Accessibility once**

If the new code hash invalidates the LaunchAgent's Accessibility permission,
open the Accessibility pane and have the user remove/re-add the exact
`/Users/don/.local/bin/parrot` executable once.

- [ ] **Step 6: Verify live behavior**

Confirm service readiness and doctor checks, then verify:

1. three separate dictations render with one boundary space each;
2. dictation after existing whitespace does not double-space;
3. selected-text replacement gets no artificial prefix;
4. the 144-by-28 X/check controls remain clickable without stealing focus;
5. Escape cancels and one Fn tap finishes; and
6. live post-stop latency is consistent with the selected model.
