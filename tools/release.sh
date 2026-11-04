#!/usr/bin/env bash
# Prepares a release: tools/release.sh 0.3.0 sets the version in src/lib/version.ml, then shows the change and the notes the
# release will have. It commits nothing: commit "release: v0.3.0", tag v0.3.0 and push; the CI tests, builds and publishes.
# In 0.x, the middle number rises when a change can break a program, the last one for a fix.
set -eu
cd "$(dirname "$0")/.."
if [ $# -ne 1 ] || ! printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "usage: tools/release.sh X.Y.Z, as tools/release.sh 0.3.0" >&2
  exit 2
fi
file=src/lib/version.ml
grep -q '^let text = "cesia [^"]*+dev"$' "$file" || { echo "$file has no version line ending in +dev." >&2; exit 1; }
sed -e "s/^let text = \"cesia [^\"]*+dev\"$/let text = \"cesia $1+dev\"/" "$file" > "$file.new"
mv "$file.new" "$file"
git --no-pager diff -- "$file"
echo
echo "The notes of v$1:"
echo
tools/notes.sh
echo "Then: git commit -am \"release: v$1\" && git tag v$1 && git push && git push origin v$1"
