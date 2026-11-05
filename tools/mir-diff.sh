#!/usr/bin/env bash
# How our copy of MIR differs from the upstream commit in src/sys/mir/VERSION: the files we changed, then the diff.
# tools/mir-diff.sh [COMMIT] compares with another upstream commit instead, to see what an update would bring.
set -eu
cd "$(dirname "$0")/.."
base=$(grep -oE '[0-9a-f]{40}' src/sys/mir/VERSION | head -1)
commit=${1:-$base}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sSfL "https://github.com/vnmakarov/mir/archive/$commit.tar.gz" | tar -xz -C "$work"
upstream="$work/mir-$commit"
status=0
for f in src/sys/mir/*; do
  name=$(basename "$f")
  case "$name" in dune | VERSION | CHANGES.md) continue ;; esac
  if [ ! -f "$upstream/$name" ]; then
    echo "only ours: $name"
    status=1
  elif ! cmp -s "$f" "$upstream/$name"; then
    echo "changed: $name"
    diff -u "$upstream/$name" "$f" || true
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "src/sys/mir is upstream $commit, unchanged"
exit 0
