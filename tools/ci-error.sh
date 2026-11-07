#!/usr/bin/env bash
# After a failed step of the CI: the failures of each output file, then its end, as error annotations, which the page of
# the run shows and which anyone can read through the API of a public repository, unlike the logs. An annotation keeps
# 4096 bytes: each part stays under it.
#   tools/ci-error.sh FILE...   files that don't exist are skipped.
set -u
annotate() {  # title, text
  # An annotation is one line: %, CR and LF are escaped as the runner reads them.
  local body
  body=$(printf '%s\n' "$2" | sed -e 's/%/%25/g' -e 's/\r/%0D/g' | awk 'BEGIN { ORS = "%0A" } { print }')
  echo "::error title=$1::$body"
}
for file in "$@"; do
  [ -s "$file" ] || continue
  # Without the names of tools/golden.sh's GOLDEN_TRACE: those of tests/errors/ would fill the annotation.
  failures=$(grep -E 'FAILED|[1-9][0-9]* failed|rror|^[-+][^-+]' "$file" | grep -v '^golden: tests/' | head -c 3000)
  [ -n "$failures" ] && annotate "$file: failures" "$failures"
  annotate "$file: end" "$(tail -c 3000 "$file")"
done
