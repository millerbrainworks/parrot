# Shareable Parrot Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the owner's current Parrot as an immutable binary release and provide one small Markdown file that a friend can give to Codex for safe installation.

**Architecture:** `PARROT_BOOTSTRAP.md` is the complete recipient handoff and pins release `v0.1.0`. A repository-only shell contract test validates the Markdown's safety properties and shell syntax. The release packages the already-built binary that is byte-for-byte identical to the owner's installed app, avoiding a behavior-changing migration from WhisperKit `v0.18.0` to its breaking Swift-6-compatible `v1.0` package.

**Tech Stack:** Markdown, Bash 3.2-compatible shell, macOS built-in command-line tools, GitHub CLI, GitHub Releases

**Spec:** `docs/superpowers/specs/2026-08-15-parrot-shareable-bootstrap-design.md`

## Global Constraints

- Supported host: Apple Silicon running macOS 14 or newer.
- Install the executable at `~/.local/bin/parrot` without `sudo`.
- Pin release tag `v0.1.0`; never resolve an unspecified future latest release.
- The unarchived release binary must have SHA-256 `b5f97e2aa475b0b93e9a53d45ba28fdacc4e5d67e038dc4c318f3640282455a0`.
- Verify `parrot-macos-arm64.tar.gz` with `parrot-macos-arm64.tar.gz.sha256` before extraction or installation.
- Preserve existing history, preferences, cached models, and personal dictionary data.
- Do not change Parrot's dictation behavior.
- Do not attempt to automate macOS Microphone or Accessibility permission grants.
- The recipient sends only `PARROT_BOOTSTRAP.md`; repository tests and workflow files are not part of the handoff.

---

### Task 1: Shareable bootstrap document and contract test

**Files:**
- Create: `PARROT_BOOTSTRAP.md`
- Create: `scripts/test-bootstrap-doc.sh`

**Interfaces:**
- Consumes: GitHub repository `digimata/parrot`, release tag `v0.1.0`, assets `parrot-macos-arm64.tar.gz` and `parrot-macos-arm64.tar.gz.sha256`
- Produces: a Codex-readable bootstrap with an embedded Bash block delimited by `<!-- BEGIN PARROT INSTALL SCRIPT -->` and `<!-- END PARROT INSTALL SCRIPT -->`; an executable static checker invoked as `scripts/test-bootstrap-doc.sh [document]`

- [ ] **Step 1: Write the failing bootstrap contract test**

