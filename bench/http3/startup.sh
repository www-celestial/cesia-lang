#!/usr/bin/env bash
# startup.sh [ROUNDS]: what HTTP/3 adds to the start of a program: `cesia run` of a file that loads std/http3 and calls
# quic.Open() (OpenSSL's QUIC before, ngtcp2 now: its library opened, its functions bound, its callbacks made), against
# the same file that only loads std/http, each run a new process, ROUNDS rounds (21) alternated; CESIA and
# CESIA_OPENSSL are the two binaries. JSON lines in $RES/startup.jsonl: {binary, file, ms}.
set -euo pipefail
. "$(dirname "$0")/env.sh"
in_ns clean "startup" "$0" "$@"
rounds=${1:-21}
out=$RES/startup.jsonl
dir=$RUN/startup
mkdir -p "$dir"
printf 'use std/http\nuse std/result\n' >"$dir/plain.ce"
printf 'use std/http\nuse std/http3\nuse std/quic\nuse std/result\nq = quic.Open()\nresult.IsOk(q) or panic("no QUIC")\n' >"$dir/quic.ce"
sed -i 's/or panic("no QUIC")//' "$dir/quic.ce"
for ((r = 1; r <= rounds; r++)); do
  for bin in "$CESIA" "$CESIA_OPENSSL"; do
    for f in plain quic; do
      t0=$(date +%s%N)
      taskset -c "$SERVER_CPUS" "$bin" run --allow ffi=ssl,ffi=crypto "$dir/$f.ce" >/dev/null 2>&1
      t1=$(date +%s%N)
      printf '{"binary":"%s","file":"%s","round":%d,"ms":%s}\n' "$(basename "$bin")" "$f" "$r" \
        "$(awk "BEGIN{print ($t1-$t0)/1e6}")" >>"$out"
    done
  done
done
echo "$(date +%H:%M:%S) startup $rounds rounds done" >&2
