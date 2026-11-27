#!/usr/bin/env bash
# ns.sh PROFILE COMMAND [ARG...]: runs COMMAND in a new user and network namespace (unshare -rn), so that the servers
# and the load generator it starts share one loopback, with netem's PROFILE on it (clean d25l1 d50l3 d100l5).
# The loopback gets an MTU of 1500 and no TCP segmentation offload (gso_max_segs 1), so that netem's delay and loss
# fall on packets the size of the Internet's, for TCP as for QUIC.
set -euo pipefail
. "$(dirname "$0")/env.sh"
args=$(netem_args "$1")
export OUTER_UID=$(id -u) OUTER_GID=$(id -g) BENCH_PROFILE=$1
shift
exec unshare -rn bash -c '
set -euo pipefail
ip link set dev lo mtu 1500 gso_max_size 1500 gso_max_segs 1 up
if [ -n "$1" ]; then tc qdisc add dev lo root netem $1 limit 100000; fi
shift
export BENCH_NS=1
exec "$@"' ns "$args" "$@"
