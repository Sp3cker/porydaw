#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
deno task build:app >&2
python3 tools/startup_bench/run.py --runs 7 --warmup 1
