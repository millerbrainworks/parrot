#!/usr/bin/env bash
set -u
set -o pipefail

doc="${1:-PARROT_BOOTSTRAP.md}"

fail() {
    printf 'bootstrap contract failed: %s\n' "$*" >&2
    exit 1
}

[ -f "$doc" ] || fail "missing $doc"

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
binary_fixture="${repo_root}/.build/release/parrot"
[ -f "$binary_fixture" ] || fail "missing binary fixture: $binary_fixture"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/parrot-doc-test.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
install_script="${scratch}/install.sh"
launch_script="${scratch}/launch-agent.sh"

extract_script() {
    begin_marker="$1"
    end_marker="$2"
    destination="$3"
    awk -v begin_marker="$begin_marker" -v end_marker="$end_marker" '
        $0 == begin_marker { capture = 1; next }
        $0 == end_marker { capture = 0 }
        capture { print }
    ' "$doc" | sed '1{/^```bash$/d;}; ${/^```$/d;}' > "$destination"
}

extract_script \
    '<!-- BEGIN PARROT INSTALL SCRIPT -->' \
    '<!-- END PARROT INSTALL SCRIPT -->' \
    "$install_script"
extract_script \
    '<!-- BEGIN PARROT LAUNCHAGENT SCRIPT -->' \
    '<!-- END PARROT LAUNCHAGENT SCRIPT -->' \
    "$launch_script"

[ -s "$install_script" ] || fail "embedded install script is empty"
bash -n "$install_script" || fail "embedded install script has invalid Bash syntax"
if [ -s "$launch_script" ]; then
    bash -n "$launch_script" || fail "embedded LaunchAgent script has invalid Bash syntax"
fi

fixture_prepare() {
    fixture="$1"
    fixture_kind="${2:-valid}"
    mkdir -p \
        "$fixture/bin" \
        "$fixture/downloads" \
        "$fixture/home" \
        "$fixture/tmp" \
        "$fixture/payload"

    cp "$binary_fixture" "$fixture/payload/parrot"
    case "$fixture_kind" in
        valid|bad-checksum)
            /usr/bin/tar -czf "$fixture/downloads/parrot-macos-arm64.tar.gz" \
                -C "$fixture/payload" parrot
            ;;
        wrong-binary)
            printf 'not the pinned Parrot binary\n' > "$fixture/payload/parrot"
            /usr/bin/tar -czf "$fixture/downloads/parrot-macos-arm64.tar.gz" \
                -C "$fixture/payload" parrot
            ;;
        extra-layout)
            printf 'unexpected archive member\n' > "$fixture/payload/README.txt"
            /usr/bin/tar -czf "$fixture/downloads/parrot-macos-arm64.tar.gz" \
                -C "$fixture/payload" parrot README.txt
            ;;
        *)
            printf 'unknown fixture kind: %s\n' "$fixture_kind" >&2
            return 1
            ;;
    esac

    (
        cd "$fixture/downloads" || exit 1
        /usr/bin/shasum -a 256 parrot-macos-arm64.tar.gz > \
            parrot-macos-arm64.tar.gz.sha256
    ) || return 1
    if [ "$fixture_kind" = "bad-checksum" ]; then
        printf '%064d  parrot-macos-arm64.tar.gz\n' 0 > \
            "$fixture/downloads/parrot-macos-arm64.tar.gz.sha256"
    fi

    cat > "$fixture/bin/curl" <<'FAKE_CURL'
#!/bin/bash
set -u
url=''
output=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o)
            output="$2"
            shift 2
            ;;
        http://*|https://*)
            url="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done
printf '%s\n' "$url" >> "$PARROT_FIXTURE_URL_LOG"
name="${url##*/}"
case "$name" in
    parrot-macos-arm64.tar.gz|parrot-macos-arm64.tar.gz.sha256) ;;
    *) printf 'fixture rejected URL: %s\n' "$url" >&2; exit 64 ;;
esac
cp "$PARROT_FIXTURE_DOWNLOADS/$name" "$output"
FAKE_CURL

    cat > "$fixture/bin/launchctl" <<'FAKE_LAUNCHCTL'
