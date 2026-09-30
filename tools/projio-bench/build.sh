#!/bin/bash
# projio-bench build: compiles the REAL project-layer sources unmodified,
# layered exactly like production (BinaryParsing -> PorydawCore ->
# PorydawProject), plus the bench main. No CMake, no Qt, no native loader.
#
# Usage: build.sh [--source-root PATH]
#   BinaryParsing sources come from $BINARY_PARSING_SRC (default below);
#   point it at the exact FetchContent revision for revision fidelity
#   (see cmake/BinaryParsing.cmake for the pinned tag).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../.."
if [ "${1:-}" = "--source-root" ]; then SRC="${2:-$HERE/../..}"; fi
BP="${BINARY_PARSING_SRC:-$HOME/dev/swiftProjects/swift-binary-parsing/Sources/BinaryParsing}"
OUT="$HERE/.build"
mkdir -p "$OUT"

SWIFTC=(swiftc -swift-version 6 -O -g)
BP_SRCS=()
while IFS= read -r f; do BP_SRCS+=("$f"); done < <(find "$BP" -name "*.swift" -not -path "*/Macros/Macros.swift")
CORE_SRCS=("$SRC"/src/swift/core/*.swift)
PROJ_SRCS=(
  "$SRC/src/swift/project/ProjectIdentity.swift"
  "$SRC/src/swift/project/VoiceEdits.swift"
  "$SRC/src/swift/project/ProjectFileStore.swift"
  "$SRC/src/swift/project/AsmLine.swift"
  "$SRC/src/swift/project/SongModel.swift"
  "$SRC/src/swift/project/MidiCfg.swift"
  "$SRC/src/swift/project/SongsMk.swift"
  "$SRC/src/swift/project/SongCatalog.swift"
  "$SRC/src/swift/project/SongRegistration.swift"
  "$SRC/src/swift/project/SongRegistration+Debug.swift"
  "$SRC/src/swift/project/SynthCatalog.swift"
  "$SRC/src/swift/project/VoiceValues.swift"
  "$SRC/src/swift/project/VoicegroupSource.swift"
  "$HERE/NativeStub.swift"
)

# 0. Neutrality gate: measured stages must not reference the stubbed native
#    surface. VoiceValues.swift may only *store* BankHandle (LoadedBankView).
for f in "${PROJ_SRCS[@]}"; do
  case "$f" in
    *NativeStub.swift) continue ;;
    *VoiceValues.swift) continue ;;
  esac
  if grep -q "BankHandle\|LoadedBankView" "$f"; then
    echo "NEUTRALITY GATE FAILED: stubbed type referenced by $f"
    exit 1
  fi
done
echo "neutrality gate: clean"

# Empty module satisfying VoiceValues.swift's (unused) native import.
mkdir -p "$OUT/empty"
echo "// bench-only: satisfies an unused import" > "$OUT/empty/Empty.swift"

"${SWIFTC[@]}" -module-name BinaryParsing -emit-module \
  -emit-module-path "$OUT/BinaryParsing.swiftmodule" \
  -enable-experimental-feature Lifetimes -strict-memory-safety \
  "${BP_SRCS[@]}"

"${SWIFTC[@]}" -module-name PorydawProjectNative -emit-module \
  -emit-module-path "$OUT/PorydawProjectNative.swiftmodule" \
  "$OUT/empty/Empty.swift"

"${SWIFTC[@]}" -module-name PorydawCore -emit-module \
  -emit-module-path "$OUT/PorydawCore.swiftmodule" \
  -I "$OUT" "${CORE_SRCS[@]}"

"${SWIFTC[@]}" -module-name PorydawProject -emit-module \
  -emit-module-path "$OUT/PorydawProject.swiftmodule" \
  -I "$OUT" "${PROJ_SRCS[@]}"

# Batch-mode objects via an output file map (every input is primary): the
# same codegen shape production's batch mode produces.
mkdir -p "$OUT/objs"
make_map() {
  local map=$1 prefix=$2
  shift 2
  {
    echo "{"
    local i=0
    for s in "$@"; do
      i=$((i + 1))
      if [ "$i" -gt 1 ]; then printf ",\n"; fi
      printf '"%s": {"object": "%s/objs/%s-%d.o"}' "$s" "$OUT" "$prefix" "$i"
    done
    printf "\n}\n"
  } > "$map"
}
make_map "$OUT/bp-map.json" bp "${BP_SRCS[@]}"
make_map "$OUT/native-map.json" native "$OUT/empty/Empty.swift"
make_map "$OUT/core-map.json" core "${CORE_SRCS[@]}"
make_map "$OUT/proj-map.json" proj "${PROJ_SRCS[@]}"
"${SWIFTC[@]}" -c -parse-as-library -I "$OUT" \
  -enable-experimental-feature Lifetimes -strict-memory-safety \
  "${BP_SRCS[@]}" -output-file-map "$OUT/bp-map.json" -module-name BinaryParsing
"${SWIFTC[@]}" -c -parse-as-library -I "$OUT" "$OUT/empty/Empty.swift" \
  -output-file-map "$OUT/native-map.json" -module-name PorydawProjectNative
"${SWIFTC[@]}" -c -parse-as-library -I "$OUT" "${CORE_SRCS[@]}" \
  -output-file-map "$OUT/core-map.json" -module-name PorydawCore
"${SWIFTC[@]}" -c -parse-as-library -I "$OUT" "${PROJ_SRCS[@]}" \
  -output-file-map "$OUT/proj-map.json" -module-name PorydawProject

"${SWIFTC[@]}" -c -parse-as-library -I "$OUT" \
  "$HERE/BenchMain.swift" -o "$OUT/objs/bench-main.o"
"${SWIFTC[@]}" -I "$OUT" "$OUT"/objs/*.o -o "$OUT/projio-bench"
echo "built: $OUT/projio-bench"
if [ "$(uname -s)" = "Darwin" ]; then
  xcrun dsymutil "$OUT/projio-bench" -o "$OUT/projio-bench.dSYM"
  echo "debug symbols: $OUT/projio-bench.dSYM"
fi
