#!/usr/bin/env bash
set -euo pipefail

readonly project_root="/Users/sallegrezza/dev/pokeemerald-expansion"
readonly song="mus_poke_center"
readonly build_dir="build"

if [[ ! -f "$project_root/sound/song_table.inc" ]]; then
  echo "autoresearch: missing fixed pokeemerald-expansion fixture at $project_root" >&2
  exit 2
fi

if [[ ! -f "$build_dir/CMakeCache.txt" ]]; then
  cmake -S . -B "$build_dir" -DBUILD_TESTING=ON >&2
fi
cmake --build "$build_dir" --target porydaw -j8 >&2

if [[ -x "$build_dir/porydaw.app/Contents/MacOS/porydaw" ]]; then
  binary="$build_dir/porydaw.app/Contents/MacOS/porydaw"
elif [[ -x "$build_dir/porydaw" ]]; then
  binary="$build_dir/porydaw"
else
  echo "autoresearch: porydaw binary was not produced" >&2
  exit 2
fi

log=$(mktemp)
trap 'rm -f "$log"' EXIT
set +e
QT_QPA_PLATFORM=offscreen "$binary" --rollcheck "$project_root" "$song" >"$log" 2>&1
set -e
cat "$log" >&2

summary=$(sed -n 's/^PSG_VELOCITY_BENCH passed=\([0-9][0-9]*\) total=\([0-9][0-9]*\)$/\1 \2/p' "$log")
if [[ -z "$summary" || "$summary" == *$'\n'* ]]; then
  echo "autoresearch: expected one PSG_VELOCITY_BENCH summary" >&2
  exit 2
fi
read -r passed total <<<"$summary"
if [[ "$total" -ne 8 ]]; then
  echo "autoresearch: expected 8 velocity contracts, got $total" >&2
  exit 2
fi
if [[ "$passed" -ne "$total" ]]; then
  echo "autoresearch: $passed of $total velocity contracts passed" >&2
  exit 1
fi

echo "METRIC velocity_contracts_passed=$passed"
echo "METRIC velocity_contracts_total=$total"
