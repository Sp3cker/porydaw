#!/usr/bin/env bash
# Run every porydaw --*check harness against a private complete copy of its
# checked-in fixture project. Point this at an ASAN build
# (-DPORYDAW_ASAN=ON) to turn silent memory bugs into aborts with stack traces.
#
# usage: tools/run_checks.sh <porydaw-binary>
#
# env: PORYDAW_SAMPLE_CORPUS  optional built project for samplecheck's corpus
#      PORYDAW_SMF_STRESS    nonempty: run bounded SMF automation stress checks
#      ASAN_OPTIONS defaults to detect_leaks=0 (Qt's process-lifetime
#      allocations drown real leaks in noise).
set -u

SCRIPT_PATH=${BASH_SOURCE[0]}
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR=$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)
    SCRIPT_PATH=$(readlink "$SCRIPT_PATH")
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR=$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
DECOMP_FIXTURE="$REPO_ROOT/src/checks/fixtures/decompproject"
SONGSMK_FIXTURE="$REPO_ROOT/src/checks/fixtures/songsmkproject"

usage() {
    echo "usage: tools/run_checks.sh <porydaw-binary>" >&2
    exit 2
}
[ $# -eq 1 ] || usage
[ -x "$1" ] || { echo "run_checks: not executable: $1" >&2; exit 2; }

resolve_path() { # path
    local path="$1" directory
    while [ -L "$path" ]; do
        directory=$(cd -P "$(dirname "$path")" && pwd)
        path=$(readlink "$path")
        [[ "$path" != /* ]] && path="$directory/$path"
    done
    directory=$(cd -P "$(dirname "$path")" && pwd)
    printf '%s/%s\n' "$directory" "$(basename "$path")"
}

BIN=$(resolve_path "$1")
case "$BIN" in
    *.app/Contents/MacOS/*)
        BUILD_ROOT=$(cd -P "$(dirname "$BIN")/../../.." && pwd)
        ;;
    *)
        BUILD_ROOT=$(cd -P "$(dirname "$BIN")" && pwd)
        ;;
esac
MID2AGB="$BUILD_ROOT/mid2agb"
[ -x "$MID2AGB.exe" ] && MID2AGB="$MID2AGB.exe"
[ -x "$MID2AGB" ] || {
    echo "run_checks: missing in-tree mid2agb beside the build: $MID2AGB" >&2
    exit 2
}

[ -f "$DECOMP_FIXTURE/sound/song_table.inc" ] || {
    echo "run_checks: missing decomp fixture song table: $DECOMP_FIXTURE/sound/song_table.inc" >&2
    exit 2
}
[ -f "$DECOMP_FIXTURE/sound/songs/midi/midi.cfg" ] || {
    echo "run_checks: missing decomp fixture midi.cfg: $DECOMP_FIXTURE/sound/songs/midi/midi.cfg" >&2
    exit 2
}
[ -f "$SONGSMK_FIXTURE/sound/song_table.inc" ] || {
    echo "run_checks: missing songs.mk fixture song table: $SONGSMK_FIXTURE/sound/song_table.inc" >&2
    exit 2
}
[ -f "$SONGSMK_FIXTURE/songs.mk" ] || {
    echo "run_checks: missing songs.mk fixture: $SONGSMK_FIXTURE/songs.mk" >&2
    exit 2
}
[ ! -e "$SONGSMK_FIXTURE/sound/songs/midi/midi.cfg" ] || {
    echo "run_checks: songs.mk fixture must not contain midi.cfg" >&2
    exit 2
}

export QT_QPA_PLATFORM=offscreen

CHECK_TIMEOUT_SECONDS=90
TIMEOUT_BIN=""
for candidate in gtimeout timeout; do
    if ! command -v "$candidate" >/dev/null 2>&1; then
        continue
    fi
    timeout_version=$("$candidate" --version 2>/dev/null || true)
    case "$timeout_version" in
        *"GNU coreutils"*)
            TIMEOUT_BIN=$(command -v "$candidate")
            break
            ;;
    esac
done
if [ -z "$TIMEOUT_BIN" ]; then
    echo "run_checks: GNU timeout (or gtimeout) is required" >&2
    exit 2
fi
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT
LOG="$TMPROOT/log"

COPY_MODE=plain
PROBE_SOURCE="$TMPROOT/copy-probe-source"
PROBE_DEST="$TMPROOT/copy-probe-dest"
touch "$PROBE_SOURCE"
case "$(uname -s)" in
    Darwin)
        cp -c "$PROBE_SOURCE" "$PROBE_DEST" 2>/dev/null && COPY_MODE=clone
        ;;
    Linux)
        cp --reflink=auto "$PROBE_SOURCE" "$PROBE_DEST" 2>/dev/null && COPY_MODE=reflink
        ;;
esac
rm -f "$PROBE_SOURCE" "$PROBE_DEST"

copy_path() { # source destination
    case "$COPY_MODE" in
        clone) cp -cR "$1" "$2" ;;
        reflink) cp -a --reflink=auto "$1" "$2" ;;
        *) cp -R "$1" "$2" ;;
    esac
}

fails=()

report() { # name exit-status
    if [ "$2" -ne 0 ]; then
        fails+=("$1")
        echo "FAIL: $1 (exit $2)"
        tail -40 "$LOG"
    else
        echo "ok: $1 — $(tail -1 "$LOG")"
    fi
}

run() { # name fixture|- harness-args... (SCRATCH = fresh path)
    local name="$1" fixture="$2"
    shift 2
    local scratch="$TMPROOT/$name"
    rm -rf "$scratch"
    if [ "$fixture" != "-" ]; then
        copy_path "$fixture" "$scratch"
    fi

    local args=() arg
    for arg in "$@"; do
        [ "$arg" = "SCRATCH" ] && arg="$scratch"
        args+=("$arg")
    done
    "$TIMEOUT_BIN" -k 5s "${CHECK_TIMEOUT_SECONDS}s" \
        "$BIN" "${args[@]}" >"$LOG" 2>&1
    local status=$?
    if [ "$status" -eq 124 ]; then
        echo "run_checks: $name exceeded ${CHECK_TIMEOUT_SECONDS}s" >>"$LOG"
    fi
    report "$name" "$status"
}

run roundtrip        "$DECOMP_FIXTURE" --roundtrip SCRATCH "$MID2AGB"
run editcheck        "$DECOMP_FIXTURE" --editcheck SCRATCH
run scalecheck       "$DECOMP_FIXTURE" --scalecheck SCRATCH
run viewcheck        "$DECOMP_FIXTURE" --viewcheck SCRATCH
run selftest         "$DECOMP_FIXTURE" --selftest SCRATCH mus_littleroot_test
run savecheck        "$DECOMP_FIXTURE" --savecheck SCRATCH mus_route101 "$MID2AGB"
run onboardcheck     "$DECOMP_FIXTURE" --onboardcheck SCRATCH "$MID2AGB"
run vgcheck          "$DECOMP_FIXTURE" --vgcheck SCRATCH mus_gym
run vgsavecheck      "$DECOMP_FIXTURE" --vgsavecheck SCRATCH mus_route101
run exportcheck-loop "$DECOMP_FIXTURE" --exportcheck SCRATCH mus_route101
run exportcheck-tail "$DECOMP_FIXTURE" --exportcheck SCRATCH mus_route102
run sessioncheck     "$DECOMP_FIXTURE" --sessioncheck SCRATCH mus_route101
run tabcheck         "$DECOMP_FIXTURE" --tabcheck SCRATCH mus_route101 mus_petalburg
run eventviewcheck   "$DECOMP_FIXTURE" --eventviewcheck SCRATCH
run rollcheck        "$DECOMP_FIXTURE" --rollcheck SCRATCH mus_route101
run mkcheck          "$SONGSMK_FIXTURE" --mkcheck SCRATCH mus_aqua_magma_hideout
run loopcheck        - --loopcheck
run ignorecheck      - --ignorecheck SCRATCH
run primecheck       - --primecheck
run smfcheck         - --smfcheck
if [ -n "${PORYDAW_SMF_STRESS:-}" ]; then
    run smfstresscheck - --smfstresscheck
fi
run transportcheck   - --transportcheck
run audiocheck       - --audiocheck
run clickcheck       - --clickcheck
run resonancecheck   - --resonancecheck
run trackactivitycheck - --trackactivitycheck
run trackactivitymetercheck - --trackactivitymetercheck
run keymapcheck      - --keymapcheck
run polycheck        - --polycheck

# samplecheck creates its own project and requires a path that does not exist.
samplecheck_args=(--samplecheck SCRATCH)
if [ -n "${PORYDAW_SAMPLE_CORPUS:-}" ]; then
    samplecheck_args+=("$PORYDAW_SAMPLE_CORPUS")
fi
run samplecheck - "${samplecheck_args[@]}"

echo
if [ ${#fails[@]} -ne 0 ]; then
    echo "run_checks: FAIL (${#fails[@]}): ${fails[*]}"
    exit 1
fi
echo "run_checks: PASS (all harnesses)"
