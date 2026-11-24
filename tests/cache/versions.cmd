# Two versions of Cesia used in turn, as an old binary kept beside a new one: each keeps its own entries, whose names
# hold its build, and neither writes over the other's, so each run after the first of each is warm. The other version
# is this binary with another build in it.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
export XDG_CACHE_HOME="$top/cache"
load="$top/cache/cesia/load"
this="$root/_build/default/src/bin/main.exe"
id=$(sed -n 's/^let id = "\(.*\)"$/\1/p' "$root/_build/default/src/bin/build.ml")
LC_ALL=C sed "s/$id/$(printf '%s' "$id" | tr '0-9a-f' 'f0-9a-e')/" "$this" > "$top/other"
chmod +x "$top/other"
cmp -s "$this" "$top/other" && echo "the other version is the same binary"
printf 'use std/plot\nuse std/io\n\nio.Print(plot.Svg(plot.Of([plot.Line([1, 2, 3], [2, 4, 1])])))\n' > "$top/graph.ce"
# A run of one version, then the end of the copy of it that writes its entries once it has ended.
graph() {
  "$1" run $no_spec "$top/graph.ce" 2>&1 | cksum
  for i in $(seq 1 500); do pgrep -f -- "$top/graph.ce" > /dev/null || return 0; sleep 0.01; done
  echo "the entries were not written in 5 s"
}
# Each entry with its inode: an entry written again is a new file.
files() { for f in "$load"/*; do [ "${f##*/}" = total ] || ls -i "$f"; done; }
first=$(graph "$this")
[ "$(graph "$top/other")" = "$first" ] && echo "two versions: the same graph"
echo "two versions: $(files | wc -l | tr -d ' ') entries"
before=$(files)
for i in 1 2 3 4 5; do
  [ "$(graph "$this")" = "$first" ] && [ "$(graph "$top/other")" = "$first" ] || echo "run $i in turn: another graph"
done
[ "$(files)" = "$before" ] && echo "ten runs in turn: every entry kept, none written again" || echo "ten runs in turn: entries written again"
