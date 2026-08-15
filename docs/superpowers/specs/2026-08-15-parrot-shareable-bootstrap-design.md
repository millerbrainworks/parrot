# Shareable Parrot Bootstrap Design

**Date:** 2026-08-15  
**Status:** Approved through the user's standing instruction to follow recommendations  
**Source version:** `custom/dictionary-controls` at `540b91d`

## Goal

Let the owner send one small Markdown file to a friend by text or GitHub. The
friend gives that file to Codex on an Apple Silicon Mac, and Codex installs the
same Parrot behavior that the owner currently runs.

The handoff must not require the friend to install Xcode, clone the repository,
or understand Swift Package Manager.

## Recommended approach

Publish an immutable GitHub release containing the exact arm64 macOS binary the
owner currently runs. The installed binary and the release build already in the
current worktree are byte-for-byte identical. Add `PARROT_BOOTSTRAP.md` to the
repository as the human- and Codex-readable handoff file. It pins the release
tag and asset URLs rather than installing an unspecified future "latest"
version.

This is preferable to a source build because it removes the Swift toolchain and
long dependency build from the recipient's setup. It is preferable to embedding
the binary in Markdown because the binary is several megabytes, would grow
further when base64 encoded, and would be fragile in messaging systems.

## Release identity

- Release tag: `v0.1.0`
- Source behavior: commit `540b91d`, plus documentation-only bootstrap changes
- Binary asset: `parrot-macos-arm64.tar.gz`
- Checksum asset: `parrot-macos-arm64.tar.gz.sha256`
- Unarchived binary SHA-256: `b5f97e2aa475b0b93e9a53d45ba28fdacc4e5d67e038dc4c318f3640282455a0`
- Supported host: Apple Silicon running macOS 14 or newer

The release tag ties the source and handoff documentation to an immutable
revision. The asset is staged directly from the verified worktree binary rather
than rebuilt with a different dependency version. The bootstrap verifies the
downloaded archive with the published SHA-256 file before extracting or
installing it.

The pinned WhisperKit `v0.18.0` source no longer compiles under the owner's
current Swift 6.2.3 toolchain because Foundation members are hidden during its
cross-module build. Upstream's Swift-6-compatible `v1.0` is a breaking package
migration. Changing that dependency would violate the goal of sharing the
current local app, so dependency modernization is a separate future task.

## Bootstrap document

`PARROT_BOOTSTRAP.md` is written primarily as an instruction file for Codex,
while remaining understandable to a person. It tells Codex to:

1. Explain that Parrot performs private, on-device dictation and needs
   Microphone and Accessibility permissions.
2. Verify macOS, macOS 14 or newer, Apple Silicon, internet access, and required
   built-in tools before changing the machine.
3. Download the pinned archive and checksum into a temporary directory.
4. Verify SHA-256, require the archive to contain exactly the expected
   executable, and install it at `~/.local/bin/parrot` with executable mode.
5. Remove only the downloaded file's quarantine attribute, after successful
   checksum verification, so the unsigned command-line binary can run.
6. Run `parrot setup`, pausing for the friend to grant macOS permissions and
   repeating the check in a fresh process when macOS requires it.
7. Remind the friend to set “Press Globe/Fn key to” to “Do Nothing.”
8. Download the recommended `whisper-base.en` model while errors remain visible.
9. Register Parrot with `parrot install --launch-at-login`.
10. Run `parrot doctor`, report any remaining remediation, and explain the
    double-tap-Fn / single-tap-Fn / Escape controls.

The file also contains a concise manual fallback for cases where Codex is not
available. The fallback uses the same pinned URLs and safety checks; it does not
silently bypass permission failures.

## Installation boundaries

The installation is user-local:

- Executable: `~/.local/bin/parrot`
- LaunchAgent: `~/Library/LaunchAgents/com.digimata.parrot.plist`
- Parrot data: `~/Library/Application Support/Parrot/`
- Logs: `/tmp/parrot.out.log` and `/tmp/parrot.err.log`
- Whisper model cache: managed by WhisperKit in the user's caches

No `sudo` is required. The bootstrap does not modify shell startup files, does
not upload recordings or transcripts, and does not replace unrelated files.

If Parrot is already installed, Codex first removes the old Parrot LaunchAgent,
then atomically replaces only `~/.local/bin/parrot`, and finally reinstalls the
agent. Existing history, preferences, models, and the personal dictionary are
preserved.

## Failure handling

The bootstrap stops before installation when the platform is unsupported, a
download fails, checksum verification fails, or the archive layout is
unexpected. Temporary files are removed on exit.

Permission setup is treated as an interactive checkpoint, not as a script
failure. Codex explains what the friend must click and resumes only after the
friend confirms it. A failed model download or LaunchAgent registration remains
visible and is retried or diagnosed instead of being ignored.

## Verification

Before publishing:

- Confirm that the installed binary and the worktree release binary have the
  pinned SHA-256 above.
- Confirm that the binary is an arm64 Mach-O with an ad-hoc code signature.
- Run `parrot models list` and `parrot doctor` against that exact binary.
- Inspect the archive layout and independently verify its generated SHA-256.
- Check every pinned URL in `PARROT_BOOTSTRAP.md` against the release tag.
- Run Markdown lint-style checks for unresolved placeholders and accidental
  references to local filesystem paths.

Recipient-side success means:

- `~/.local/bin/parrot` is an arm64 Mach-O executable.
- The downloaded archive passes SHA-256 verification.
- `parrot models download whisper-base.en` succeeds.
- The LaunchAgent points to `~/.local/bin/parrot` and is loaded.
- `parrot doctor` passes after the friend grants permissions and changes the Fn
  key setting.
- A short dictated phrase is inserted into a focused text field.

## Out of scope

- Apple code signing, notarization, or a graphical `.app` installer
- Intel Mac or macOS 13 support
- Automatic permission grants, which macOS intentionally prevents
- Publishing future updates automatically through this pinned handoff file
- Migrating WhisperKit from `v0.18.0` to the breaking `v1.0` package
- Changing Parrot's dictation behavior