Create `scripts/test-bootstrap-doc.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

doc="${1:-PARROT_BOOTSTRAP.md}"

fail() {
    printf 'bootstrap contract failed: %s\n' "$*" >&2
    exit 1
}

[ -f "$doc" ] || fail "missing $doc"

begin_count=$(grep -Fxc '<!-- BEGIN PARROT INSTALL SCRIPT -->' "$doc" || true)
end_count=$(grep -Fxc '<!-- END PARROT INSTALL SCRIPT -->' "$doc" || true)
[ "$begin_count" -eq 1 ] || fail "expected one install-script begin marker"
[ "$end_count" -eq 1 ] || fail "expected one install-script end marker"

scratch=$(mktemp -d "${TMPDIR:-/tmp}/parrot-doc-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
script="$scratch/install.sh"

awk '
    /^<!-- BEGIN PARROT INSTALL SCRIPT -->$/ { capture = 1; next }
    /^<!-- END PARROT INSTALL SCRIPT -->$/ { capture = 0 }
    capture { print }
' "$doc" | sed '1{/^```bash$/d;}; ${/^```$/d;}' > "$script"

[ -s "$script" ] || fail "embedded install script is empty"
bash -n "$script" || fail "embedded install script has invalid Bash syntax"

require_doc() {
    grep -Fq "$1" "$doc" || fail "document is missing: $1"
}

require_script() {
    grep -Fq "$1" "$script" || fail "install script is missing: $1"
}

require_doc 'Give this entire file to Codex'
require_doc '~/.local/bin/parrot setup'
require_doc '~/.local/bin/parrot models download whisper-base.en'
require_doc '~/.local/bin/parrot install --launch-at-login'
require_doc '~/.local/bin/parrot doctor'
require_doc 'Press Globe/Fn key to'

require_script 'PARROT_REPO="digimata/parrot"'
require_script 'PARROT_TAG="v0.1.0"'
require_script 'PARROT_ASSET="parrot-macos-arm64.tar.gz"'
require_script 'uname -s'
require_script 'uname -m'
require_script 'sw_vers -productVersion'
require_script 'shasum -a 256 -c'
require_script 'tar -tzf'
require_script 'Mach-O 64-bit executable arm64'
require_script 'PARROT_TARGET="${HOME}/.local/bin/parrot"'
require_script 'xattr -d com.apple.quarantine'

if grep -Fq 'sudo' "$doc"; then
    fail "bootstrap must not use sudo"
fi
if grep -Eq '/Users/don|/Volumes/MIAU' "$doc"; then
    fail "bootstrap exposes an owner-local filesystem path"
fi

checksum_line=$(grep -nF 'shasum -a 256 -c' "$script" | head -1 | cut -d: -f1)
extract_line=$(grep -nF 'tar -xzf' "$script" | head -1 | cut -d: -f1)
xattr_line=$(grep -nF 'xattr -d com.apple.quarantine' "$script" | head -1 | cut -d: -f1)
[ "$checksum_line" -lt "$extract_line" ] || fail "archive is extracted before checksum verification"
[ "$extract_line" -lt "$xattr_line" ] || fail "quarantine is removed before verified extraction"

printf 'bootstrap contract passed: %s\n' "$doc"
```

Make it executable:

```bash
chmod +x scripts/test-bootstrap-doc.sh
```

- [ ] **Step 2: Run the contract test and verify it fails**

Run:

```bash
scripts/test-bootstrap-doc.sh
```

Expected: exit 1 with `bootstrap contract failed: missing PARROT_BOOTSTRAP.md`.

- [ ] **Step 3: Create the recipient-facing Markdown**

Create `PARROT_BOOTSTRAP.md`. It must contain the following sections and exact operational behavior:

```markdown
# Install Parrot

Give this entire file to Codex and say: **“Install Parrot exactly as instructed.”**

Parrot is Don's private, on-device macOS dictation tool. Audio and transcripts
stay on the Mac. It requires an Apple Silicon Mac running macOS 14 or newer,
internet access for the app and speech model, and manual approval of Microphone
and Accessibility permissions.

## Instructions for Codex

Explain each phase before running it. Do not change the repository, release tag,
asset names, or install location. Stop on failed compatibility, download,
checksum, archive-layout, or executable-type checks. Never request elevated
privileges. Preserve existing Parrot data under
`~/Library/Application Support/Parrot/`.

First, run the following block as one Bash script.

<!-- BEGIN PARROT INSTALL SCRIPT -->
```bash
set -euo pipefail

PARROT_REPO="digimata/parrot"
PARROT_TAG="v0.1.0"
PARROT_ASSET="parrot-macos-arm64.tar.gz"
PARROT_CHECKSUM="${PARROT_ASSET}.sha256"
PARROT_INSTALL_DIR="${HOME}/.local/bin"
PARROT_TARGET="${HOME}/.local/bin/parrot"
PARROT_PLIST="${HOME}/Library/LaunchAgents/com.digimata.parrot.plist"

[ "$(uname -s)" = "Darwin" ] || {
    printf 'Parrot requires macOS.\n' >&2
    exit 1
}
[ "$(uname -m)" = "arm64" ] || {
    printf 'Parrot requires Apple Silicon.\n' >&2
    exit 1
}

PARROT_MACOS_MAJOR="$(sw_vers -productVersion | awk -F. '{print $1}')"
case "$PARROT_MACOS_MAJOR" in
    ''|*[!0-9]*) printf 'Could not determine the macOS version.\n' >&2; exit 1 ;;
esac
[ "$PARROT_MACOS_MAJOR" -ge 14 ] || {
    printf 'Parrot requires macOS 14 or newer.\n' >&2
    exit 1
}

for PARROT_COMMAND in curl tar shasum file install mktemp xattr; do
    command -v "$PARROT_COMMAND" >/dev/null 2>&1 || {
        printf 'Missing required command: %s\n' "$PARROT_COMMAND" >&2
        exit 1
    }
done

PARROT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/parrot-bootstrap.XXXXXX")"
PARROT_STAGE=""
parrot_cleanup() {
    rm -rf "$PARROT_TMP"
    if [ -n "$PARROT_STAGE" ]; then rm -f "$PARROT_STAGE"; fi
}
trap parrot_cleanup EXIT HUP INT TERM

PARROT_BASE_URL="https://github.com/${PARROT_REPO}/releases/download/${PARROT_TAG}"
curl --proto '=https' --tlsv1.2 --fail --location --show-error \
    "${PARROT_BASE_URL}/${PARROT_ASSET}" -o "${PARROT_TMP}/${PARROT_ASSET}"
curl --proto '=https' --tlsv1.2 --fail --location --show-error \
    "${PARROT_BASE_URL}/${PARROT_CHECKSUM}" -o "${PARROT_TMP}/${PARROT_CHECKSUM}"

(cd "$PARROT_TMP" && shasum -a 256 -c "$PARROT_CHECKSUM")

