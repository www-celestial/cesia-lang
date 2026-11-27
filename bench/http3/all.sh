#!/usr/bin/env bash
# all.sh: every measure of bench/http3, one after the other, each in its own short session of the heavy lock
# (HEAVY_LOCK names the lock file; each session stays under 25 minutes, so the long ones are cut in rounds), then the
# tables (summary.py). Results in $HOME/.cache/quic/bench/results, logs in $HOME/.cache/quic/bench/logs.
set -uo pipefail
cd "$(dirname "$0")"
step() { echo "$(date +%H:%M:%S) start: $*"; "$@" || echo "$(date +%H:%M:%S) FAILED ($?): $*"; }
step ./rps.sh clean 7
step ./ab.sh 21
step ./h3off.sh 7
step ./memory.sh 5 200
step ./download.sh clean 5
step ./migrate.sh clean 5
step ./rps.sh d25l1 3
step ./download.sh d25l1 3
step ./migrate.sh d25l1 3
step ./rps.sh d50l3 3
step ./download.sh d50l3 3
step ./rps.sh d100l5 3
step ./download.sh d100l5 3
python3 summary.py
