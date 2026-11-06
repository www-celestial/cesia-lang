#!/usr/bin/env bash
# Benchmarks: best of 3, one process at a time. A wrong output fails the script. The programs of bench/real, named
# real/NAME, measure the JIT on what a program does, with no reference: `tools/bench.sh real/particles real/csv real/json`.
set -u
cd "$(dirname "$0")/.."
no_spec=""
if [ "${1:-}" = "--no-spec" ]; then no_spec="--no-spec"; shift; fi
dune build --profile release 2>&1 | head -20
tests=${*:-fib mandel structs matmul dyn}
refs=${REFS:-python lua}
cesia=_build/default/src/bin/main.exe
runs=${RUNS:-3}
status=0

expected() {
  case "$1" in
    fib) echo 9227465 ;;
    mandel) echo 13428156 ;;
    structs) echo 1634100.475000 ;;
    matmul) echo 1119343.750000 ;;
    dyn) echo 11.000000 ;;
    real/particles) echo 807945.334142 ;;
    real/csv) echo "200000 {south: 3999990001.5, east: 3999879999.25, west: 3999920001.0, center: 4000109996.25, north: 4000100002.5}" ;;
    real/json) printf '2500025000.0\n4116680\n' ;;
  esac
}

same() {  # expected value, output
  case "$2" in *$'\n'* | *" "*) [ "$2" = "$1" ]; return ;; esac
  case "$1" in
    *.*) [ "$(LC_ALL=C printf '%.6f' "$2" 2>/dev/null)" = "$1" ] ;;
    *) [ "$2" = "$1" ] ;;
  esac
}

measure() {
  local test="$1" name="$2"; shift 2
  local best="" out="" s e ms i
  for ((i = 0; i < runs; i++)); do
    s=$(date +%s%N)
    out=$("$@" 2>&1)
    e=$(date +%s%N)
    ms=$(((e - s) / 1000000))
    if [ -z "$best" ] || [ "$ms" -lt "$best" ]; then best=$ms; fi
  done
  local mark=ok
  if ! same "$(expected "$test")" "$out"; then mark="WRONG: $out"; status=1; fi
  printf '%-8s %-8s %7d ms  %s\n' "$test" "$name" "$best" "$mark"
}

for t in $tests; do
  measure "$t" cesia "$cesia" run $no_spec "bench/$t.ce"
  for r in $refs; do
    [ "${t#real/}" = "$t" ] || continue
    case "$r" in
      python) measure "$t" python python3 "bench/$t.py" ;;
      lua) measure "$t" lua lua "bench/$t.lua" ;;
      luajit) measure "$t" luajit luajit "bench/$t.lua" ;;
      node) measure "$t" node node "bench/$t.js" ;;
    esac
  done
done
exit $status
