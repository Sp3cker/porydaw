#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export QT_QPA_PLATFORM=offscreen
export QT_LOGGING_RULES="qt.qpa.*=false"

repositoryRoot="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
buildDirectory="${PORYDAW_AUTORESEARCH_BUILD_DIR:-"$repositoryRoot/build-autoresearch"}"
cmake -S "$repositoryRoot" -B "$buildDirectory" -DCMAKE_BUILD_TYPE=Release >&2
cmake --build "$buildDirectory" --target porydaw --parallel 8 >&2

applicationBinary="$buildDirectory/porydaw"
if [[ -x "$buildDirectory/porydaw.app/Contents/MacOS/porydaw" ]]; then
    applicationBinary="$buildDirectory/porydaw.app/Contents/MacOS/porydaw"
fi

"$applicationBinary" --shortcutcheck