#!/bin/bash
set -u
command_name="${1:-}"
printf '%s\n' "$*" >> "$PARROT_FIXTURE_LAUNCHCTL_LOG"
case "$command_name" in
    print)
        case "$PARROT_FIXTURE_LAUNCH_MODE" in
            loaded-bootout-fail)
                printf 'fixture service is loaded\n'
                exit 0
                ;;
            registered)
                if [ -f "$PARROT_FIXTURE_REGISTERED" ]; then
                    printf 'fixture service is loaded\n'
                    exit 0
                fi
                ;;
        esac
        printf 'fixture service is absent\n' >&2
        exit 113
        ;;
    bootout)
        if [ "$PARROT_FIXTURE_LAUNCH_MODE" = "loaded-bootout-fail" ]; then
            printf 'fixture bootout was denied\n' >&2
            exit 55
        fi
        rm -f "$PARROT_FIXTURE_REGISTERED"
        exit 0
        ;;
esac
printf 'unexpected launchctl invocation: %s\n' "$*" >&2
exit 65
FAKE_LAUNCHCTL

    cat > "$fixture/bin/xattr" <<'FAKE_XATTR'
#!/bin/bash
set -u
printf '%s\n' "$*" >> "$PARROT_FIXTURE_XATTR_LOG"
exit 0
FAKE_XATTR

    cat > "$fixture/bin/file" <<'FAKE_FILE'
#!/bin/bash
printf 'Mach-O 64-bit executable arm64\n'
FAKE_FILE

    cat > "$fixture/bin/uname" <<'FAKE_UNAME'
#!/bin/bash
case "${1:-}" in
    -s) printf 'Darwin\n' ;;
    -m) printf 'arm64\n' ;;
    *) printf 'Darwin\n' ;;
esac
FAKE_UNAME

    cat > "$fixture/bin/sw_vers" <<'FAKE_SW_VERS'
#!/bin/bash
if [ "${1:-}" = "-productVersion" ]; then
    printf '14.7.1\n'
else
    exit 64
fi
FAKE_SW_VERS

    chmod +x "$fixture/bin/"*
    : > "$fixture/urls.log"
    : > "$fixture/launchctl.log"
    : > "$fixture/xattr.log"
}

fixture_env() {
    fixture="$1"
    launch_mode="${2:-unloaded}"
    env \
        HOME="$fixture/home" \
        TMPDIR="$fixture/tmp" \
        PATH="$fixture/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        PARROT_FIXTURE_DOWNLOADS="$fixture/downloads" \
        PARROT_FIXTURE_URL_LOG="$fixture/urls.log" \
        PARROT_FIXTURE_LAUNCHCTL_LOG="$fixture/launchctl.log" \
        PARROT_FIXTURE_XATTR_LOG="$fixture/xattr.log" \
        PARROT_FIXTURE_LAUNCH_MODE="$launch_mode" \
        PARROT_FIXTURE_REGISTERED="$fixture/registered" \
        "${@:3}"
}

run_install() {
    fixture="$1"
    launch_mode="${2:-unloaded}"
    fixture_env "$fixture" "$launch_mode" /bin/bash "$install_script"
}

assert_tmp_clean() {
    fixture="$1"
    [ -z "$(find "$fixture/tmp" -mindepth 1 -maxdepth 1 -print -quit)" ]
}

show_failure_output() {
    output_file="$1"
    if [ -s "$output_file" ]; then
        sed 's/^/    | /' "$output_file" >&2
    fi
}

test_exact_pinned_release_urls() {
    # Mutation caught: rolling the tag back or downloading either asset elsewhere.
    fixture="$scratch/exact-release-urls"
    fixture_prepare "$fixture" valid || return 1
    run_install "$fixture" > "$fixture/output" 2>&1 || {
        show_failure_output "$fixture/output"
        return 1
    }
    [ "$(wc -l < "$fixture/urls.log" | tr -d ' ')" = "2" ] || return 1
    [ "$(sed -n '1p' "$fixture/urls.log")" = \
        "https://github.com/millerbrainworks/parrot/releases/download/v0.1.1/parrot-macos-arm64.tar.gz" ] || return 1
    [ "$(sed -n '2p' "$fixture/urls.log")" = \
        "https://github.com/millerbrainworks/parrot/releases/download/v0.1.1/parrot-macos-arm64.tar.gz.sha256" ] || return 1
}

