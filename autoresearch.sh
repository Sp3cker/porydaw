#!/bin/bash
# autoresearch harness: wall time of a clean `porydaw` app build (Debug),
# mirroring `deno task build:app` configure arguments. Offline: QtBridge and
# swift-syntax are vendored under autoresearch/vendor/.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD
VENDOR="$ROOT/autoresearch/vendor"
LOG_DIR="$ROOT/autoresearch/logs"
RUNS="${AUTORESEARCH_RUNS:-3}"

PORYAAAA_PKG="$ROOT/external/poryaaaa/packages/poryaaaa"
if [ ! -f "$PORYAAAA_PKG/plugin/porydaw/CMakeLists.txt" ]; then
    MAIN_ROOT=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
    PORYAAAA_PKG="$MAIN_ROOT/external/poryaaaa/packages/poryaaaa"
fi
if [ ! -f "$PORYAAAA_PKG/plugin/porydaw/CMakeLists.txt" ]; then
    echo "autoresearch: poryaaaa package not found" >&2
    exit 1
fi

SWIFT_ARGS=()
if [ -s "$ROOT/.swift-version" ] && [ -x "$HOME/.swiftly/bin/swiftc" ]; then
    SWIFT_ARGS=("-DCMAKE_Swift_COMPILER=$HOME/.swiftly/bin/swiftc")
fi

NPROC=$(sysctl -n hw.ncpu)

now_s() { python3 -c 'import time;print(f"{time.monotonic():.6f}")'; }

warm_page_cache() {
    find "$ROOT/src" "$ROOT/cmake" "$VENDOR" "$PORYAAAA_PKG" \
        -type f -exec cat {} + >/dev/null 2>&1 || true
}

clean_scratch() {
    # Late writes from a just-finished build can make rm -rf lose files; retry.
    local dir=$1 attempt
    for attempt in 1 2 3 4 5; do
        rm -rf "$dir" 2>/dev/null || true
        [ ! -e "$dir" ] && return 0
        sleep 1
    done
    rm -rf "$dir" 2>/dev/null || true
}

# One clean build in a fresh directory. Prints "configure_s compile_s total_s".
run_once() {
    local build_dir=$1
    mkdir -p "$LOG_DIR"
    warm_page_cache

    local t0 t1 t2
    t0=$(now_s)
    cmake -S "$ROOT" -B "$build_dir" -G Ninja \
        -DCMAKE_BUILD_TYPE=Debug \
        -DPORYDAW_BUILD_CHECKS=OFF \
        -DPORYAAAA_DIR="$PORYAAAA_PKG" \
        -DFETCHCONTENT_SOURCE_DIR_QTBRIDGE="$VENDOR/qtbridge-src" \
        -DCMAKE_Swift_FLAGS="${CMAKE_Swift_FLAGS:-} -experimental-emit-module-separately" \
        "${SWIFT_ARGS[@]}" \
        >"$build_dir.configure.log" 2>&1 || return 1
    t1=$(now_s)

    cmake --build "$build_dir" -j "$NPROC" --target porydaw \
        >"$build_dir.build.log" 2>&1 || return 1
    t2=$(now_s)

    [ -x "$build_dir/porydaw.app/Contents/MacOS/porydaw" ] || return 1

    python3 - "$t0" "$t1" "$t2" <<'EOF'
import sys
t0, t1, t2 = (float(v) for v in sys.argv[1:4])
print(f"{t1 - t0:.6f} {t2 - t1:.6f} {t2 - t0:.6f}")
EOF
}

# Collect any scratch dirs left by earlier invocations now that no build is
# running inside them.
for stale in "$ROOT"/build-bench-*; do
    [ -e "$stale" ] && clean_scratch "$stale" || true
done
for stale in "$ROOT"/build-bench-*.log; do
    [ -e "$stale" ] && rm -f "$stale"
done

declare -a CONFIGURE_TIMES COMPILE_TIMES TOTAL_TIMES
for i in $(seq 1 "$RUNS"); do
    result=""
    # A clean build in a fresh dir may retry once: the Swift+Ninja graph
    # occasionally drops an output directory mid-build.
    for attempt in 1 2; do
        build_dir="$ROOT/build-bench-$$-$i-$attempt"
        clean_scratch "$build_dir"
        if result=$(run_once "$build_dir"); then
            mv "$build_dir.configure.log" "$LOG_DIR/configure.$i.log" 2>/dev/null || true
            mv "$build_dir.build.log" "$LOG_DIR/build.$i.log" 2>/dev/null || true
            break
        fi
        if [ "$attempt" -eq 2 ]; then
            tail -40 "$build_dir.build.log" >&2 2>/dev/null || true
            tail -40 "$build_dir.configure.log" >&2 2>/dev/null || true
            echo "autoresearch: run $i failed twice" >&2
            exit 1
        fi
    done
    read -r cfg comp tot <<<"$result"
    CONFIGURE_TIMES+=("$cfg")
    COMPILE_TIMES+=("$comp")
    TOTAL_TIMES+=("$tot")
done

for stale in "$ROOT"/build-bench-*; do
    [ -e "$stale" ] && clean_scratch "$stale" || true
done
for stale in "$ROOT"/build-bench-*.log; do
    [ -e "$stale" ] && rm -f "$stale"
done

python3 - <<EOF
vals = {
    "configure_time_s": [float(v) for v in "${CONFIGURE_TIMES[*]}".split()],
    "compile_time_s": [float(v) for v in "${COMPILE_TIMES[*]}".split()],
    "build_time_s": [float(v) for v in "${TOTAL_TIMES[*]}".split()],
}
for name in ("configure_time_s", "compile_time_s", "build_time_s"):
    xs = sorted(vals[name])
    mid = len(xs) // 2
    med = xs[mid] if len(xs) % 2 else (xs[mid - 1] + xs[mid]) / 2
    print(f"METRIC {name}={med:.3f}")
EOF
