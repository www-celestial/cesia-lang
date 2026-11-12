# The cache of loaded packages, end to end. A run with the cache empty and runs with it filled give the same output and
# the same error; an entry damaged, cut, swapped with another, made a link or opened to others is not used, and is
# written again as it was; a changed file is read again; a folder that isn't the person's alone is neither read nor
# written; one that can't be written changes nothing; four runs at once agree.
top=$(mktemp -d)
trap 'chmod -R u+rwx "$top"; rm -rf "$top"' EXIT
export XDG_CACHE_HOME="$top/cache"
load="$top/cache/cesia/load"
app="$top/app"
mkdir -p "$app/src/shapes" "$app/src/units" "$top/good"
printf '[project]\nname = "app"\n' > "$app/cesia.toml"
fill=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do fill="$fill(** Filler $i. *)\nFill$i(x) = x + $i\n"; done
printf "(** Areas. *)\nuse src/units\nuse std/list\nuse std/text\n\n(** A rectangle. *)\nstruct Rect { W, H }\n\n(** The area. *)\nArea(r) = r.W * r.H\n\n(** Their areas, in a unit. *)\nAll(rs) = text.Str(list.Sum(list.Map(Area, rs)), units.Unit)\n$fill" > "$app/src/shapes/area.ce"
printf '(** What fails. *)\nuse std/bug\n\n(** A panic, two calls down. *)\nBroken(n) = deeper(n)\ndeeper(n) = if n > 0 bug.Panic("broken $n") else 0 end\n' > "$app/src/shapes/broken.ce"
units() { printf "(** Units. *)\n$1\n$fill" > "$app/src/units/units.ce"; }
units 'Unit = " m2"'
printf 'use src/shapes\nuse std/io\n\nio.Print(shapes.All([shapes.Rect(2, 3), shapes.Rect(4, 5)]))\nio.Print(shapes.Broken(1))\n' > "$app/main.ce"
# A run, then the end of the copy of it that writes its entries once it has ended.
run() {
  (cd "$app" && cesia run $no_spec "$app/main.ce" 2>&1; echo "exit $?") | sed "s|$top|TOP|g"
  for i in $(seq 1 500); do pgrep -f -- "$app/main.ce" > /dev/null || return 0; sleep 0.01; done
  echo "the entries were not written in 5 s"
}
# Each entry as it was when written, or not.
kept() { for f in "$top"/good/*; do cmp -s "$f" "$load/${f##*/}" || { echo "$1: an entry differs"; return; }; done; echo "$1: every entry as it was"; }
same() { [ "$(run)" = "$expected" ] && echo "$1: the same output and error" || echo "$1: another output"; }
expected=$(XDG_CACHE_HOME=/proc/none run)
echo "$expected"
same "cold"
echo "entries: $(ls "$load" | wc -l | tr -d ' ')"
cp "$load"/* "$top/good"
same "warm"
kept "warm"
size() { wc -c < "$1" | tr -d ' '; }
for f in "$load"/*; do printf '\377\001\377\001' | dd of="$f" bs=1 seek=$(($(size "$f") / 2)) conv=notrunc 2> /dev/null; done
same "damaged"
kept "damaged"
for f in "$load"/*; do head -c $(($(size "$f") / 2)) "$f" > "$top/cut"; cat "$top/cut" > "$f"; done
same "cut"
kept "cut"
set -- "$load"/*
cp "$1" "$top/swap"; cp "$2" "$1"; cp "$top/swap" "$2"
same "swapped"
kept "swapped"
mv "$1" "$top/real"; ln -s "$top/real" "$1"
same "a link"
[ -L "$1" ] && echo "a link: still there" || echo "a link: replaced by an entry"
cmp -s "$top/real" "$1" && echo "a link: what it pointed to untouched"
chmod 644 "$1"
same "open to others"
ls -l "$1" | cut -c1-10
kept "open to others"
units 'Unit = " square meters"'
chmod 755 "$load"
run | head -1
kept "a folder open to others"
chmod 700 "$load"
run | head -1
units 'Unit = " sq m"'
chmod 500 "$load"
run
chmod 700 "$load"
export XDG_CACHE_HOME="$top/race"
for i in 1 2 3 4; do run > "$top/out$i" & done
wait
expected=$(run)
for i in 1 2 3 4; do [ "$(cat "$top/out$i")" = "$expected" ] || echo "run $i at once: another output"; done
echo "four runs at once: $(ls "$top/race/cesia/load" | grep -c -v tmp) entries"
same "after them"
# The copy that writes the entries holds none of the program's descriptors once the program has ended: the port it
# listened on is free, a lock it held is free, a pipe it wrote to ends, and a file it wrote gets nothing more. Each run
# starts with an empty cache, so that a copy writes.
wait_copies() { for i in $(seq 1 500); do pgrep -f -- "$app/" > /dev/null || return 0; sleep 0.01; done; }
printf 'use src/shapes\nuse std/io\nuse std/net\n\nlistener = net.Listen(0).Value\nio.Print(net.Port(listener))\n' > "$app/listen.ce"
port=$(cd "$app" && XDG_CACHE_HOME="$top/port" cesia run $no_spec --allow net "$app/listen.ce")
printf 'use std/io\nuse std/net\nuse std/result\n\nio.Print(result.IsOk(net.Listen(%s)))\n' "$port" > "$top/again.ce"
[ "$(XDG_CACHE_HOME=/proc/none cesia run --allow net "$top/again.ce")" = true ] || echo "the port stays bound after the end"
if command -v flock > /dev/null; then
  (cd "$app" && XDG_CACHE_HOME="$top/lock" flock "$top/lock-file" "$root/_build/default/src/bin/main.exe" run $no_spec "$app/main.ce" > /dev/null 2>&1)
  flock -n "$top/lock-file" true || echo "the lock stays held after the end"
fi
(cd "$app" && XDG_CACHE_HOME="$top/pipe" cesia run $no_spec "$app/main.ce" 3>&1 2>&1 | cat | head -1)
(cd "$app" && XDG_CACHE_HOME="$top/file" cesia run $no_spec "$app/main.ce" > "$top/written" 2>&1)
size=$(wc -c < "$top/written")
wait_copies
[ "$(wc -c < "$top/written")" = "$size" ] || echo "the copy wrote to the program's output"
