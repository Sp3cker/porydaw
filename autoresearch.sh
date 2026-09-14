#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
exec deno run --allow-read --allow-run --allow-env tools/benchmark_cli.ts
