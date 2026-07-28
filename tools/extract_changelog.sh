#!/bin/sh
# Print one version's section of CHANGELOG.md (used by the release workflow
# as the GitHub release body). Fails if the version has no entry, so a tag
# pushed without a changelog update fails loudly in CI.
#
# Usage: tools/extract_changelog.sh <version> [changelog-path]
set -eu

version="$1"
changelog="${2:-CHANGELOG.md}"

awk -v ver="$version" '
    /^## \[/ {
        in_section = ($0 ~ ("^## \\[" ver "\\]"))
        if (in_section) { found = 1 }
        next
    }
    # The link-reference footer is not part of any section.
    /^\[[^]]+\]: / { next }
    in_section { print }
    END { exit !found }
' "$changelog"
