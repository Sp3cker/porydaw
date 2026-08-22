#!/usr/bin/env bash
# Autoresearch harness: profiles decomp project indexing (DecompProject::open)
# against the hearth-usb checkout on the ESD-USB stick.
#
# Determinism: fixed project root, fixed run count (PORYDAW_BENCH_ROOT /
# PORYDAW_BENCH_RUNS override), median-of-runs primary metric, and the
# benchmark aborts if two runs ever assemble a different index.
#
# Trace discipline: collects no traces and writes nothing to the indexed
# volume — the FAT32 stick has no room for stray artifacts. All build
# artifacts stay under ./build/.
set -euo pipefail
cd "$(dirname "$0")"

ROOT="${PORYDAW_BENCH_ROOT:-/Volumes/ESD-USB/hearth-usb}"
RUNS="${PORYDAW_BENCH_RUNS:-7}"

if [ ! -d "$ROOT" ]; then
  echo "autoresearch: indexed project not mounted: $ROOT" >&2
  exit 1
fi

# Build lane prints progress on stderr; stdout carries only METRIC/ASI lines.
deno task build:bench >&2

exec ./build/porydaw_index_bench --root "$ROOT" --runs "$RUNS"
