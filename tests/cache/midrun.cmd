# The entry of std/plot changed under a run that read its head, before the run draws with it: unlinked, replaced by
# another file, or changed in place in every record, also with the JIT on every function and under a memory limit. The
# run draws the same graph as without a cache: a file unlinked or replaced stays, for the run that mapped it, as it was;
# a record changed is found when it is read, and its function taken from the source that the load read. The next run
# draws the same, and the entry is as it was.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
export XDG_CACHE_HOME="$top/cache"
load="$top/cache/cesia/load"
printf 'use std/plot\nuse std/io\nuse std/sys\n\nio.Print("loaded")\n_ = sys.ReadInput(1)\nio.Print(plot.Svg(plot.Of([plot.Line([1, 2, 3], [2, 4, 1])], title = "first")))\n' > "$top/draw.ce"
# A run, then the end of the copy of it that writes its entries once it has ended.
draw() {
  cesia run $no_spec "$@" "$top/draw.ce" 2>&1; echo "exit $?"
  for i in $(seq 1 500); do pgrep -f -- "$top/draw.ce" > /dev/null || return 0; sleep 0.01; done
  echo "the entries were not written in 5 s"
}
entries() { for f in "$load"/*; do [ "${f##*/}" = total ] || printf '%s\n' "$f"; done; }
expected=$(XDG_CACHE_HOME=/proc/none draw < /dev/null | cksum)
draw < /dev/null > /dev/null
mkdir "$top/good"
cp $(entries) "$top/good"
echo "entries: $(entries | wc -l | tr -d ' ')"
# Every byte of the tail of an entry changed in place, the same file: its head's length is in its bytes 16 to 24.
records() {
  local head=$((24 + $(od -An -td8 -j16 -N8 "$1" | tr -d ' '))) size
  size=$(wc -c < "$1" | tr -d ' ')
  { head -c "$head" "$1"; head -c $((size - head)) /dev/zero; } > "$top/changed"
  cat "$top/changed" > "$1"
}
unlinked() { rm "$1"; }
# The entries as they are against the good ones: a run that took a function from its source wrote its entry again.
state() {
  local kept=0 changed=0 gone=0
  for f in "$top"/good/*; do
    if [ ! -e "$load/${f##*/}" ]; then gone=$((gone + 1)); elif cmp -s "$f" "$load/${f##*/}"; then kept=$((kept + 1)); else changed=$((changed + 1)); fi
  done
  echo "$kept as they were, $changed changed, $gone gone"
}
replaced() { printf 'another file' > "$top/other"; mv "$top/other" "$1"; }
# A run that waits once it has loaded, then the change to each entry, then the rest of the run: with the JIT as $1 says
# (CESIA_JIT; empty, as it is by default), and the flags after the change.
under() {
  local jit="$1" how="$2" name="$2${1:+ with the JIT $1}${3:+ $3 $4}"
  shift 2
  rm -f "$top/fifo" "$top/out"
  mkfifo "$top/fifo"
  CESIA_JIT="$jit" draw "$@" < "$top/fifo" > "$top/out" &
  exec 9> "$top/fifo"
  for i in $(seq 1 500); do [ -s "$top/out" ] && break; sleep 0.01; done
  for f in $(entries); do "$how" "$f"; done
  echo x >&9
  exec 9>&-
  wait
  [ "$(cksum < "$top/out")" = "$expected" ] && echo "$name: the same graph" || { echo "$name: another output"; cat "$top/out"; }
  # With the JIT, a run whose native code is made on another core writes no entry when it ends.
  [ -n "$jit" ] || echo "$name: the entries after it: $(state)"
  [ "$(draw < /dev/null | cksum)" = "$expected" ] && echo "$name: the next run, the same graph" || echo "$name: the next run, another output"
  for f in "$top"/good/*; do cmp -s "$f" "$load/${f##*/}" || { echo "$name: an entry differs"; return; }; done
  echo "$name: every entry as it was"
}
under "" unlinked
under "" replaced
under "" records
under always records
under "" records --limit memory=2M