PARROT_CONTENTS="$(tar -tzf "${PARROT_TMP}/${PARROT_ASSET}")"
[ "$PARROT_CONTENTS" = "parrot" ] || {
    printf 'Unexpected archive contents: %s\n' "$PARROT_CONTENTS" >&2
    exit 1
}
tar -xzf "${PARROT_TMP}/${PARROT_ASSET}" -C "$PARROT_TMP"
[ -f "${PARROT_TMP}/parrot" ] && [ ! -L "${PARROT_TMP}/parrot" ] || {
    printf 'Archive did not contain a regular Parrot executable.\n' >&2
    exit 1
}

PARROT_FILE_INFO="$(file -b "${PARROT_TMP}/parrot")"
case "$PARROT_FILE_INFO" in
    *'Mach-O 64-bit executable arm64'*) ;;
    *) printf 'Unexpected executable type: %s\n' "$PARROT_FILE_INFO" >&2; exit 1 ;;
esac

if [ -f "$PARROT_PLIST" ]; then
    launchctl bootout "gui/$(id -u)" "$PARROT_PLIST" 2>/dev/null || true
fi

mkdir -p "$PARROT_INSTALL_DIR"
PARROT_STAGE="${PARROT_INSTALL_DIR}/.parrot.new.$$"
install -m 0755 "${PARROT_TMP}/parrot" "$PARROT_STAGE"
xattr -d com.apple.quarantine "$PARROT_STAGE" 2>/dev/null || true
mv -f "$PARROT_STAGE" "$PARROT_TARGET"
PARROT_STAGE=""

printf 'Installed verified Parrot %s at %s\n' "$PARROT_TAG" "$PARROT_TARGET"
```
<!-- END PARROT INSTALL SCRIPT -->

Next, guide the person through these interactive checkpoints one at a time:

1. Run `~/.local/bin/parrot setup`. If macOS opens Accessibility settings, ask
   the person to enable Parrot (or add `~/.local/bin/parrot` with the `+` button),
   then run setup again in a fresh process. Ask them to approve Microphone access.
2. Ask the person to set **System Settings → Keyboard → Press Globe/Fn key to →
   Do Nothing**.
3. Run `~/.local/bin/parrot models download whisper-base.en` and wait for the
   one-time model download and warmup to finish.
4. Run `~/.local/bin/parrot install --launch-at-login`.
5. Run `~/.local/bin/parrot doctor`. If any item is not clean, show the exact
   remediation and pause for the person to fix it before retrying.
6. Confirm that Parrot appears in the menu bar. Have the person focus a text
   field, double-tap Fn to start, speak, and tap Fn once to finish. Escape or `×`
   cancels a recording; `✓` finishes it.

Do not claim completion until the doctor is clean and the person confirms the
short dictation test. If setup attributes a permission to Codex or Terminal but
the background Parrot process still lacks it, add `~/.local/bin/parrot`
directly in the relevant Privacy & Security pane and retry.

## Manual fallback

Without Codex, paste the fenced Bash block into Terminal, then run the four
`~/.local/bin/parrot` commands above one at a time and follow the same macOS
permission instructions.
```

- [ ] **Step 4: Run the contract test and verify it passes**

Run:

```bash
scripts/test-bootstrap-doc.sh
git diff --check
```

Expected: `bootstrap contract passed: PARROT_BOOTSTRAP.md`, followed by a zero exit from `git diff --check`.

- [ ] **Step 5: Commit the bootstrap and its checker**

```bash
git add PARROT_BOOTSTRAP.md scripts/test-bootstrap-doc.sh
git commit -m "feat: add shareable Parrot bootstrap"
```

### Task 2: Verify and publish release `v0.1.0`

**Files:**
- Verify: `PARROT_BOOTSTRAP.md`
- Verify: `.build/release/parrot`
- Verify: `/Users/don/.local/bin/parrot`
- Generate in a temporary directory: `PARROT_BOOTSTRAP.md`, `parrot`, `parrot-macos-arm64.tar.gz`, `parrot-macos-arm64.tar.gz.sha256`

**Interfaces:**
- Consumes: the clean committed repository, the exact current Parrot binary, GitHub remote `origin`, and authenticated GitHub CLI access
- Produces: remote source branch `custom/dictionary-controls`, immutable tag `v0.1.0`, and a public GitHub release with exactly three assets

- [ ] **Step 1: Verify release identity and authentication without changing remote state**

Run:

```bash
git status --short --branch
git tag --list v0.1.0
git ls-remote --tags origin refs/tags/v0.1.0
git ls-remote --heads origin refs/heads/custom/dictionary-controls
gh auth status
```

Expected: clean `custom/dictionary-controls`, no local or remote `v0.1.0` tag, and authenticated access to `digimata/parrot`. Record whether the source branch already exists remotely before pushing it.

