#!/usr/bin/env bash
# The notes of a release, from the messages of the commits since the tag before: tools/notes.sh [FROM [TO]]. feat: goes under
# New, fix: under Fixes, and a ! (feat!: or fix!:) under Breaking, where the message says what to change. The rest is left out.
set -eu
cd "$(dirname "$0")/.."
to=${2:-HEAD}
from=${1:-$(git describe --tags --abbrev=0 --exclude nightly "$to^" 2> /dev/null || true)}
subjects=$(git log --format=%s "${from:+$from..}$to")
section() { # title, pattern
  lines=$(printf '%s\n' "$subjects" | grep -E "$2" | sed -E 's/^[a-z]+(\([^)]*\))?!?: //' || true)
  if [ -n "$lines" ]; then
    printf '## %s\n\n' "$1"
    printf '%s\n' "$lines" | sed 's/^/- /'
    echo
  fi
}
section Breaking '^[a-z]+(\([^)]*\))?!: '
section New '^feat(\([^)]*\))?: '
section Fixes '^fix(\([^)]*\))?: '
