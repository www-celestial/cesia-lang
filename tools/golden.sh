#!/usr/bin/env bash
# Golden tests: for each name.ce with name.expected, runs cesia from the test's folder
# and compares stdout then stderr (2>&1), followed by an "exit N" line.
# Optional files: name.flags, name.args, name.stdin, name.cmd (full command, replaces "cesia run").
#   tools/golden.sh [--no-spec | --both] [--quick | --slow] FOLDER...
# --no-spec runs the other path of the engine. --both runs each test on both, one after the other in the same job, so that
# a test's ports never meet, but in a folder with a .one-path file, which says why, and for a .cmd that doesn't pass
# $no_spec on. A name.slow file marks a test slow by nature (a compiler, git, every core): --quick leaves those out, for the
# change loop, and --slow runs only them.
# The tests run side by side, the slowest of the last run first, so that none starts last and keeps the others waiting.
# GOLDEN_TRACE=1 names each test as it starts: a test that hangs would otherwise leave no trace.
set -u
cd "$(dirname "$0")/.."
root=$PWD
cesia="$root/_build/default/src/bin/main.exe"
paths="spec"
pick="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --no-spec) paths="no-spec" ;;
    --both) paths="both" ;;
    --quick) pick="quick" ;;
    --slow) pick="slow" ;;
    *) break ;;
  esac
  shift
done

times="$root/_build/golden-times"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The time in milliseconds into $ms, from bash itself when it can tell it, without a process.
clock() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    local t=${EPOCHREALTIME/[.,]/}
    ms=$((t / 1000))
  else
    ms=$(($(date +%s) * 1000))
  fi
}

# One run of a test on one path: its output in $out, and $out.failed when it differs from the expected one. A test of a
# .ce runs in this job's shell, a .cmd in a shell of its own, since it may change the shell.
run_path() {
  local dir="$1" name="$2" out="$3" no_spec="$4"
  local flags="" args="" input=/dev/null got="" want=""
  [ -f "$dir/$name.flags" ] && read -r flags < "$dir/$name.flags"
  [ -f "$dir/$name.args" ] && read -r args < "$dir/$name.args"
  [ -f "$dir/$name.stdin" ] && input="$root/$dir/$name.stdin"
  if [ -f "$dir/$name.cmd" ]; then
    (
      cd "$dir" || exit 99
      cesia() { "$root/_build/default/src/bin/main.exe" "$@"; }
      # shellcheck disable=SC1090
      source "./$name.cmd" < "$input"
      echo "exit $?"
    ) > "$out" 2>&1
  else
    cd "$root/$dir" || return
    # shellcheck disable=SC2086
    "$cesia" run $no_spec $flags "$name.ce" $args < "$input" > "$out" 2>&1
    echo "exit $?" >> "$out"
    cd "$root" || return
  fi
  # Read whole by bash: no process for a test that passes, and diff for one that doesn't.
  IFS= read -r -d '' got < "$out" || true
  IFS= read -r -d '' want < "$dir/$name.expected" || true
  if [ "$got" != "$want" ]; then
    diff -u "$dir/$name.expected" "$out" > "$out.diff"
    echo "$dir/$name $no_spec" > "$out.failed"
  fi
}

# Does this test run differently on the other path? A .cmd does only when it passes $no_spec on to cesia.
second() {
  local body=""
  [ -f "$1.cmd" ] || return 0
  IFS= read -r -d '' body < "$1.cmd" || true
  [[ $body == *no_spec* ]]
}

run_one() {
  local dir="$1" name="$2" out="$3" start ms
  clock
  start=$ms
  case "$paths" in
    spec) run_path "$dir" "$name" "$out.a" "" ;;
    no-spec) run_path "$dir" "$name" "$out.b" "--no-spec" ;;
    both)
      run_path "$dir" "$name" "$out.a" ""
      if [ ! -f "$dir/.one-path" ] && second "$dir/$name"; then run_path "$dir" "$name" "$out.b" "--no-spec"; fi
      ;;
  esac
  clock
  echo "$((ms - start)) $dir/$name" > "$out.time"
}

# Every test to run, the slowest of the last run first.
for dir in "$@"; do
  dir=${dir%/}
  [ -d "$dir" ] || continue
  for expected in "$dir"/*.expected; do
    [ -f "$expected" ] || continue
    name=${expected##*/}
    name=${name%.expected}
    slow=no
    [ -f "$dir/$name.slow" ] && slow=yes
    if [ "$pick" = quick ] && [ "$slow" = yes ]; then continue; fi
    if [ "$pick" = slow ] && [ "$slow" = no ]; then continue; fi
    echo "$dir $name"
  done
done > "$tmp/names"
# shellcheck disable=SC2016
awk 'FILENAME == ARGV[1] { ms[$2] = $1; next } { print (($1 "/" $2) in ms ? ms[$1 "/" $2] : 0), $1, $2 }' \
  <(cat "$times" 2> /dev/null) "$tmp/names" | sort -rn > "$tmp/list"

# Many tests wait, on the network or on a clock: a half more jobs than cores fills those gaps. GOLDEN_JOBS sets the number.
max_jobs=${GOLDEN_JOBS:-$(($(getconf _NPROCESSORS_ONLN) * 3 / 2))}
running=0
total=0
while read -r _ dir name; do
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
done < "$tmp/list"
wait

failed=0
runs=0
spec_runs=0
no_spec_runs=0
for ((i = 1; i <= total; i++)); do
  for part in a b; do
    [ -f "$tmp/$i.$part" ] || continue
    runs=$((runs + 1))
    if [ "$part" = a ]; then spec_runs=$((spec_runs + 1)); else no_spec_runs=$((no_spec_runs + 1)); fi
    if [ -f "$tmp/$i.$part.failed" ]; then
      echo "golden: FAILED $(cat "$tmp/$i.$part.failed")"
      cat "$tmp/$i.$part.diff"
      failed=$((failed + 1))
    fi
  done
done
# The times of this run, and those of the tests it didn't run.
if [ -d "$root/_build" ] && [ "$total" -gt 0 ]; then
  cat "$tmp"/*.time > "$tmp/new-times"
  awk 'FILENAME == ARGV[1] { seen[$2] = 1; print; next } !($2 in seen)' "$tmp/new-times" <(cat "$times" 2> /dev/null) > "$tmp/all-times"
  cp "$tmp/all-times" "$times"
fi

case "$paths" in
  spec) echo "golden: $((runs - failed))/$runs" ;;
  no-spec) echo "golden: $((runs - failed))/$runs --no-spec" ;;
  both) echo "golden: $((runs - failed))/$runs ($spec_runs, and $no_spec_runs --no-spec)" ;;
esac
[ "$failed" -eq 0 ]
