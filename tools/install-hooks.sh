#!/bin/sh

repo_root=$(git rev-parse --show-toplevel) || {
    echo "install-hooks: not inside a Git repository" >&2
    exit 1
}

git -C "$repo_root" config --local core.hooksPath .githooks
printf '%s\n' "Configured this checkout to use .githooks."
