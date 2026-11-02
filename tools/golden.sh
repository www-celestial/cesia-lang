#!/usr/bin/env bash
# Golden tests: for each name.kp with name.expected, runs kepler from the test's folder
# and compares stdout then stderr (2>&1), followed by an "exit N" line.
# Optional files: name.flags, name.args, name.stdin, name.cmd (full command, replaces "kepler run").
# GOLDEN_TRACE=1 names each test as it starts: a test that hangs would otherwise leave no trace.
set -u
cd "$(dirname "$0")/.."
root=$PWD
kepler="$root/_build/default/bin/main.exe"
no_spec=""
if [ "${1:-}" = "--no-spec" ]; then no_spec="--no-spec"; shift; fi

failed=0
total=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Golden tests are small and independent: their ports and folders differ, so they run side by side.
max_jobs=$(getconf _NPROCESSORS_ONLN)
running=0

run_one() {
  local dir="$1" name="$2" out="$3"
  local flags="" args="" input=/dev/null
  [ -f "$dir/$name.flags" ] && flags=$(cat "$dir/$name.flags")
  [ -f "$dir/$name.args" ] && args=$(cat "$dir/$name.args")
  [ -f "$dir/$name.stdin" ] && input=$(realpath "$dir/$name.stdin")
  (
    cd "$dir" || exit 99
    kepler() { "$root/_build/default/bin/main.exe" "$@"; }
    if [ -f "$name.cmd" ]; then
      # shellcheck disable=SC1090
      source "./$name.cmd" < "$input"
    else
      # shellcheck disable=SC2086
      "$kepler" run $no_spec $flags "$name.kp" $args < "$input"
    fi
    echo "exit $?"
  ) > "$out" 2>&1
  diff -u "$dir/$name.expected" "$out" > "$out.diff" || echo "$dir/$name" > "$out.failed"
}

for dir in "$@"; do
  dir=${dir%/}
  [ -d "$dir" ] || continue
  for expected in "$dir"/*.expected; do
    [ -f "$expected" ] || continue
    name=${expected##*/}
    name=${name%.expected}
    total=$((total + 1))
    [ -z "${GOLDEN_TRACE:-}" ] || echo "golden: $dir/$name"
    run_one "$dir" "$name" "$tmp/$total" &
    running=$((running + 1))
    if [ "$running" -ge "$max_jobs" ]; then
      # macOS has bash 3.2, which has no wait -n: there, the tests go by batches.
      if wait -n 2> /dev/null; then
        running=$((running - 1))
      else
        wait
        running=0
      fi
    fi
  done
done
wait

for ((i = 1; i <= total; i++)); do
  if [ -f "$tmp/$i.failed" ]; then
    echo "golden: FAILED $(cat "$tmp/$i.failed")"
    cat "$tmp/$i.diff"
    failed=$((failed + 1))
  fi
done

echo "golden: $((total - failed))/$total ${no_spec}"
[ "$failed" -eq 0 ]
