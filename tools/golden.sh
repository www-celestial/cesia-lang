#!/usr/bin/env bash
# Golden tests: for each name.kp with name.expected, runs kepler from the test's folder
# and compares stdout then stderr (2>&1), followed by an "exit N" line.
# Optional files: name.flags, name.args, name.stdin, name.cmd (full command, replaces "kepler run").
set -u
cd "$(dirname "$0")/.."
root=$PWD
kepler="$root/_build/default/bin/main.exe"
no_spec=""
if [ "${1:-}" = "--no-spec" ]; then no_spec="--no-spec"; shift; fi

failed=0
total=0
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

run_one() {
  local dir="$1" name="$2"
  local flags="" args="" input=/dev/null
  [ -f "$dir/$name.flags" ] && flags=$(cat "$dir/$name.flags")
  [ -f "$dir/$name.args" ] && args=$(cat "$dir/$name.args")
  [ -f "$dir/$name.stdin" ] && input="$dir/$name.stdin"
  local abs_input; abs_input=$(realpath "$input")
  (
    cd "$dir" || exit 99
    kepler() { "$root/_build/default/bin/main.exe" "$@"; }
    if [ -f "$name.cmd" ]; then
      # shellcheck disable=SC1090
      source "./$name.cmd" < "$abs_input"
    else
      # shellcheck disable=SC2086
      "$kepler" run $no_spec $flags "$name.kp" $args < "$abs_input"
    fi
    echo "exit $?"
  ) > "$tmp" 2>&1
  total=$((total + 1))
  if ! diff -u "$dir/$name.expected" "$tmp" > "$tmp.diff"; then
    echo "golden: FAILED $dir/$name"
    cat "$tmp.diff"
    failed=$((failed + 1))
  fi
  rm -f "$tmp.diff"
}

for dir in "$@"; do
  dir=${dir%/}
  [ -d "$dir" ] || continue
  for expected in "$dir"/*.expected; do
    [ -f "$expected" ] || continue
    name=$(basename "$expected" .expected)
    run_one "$dir" "$name"
  done
done

echo "golden: $((total - failed))/$total ${no_spec}"
[ "$failed" -eq 0 ]