test_happy_path_stages_verified_binary() {
    # Mutation caught: skipping the staged final rename leaves the old target installed.
    fixture="$scratch/happy-staged-install"
    fixture_prepare "$fixture" valid || return 1
    mkdir -p "$fixture/home/.local/bin"
    printf 'old executable\n' > "$fixture/home/.local/bin/parrot"
    run_install "$fixture" > "$fixture/output" 2>&1 || {
        show_failure_output "$fixture/output"
        return 1
    }
    actual_sha="$(/usr/bin/shasum -a 256 "$fixture/home/.local/bin/parrot" | awk '{print $1}')"
    [ "$actual_sha" = "b5f97e2aa475b0b93e9a53d45ba28fdacc4e5d67e038dc4c318f3640282455a0" ] || return 1
    grep -Eq '/\.parrot\.new\.[0-9]+$' "$fixture/xattr.log" || return 1
    [ -z "$(find "$fixture/home/.local/bin" -name '.parrot.new.*' -print -quit)" ] || return 1
    assert_tmp_clean "$fixture"
}

test_corrupt_archive_checksum_is_rejected() {
    # Mutation caught: deleting the archive checksum command installs corrupt input.
    fixture="$scratch/bad-archive-checksum"
    fixture_prepare "$fixture" bad-checksum || return 1
    if run_install "$fixture" > "$fixture/output" 2>&1; then
        return 1
    fi
    [ ! -e "$fixture/home/.local/bin/parrot" ] || return 1
    assert_tmp_clean "$fixture"
}

test_wrong_extracted_binary_digest_is_rejected() {
    # Mutation caught: trusting the archive checksum without pinning the executable.
    fixture="$scratch/wrong-binary-digest"
    fixture_prepare "$fixture" wrong-binary || return 1
    if run_install "$fixture" > "$fixture/output" 2>&1; then
        return 1
    fi
    [ ! -e "$fixture/home/.local/bin/parrot" ] || return 1
    assert_tmp_clean "$fixture"
}

test_unexpected_archive_layout_is_rejected() {
    # Mutation caught: accepting extra archive members alongside the root executable.
    fixture="$scratch/extra-archive-layout"
    fixture_prepare "$fixture" extra-layout || return 1
    if run_install "$fixture" > "$fixture/output" 2>&1; then
        return 1
    fi
    [ ! -e "$fixture/home/.local/bin/parrot" ] || return 1
    assert_tmp_clean "$fixture"
}

test_loaded_service_bootout_failure_blocks_replacement() {
    # Mutation caught: restoring `bootout ... || true` lets a loaded old process survive.
    fixture="$scratch/bootout-failure"
    fixture_prepare "$fixture" valid || return 1
    mkdir -p "$fixture/home/.local/bin" "$fixture/home/Library/LaunchAgents"
    printf 'old executable\n' > "$fixture/home/.local/bin/parrot"
    printf '<plist/>\n' > "$fixture/home/Library/LaunchAgents/com.digimata.parrot.plist"
    if run_install "$fixture" loaded-bootout-fail > "$fixture/output" 2>&1; then
        return 1
    fi
    [ "$(cat "$fixture/home/.local/bin/parrot")" = "old executable" ] || return 1
    grep -Fq 'fixture bootout was denied' "$fixture/output" || return 1
    grep -Fq '/tmp/parrot.out.log' "$fixture/output" || return 1
    grep -Fq '/tmp/parrot.err.log' "$fixture/output" || return 1
    assert_tmp_clean "$fixture"
}

install_fake_parrot() {
    fixture="$1"
    mkdir -p "$fixture/home/.local/bin"
    cat > "$fixture/home/.local/bin/parrot" <<'FAKE_PARROT'
#!/bin/bash
set -u
printf 'fixture parrot install output\n'
if [ "$PARROT_FIXTURE_LAUNCH_MODE" = "registered" ]; then
    : > "$PARROT_FIXTURE_REGISTERED"
fi
exit 0
FAKE_PARROT
    chmod +x "$fixture/home/.local/bin/parrot"
}