- [ ] **Step 2: Verify the exact current binary**

Run:

```bash
scripts/test-bootstrap-doc.sh
expected_binary_sha='b5f97e2aa475b0b93e9a53d45ba28fdacc4e5d67e038dc4c318f3640282455a0'
test "$(shasum -a 256 .build/release/parrot | awk '{print $1}')" = "$expected_binary_sha"
test "$(shasum -a 256 /Users/don/.local/bin/parrot | awk '{print $1}')" = "$expected_binary_sha"
file .build/release/parrot
codesign -dv --verbose=4 .build/release/parrot 2>&1
.build/release/parrot models list
.build/release/parrot doctor
git diff --check
git status --short
```

Expected: the bootstrap contract passes; both binaries match the pinned hash; `file` reports an arm64 Mach-O; `codesign` reports an ad-hoc signature; the expected three models are listed; every doctor check is clean; and Git remains clean.

- [ ] **Step 3: Package and verify the release assets locally**

Run:

```bash
release_stage=$(mktemp -d "${TMPDIR:-/tmp}/parrot-local-release.XXXXXX")
cp .build/release/parrot "$release_stage/parrot"
cp PARROT_BOOTSTRAP.md "$release_stage/PARROT_BOOTSTRAP.md"
(cd "$release_stage" && tar -czf parrot-macos-arm64.tar.gz parrot)
(cd "$release_stage" && shasum -a 256 parrot-macos-arm64.tar.gz > parrot-macos-arm64.tar.gz.sha256)
(cd "$release_stage" && shasum -a 256 -c parrot-macos-arm64.tar.gz.sha256)
test "$(tar -tzf "$release_stage/parrot-macos-arm64.tar.gz")" = "parrot"
extract_check=$(mktemp -d "${TMPDIR:-/tmp}/parrot-archive-check.XXXXXX")
tar -xzf "$release_stage/parrot-macos-arm64.tar.gz" -C "$extract_check"
test "$(shasum -a 256 "$extract_check/parrot" | awk '{print $1}')" = "$expected_binary_sha"
rm -rf "$extract_check"
```

Expected: archive checksum verification prints `OK`, the archive contains only `parrot`, and the extracted executable retains the pinned SHA-256.

- [ ] **Step 4: Publish the source branch and release**

Run:

```bash
git push --set-upstream origin custom/dictionary-controls
gh release create v0.1.0 \
    --target custom/dictionary-controls \
    --title 'Parrot v0.1.0' \
    --notes 'Shareable release of the current local Parrot dictation app. Apple Silicon and macOS 14 or newer are required. Download PARROT_BOOTSTRAP.md and give it to Codex for guided installation.' \
    "$release_stage/PARROT_BOOTSTRAP.md" \
    "$release_stage/parrot-macos-arm64.tar.gz" \
    "$release_stage/parrot-macos-arm64.tar.gz.sha256"
gh release view v0.1.0 --json tagName,targetCommitish,assets,url
```

Expected: GitHub publishes the branch and creates tag/release `v0.1.0` at that branch. The release has exactly:

```text
PARROT_BOOTSTRAP.md
parrot-macos-arm64.tar.gz
parrot-macos-arm64.tar.gz.sha256
```

- [ ] **Step 5: Independently verify the published assets**

Use a new temporary directory rather than the local `dist/` files:

```bash
release_check=$(mktemp -d "${TMPDIR:-/tmp}/parrot-release-check.XXXXXX")
gh release download v0.1.0 --dir "$release_check"
(cd "$release_check" && shasum -a 256 -c parrot-macos-arm64.tar.gz.sha256)
test "$(tar -tzf "$release_check/parrot-macos-arm64.tar.gz")" = "parrot"
cmp PARROT_BOOTSTRAP.md "$release_check/PARROT_BOOTSTRAP.md"
tar -xzf "$release_check/parrot-macos-arm64.tar.gz" -C "$release_check"
test "$(shasum -a 256 "$release_check/parrot" | awk '{print $1}')" = "$expected_binary_sha"
rm -rf "$release_check"
rm -rf "$release_stage"
```

Expected: checksum verification prints `OK`, the archive contains only `parrot`, the published bootstrap is byte-for-byte identical to the committed file, and the published executable has the pinned SHA-256.

- [ ] **Step 6: Record the final handoff information**

Run:

```bash
gh release view v0.1.0 --json url --jq .url
git fetch origin tag v0.1.0
git rev-parse v0.1.0^{}
shasum -a 256 PARROT_BOOTSTRAP.md
```

Expected: capture the release URL, tagged commit, and Markdown checksum for the final user handoff. Do not alter the bootstrap to include machine-local paths or a mutable latest-release URL.
