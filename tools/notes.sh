#!/usr/bin/env bash
# The notes of a release, from the messages of the commits since the tag before: tools/notes.sh [FROM [TO]]. feat: goes under
# New, fix: under Fixes, and a ! (feat!: or fix!:) under Breaking, where the message says what to change. The rest is left out.
set -eu
cd "$(dirname "$0")/.."
to=${2:-HEAD}
from=${1:-$(git describe --tags --abbrev=0 --exclude nightly "$to^" 2> /dev/null || true)}
# A release whose version has a section of its own in CHANGELOG.md takes that text, written by hand; a nightly, the commits.
tag=$(git describe --tags --exact-match --exclude nightly "$to" 2> /dev/null || true)
if [ -n "$tag" ] && grep -qx "## ${tag#v}" CHANGELOG.md 2> /dev/null; then
  awk -v h="## ${tag#v}" '$0 == h { on = 1; next } on && /^## / { exit } on' CHANGELOG.md
  exit 0
fi
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