run_launch_script_by_pasting() {
    fixture="$1"
    launch_mode="$2"
    fixture_env "$fixture" "$launch_mode" /bin/bash -c '
        . "$1"
        launch_status=$?
        [ "${PARROT_SERVICE+x}" != x ] || {
            printf "launch script leaked variables into the calling shell\n" >&2
            exit 92
        }
        exit "$launch_status"
    ' fixture-shell "$launch_script"
}

test_post_install_missing_launchagent_is_rejected() {
    # Mutation caught: omitting the post-install `launchctl print` accepts a warning-only install.
    fixture="$scratch/missing-post-install-service"
    fixture_prepare "$fixture" valid || return 1
    install_fake_parrot "$fixture" || return 1
    [ -s "$launch_script" ] || return 1
    if run_launch_script_by_pasting "$fixture" missing > "$fixture/output" 2>&1; then
        return 1
    fi
    grep -Fq 'fixture parrot install output' "$fixture/output" || return 1
    grep -Fq 'fixture service is absent' "$fixture/output" || return 1
    grep -Fq '/tmp/parrot.out.log' "$fixture/output" || return 1
    grep -Fq '/tmp/parrot.err.log' "$fixture/output" || return 1
}

test_registered_launchagent_is_accepted() {
    # Mutation caught: checking the wrong service label rejects a real registration.
    fixture="$scratch/registered-post-install-service"
    fixture_prepare "$fixture" valid || return 1
    install_fake_parrot "$fixture" || return 1
    [ -s "$launch_script" ] || return 1
    run_launch_script_by_pasting "$fixture" registered > "$fixture/output" 2>&1 || {
        show_failure_output "$fixture/output"
        return 1
    }
    [ -f "$fixture/registered" ] || return 1
    grep -Fq 'gui/' "$fixture/launchctl.log" || return 1
    grep -Fq '/com.digimata.parrot' "$fixture/launchctl.log" || return 1
}

test_rosetta_translated_shell_is_accepted() {
    # Mutation caught: rejecting every x86_64 uname result also rejects Rosetta on Apple Silicon.
    fixture="$scratch/rosetta-translated-shell"
    fixture_prepare "$fixture" valid || return 1
    rm "$fixture/bin/uname"
    fixture_env "$fixture" unloaded /usr/bin/arch -x86_64 /bin/bash "$install_script" \
        > "$fixture/output" 2>&1 || {
        show_failure_output "$fixture/output"
        return 1
    }
    actual_sha="$(/usr/bin/shasum -a 256 "$fixture/home/.local/bin/parrot" | awk '{print $1}')"
    [ "$actual_sha" = "b5f97e2aa475b0b93e9a53d45ba28fdacc4e5d67e038dc4c318f3640282455a0" ] || return 1
}

test_pasted_install_block_is_bounded_bash() {
    # Mutation caught: removing the explicit Bash wrapper leaks variables and defers cleanup.
    fixture="$scratch/bounded-pasted-install"
    fixture_prepare "$fixture" valid || return 1
    if ! fixture_env "$fixture" unloaded /bin/bash -c '
        . "$1"
        [ "${PARROT_TAG+x}" != x ] || {
            printf "install script leaked variables into the calling shell\n" >&2
            exit 91
        }
        [ -z "$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
            printf "install script deferred temporary cleanup\n" >&2
            exit 90
        }
    ' fixture-shell "$install_script" > "$fixture/output" 2>&1; then
        show_failure_output "$fixture/output"
        return 1
    fi
}

