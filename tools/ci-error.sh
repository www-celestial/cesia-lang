#!/usr/bin/env bash
# After a failed step of the CI: the end of each output file, as an error annotation, which the page of the run shows
# and which anyone can read through the API of a public repository, unlike the logs.
#   tools/ci-error.sh FILE...   files that don't exist are skipped.
set -u
for file in "$@"; do
  [ -s "$file" ] || continue
  # An annotation is one line: %, CR and LF are escaped as the runner reads them.
  body=$(tail -n 150 "$file" | sed -e 's/%/%25/g' -e 's/\r/%0D/g' | awk 'BEGIN { ORS = "%0A" } { print }')
  echo "::error title=$file::$body"
done
