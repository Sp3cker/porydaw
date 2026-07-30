#!/usr/bin/env bash
# Format porydaw's own sources (src/ and tools/) with the repo .clang-format,
# or verify they are already formatted. external/ is third-party and is
# never touched; generated tables opt out with clang-format off/on guards.
#
# usage: tools/format.sh          reformat files in place
#        tools/format.sh --check  exit non-zero if any file needs formatting
#
# Formatting output differs across clang-format major versions; CI pins
# major version 22 (pip install 'clang-format==22.*'), so run the same
# major locally before relying on --check. Override the binary with
# CLANG_FORMAT=/path/to/clang-format.
set -u

cd "$(dirname "$0")/.." || exit 1

CLANG_FORMAT="${CLANG_FORMAT:-clang-format}"
command -v "$CLANG_FORMAT" >/dev/null 2>&1 || {
    echo "format.sh: $CLANG_FORMAT not found (pip install 'clang-format==22.*')" >&2
    exit 2
}

major=$("$CLANG_FORMAT" --version | grep -oE '[0-9]+' | head -1)
[ "$major" = 22 ] || \
    echo "format.sh: warning: clang-format major version $major, CI pins 22 — results may differ" >&2

mode=format
[ "${1:-}" = "--check" ] && mode=check

# git ls-files keeps the list to tracked sources (build dirs, scratch
# files, and external/ never appear in it).
files=$(git ls-files 'src/*.cpp' 'src/*.h' 'tools/*.cpp' 'tools/*.h')
[ -n "$files" ] || { echo "format.sh: no sources found" >&2; exit 2; }

if [ "$mode" = check ]; then
    # shellcheck disable=SC2086
    "$CLANG_FORMAT" --dry-run --Werror $files || {
        echo "format.sh: formatting differences found — run tools/format.sh" >&2
        exit 1
    }
    echo "format.sh: all $(echo "$files" | wc -l) files formatted"
else
    # shellcheck disable=SC2086
    "$CLANG_FORMAT" -i $files
    echo "format.sh: formatted $(echo "$files" | wc -l) files"
fi
