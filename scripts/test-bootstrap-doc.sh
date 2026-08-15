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
require_script 'PARROT_BINARY_SHA256="b5f97e2aa475b0b93e9a53d45ba28fdacc4e5d67e038dc4c318f3640282455a"'
require_script 'uname -s'
require_script 'uname -m'
require_script 'sw_vers -productVersion'
require_script 'shasum -a 256 -c'
require_script 'tar -tzf'
require_script 'shasum -a 256 "${PARROT_TMP}/parrot"'
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
executable_checksum_line=$(grep -nF 'shasum -a 256 "${PARROT_TMP}/parrot"' "$script" | head -1 | cut -d: -f1)
xattr_line=$(grep -nF 'xattr -d com.apple.quarantine' "$script" | head -1 | cut -d: -f1)
[ "$checksum_line" -lt "$extract_line" ] || fail "archive is extracted before checksum verification"
[ "$extract_line" -lt "$executable_checksum_line" ] || fail "binary checksum is checked before extraction"
[ "$executable_checksum_line" -lt "$xattr_line" ] || fail "quarantine is removed before pinned binary verification"

printf 'bootstrap contract passed: %s\n' "$doc"
