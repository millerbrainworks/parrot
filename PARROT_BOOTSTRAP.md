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
PARROT_BINARY_SHA256="b5f97e2aa475b0b93e9a53d45ba28fdacc4e5d67e038dc4c318f3640282455a"
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
PARROT_BINARY_SHA256_ACTUAL="$(shasum -a 256 "${PARROT_TMP}/parrot" | awk '{print $1}')"
[ "$PARROT_BINARY_SHA256_ACTUAL" = "$PARROT_BINARY_SHA256" ] || {
    printf 'Unexpected Parrot executable checksum: %s\n' "$PARROT_BINARY_SHA256_ACTUAL" >&2
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