test_static_contract_supplements() {
    # Supplemental source guards; behavioral cases above own the safety claims.
    [ "$(grep -Fxc '<!-- BEGIN PARROT INSTALL SCRIPT -->' "$doc" || true)" -eq 1 ] || return 1
    [ "$(grep -Fxc '<!-- END PARROT INSTALL SCRIPT -->' "$doc" || true)" -eq 1 ] || return 1
    [ "$(grep -Fxc '<!-- BEGIN PARROT LAUNCHAGENT SCRIPT -->' "$doc" || true)" -eq 1 ] || return 1
    [ "$(grep -Fxc '<!-- END PARROT LAUNCHAGENT SCRIPT -->' "$doc" || true)" -eq 1 ] || return 1
    grep -Fq 'Give this entire file to Codex' "$doc" || return 1
    grep -Fq '~/.local/bin/parrot setup' "$doc" || return 1
    grep -Fq '~/.local/bin/parrot models download whisper-base.en' "$doc" || return 1
    grep -Fq '~/.local/bin/parrot install --launch-at-login' "$doc" || return 1
    grep -Fq '~/.local/bin/parrot doctor' "$doc" || return 1
    grep -Fq 'Press Globe/Fn key to' "$doc" || return 1
    grep -Fq 'PARROT_REPO="millerbrainworks/parrot"' "$install_script" || return 1
    grep -Fq 'PARROT_TAG="v0.1.1"' "$install_script" || return 1
    grep -Fq 'PARROT_ASSET="parrot-macos-arm64.tar.gz"' "$install_script" || return 1
    grep -Fq 'PARROT_BINARY_SHA256="b5f97e2aa475b0b93e9a53d45ba28fdacc4e5d67e038dc4c318f3640282455a0"' "$install_script" || return 1
    grep -Fq '/usr/sbin/sysctl -in sysctl.proc_translated' "$install_script" || return 1
    grep -Fq 'PARROT_TARGET="${HOME}/.local/bin/parrot"' "$install_script" || return 1
    grep -Fq 'xattr -d com.apple.quarantine' "$install_script" || return 1
    [ "$(sed -n '1p' "$install_script")" = "/bin/bash <<'PARROT_INSTALL'" ] || return 1
    [ "$(tail -n 1 "$install_script")" = "PARROT_INSTALL" ] || return 1
    [ "$(sed -n '1p' "$launch_script")" = "/bin/bash <<'PARROT_LAUNCHAGENT'" ] || return 1
    [ "$(tail -n 1 "$launch_script")" = "PARROT_LAUNCHAGENT" ] || return 1
    if grep -Fq 'sudo' "$doc"; then return 1; fi
    if grep -Eq '/Users/don|/Volumes/MIAU' "$doc"; then return 1; fi
}

failures=0
tests_run=0

run_case() {
    case_name="$1"
    case_function="$2"
    if [ -n "${PARROT_TEST_CASE:-}" ] && [ "$PARROT_TEST_CASE" != "$case_name" ]; then
        return
    fi
    tests_run=$((tests_run + 1))
    if "$case_function"; then
        printf 'ok - %s\n' "$case_name"
    else
        printf 'not ok - %s\n' "$case_name" >&2
        failures=$((failures + 1))
    fi
}

run_case exact-pinned-release-urls test_exact_pinned_release_urls
run_case happy-path-staged-install test_happy_path_stages_verified_binary
run_case corrupt-archive-checksum-rejected test_corrupt_archive_checksum_is_rejected
run_case wrong-extracted-binary-digest-rejected test_wrong_extracted_binary_digest_is_rejected
run_case unexpected-archive-layout-rejected test_unexpected_archive_layout_is_rejected
run_case loaded-service-bootout-failure-rejected test_loaded_service_bootout_failure_blocks_replacement
run_case post-install-missing-launchagent-rejected test_post_install_missing_launchagent_is_rejected
run_case registered-launchagent-accepted test_registered_launchagent_is_accepted
run_case rosetta-translated-shell-accepted test_rosetta_translated_shell_is_accepted
run_case pasted-blocks-use-bounded-bash test_pasted_install_block_is_bounded_bash
run_case static-contract-supplements test_static_contract_supplements

[ "$tests_run" -gt 0 ] || fail "unknown PARROT_TEST_CASE: ${PARROT_TEST_CASE:-}"
if [ "$failures" -ne 0 ]; then
    printf 'bootstrap behavioral checks failed: %d of %d\n' "$failures" "$tests_run" >&2
    exit 1
fi

printf 'bootstrap behavioral checks passed: %d cases for %s\n' "$tests_run" "$doc"
