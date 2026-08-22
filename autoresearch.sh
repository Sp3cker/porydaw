#!/usr/bin/env bash
# Autoresearch harness: profiles decomp project indexing (DecompProject::open)
# against the hearth-usb checkout on the ESD-USB stick.
#
# Determinism: fixed project root, fixed run count (PORYDAW_BENCH_ROOT /
# PORYDAW_BENCH_RUNS override), median-of-runs primary metric, and the
# benchmark aborts if two runs ever assemble a different index. The
# persistent-index store (PORYDAW_INDEX_BACKEND: sqlite|json|none) is wiped
# before every invocation so the first open always measures scan+build and
# the rest measure warm loads.
#
# Trace discipline: collects no traces and writes nothing to the indexed
# volume — the FAT32 stick has no room for stray artifacts. All build and
# store artifacts stay under ./build/.
set -euo pipefail
cd "$(dirname "$0")"

ROOT="${PORYDAW_BENCH_ROOT:-/Volumes/ESD-USB/hearth-usb}"
RUNS="${PORYDAW_BENCH_RUNS:-7}"
BACKEND="${PORYDAW_INDEX_BACKEND:-json}"
CACHE_DIR="build/bench-cache"

if [ ! -d "$ROOT" ]; then
  echo "autoresearch: indexed project not mounted: $ROOT" >&2
  exit 1
fi

# Build lane prints progress on stderr; stdout carries only METRIC/ASI lines.
deno task build:bench >&2

rm -rf "$CACHE_DIR"
mkdir -p "$CACHE_DIR"

exec ./build/porydaw_index_bench --root "$ROOT" --runs "$RUNS" \
  --backend "$BACKEND" --cache-dir "$CACHE_DIR"
