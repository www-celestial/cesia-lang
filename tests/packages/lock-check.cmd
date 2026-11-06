# A file of std/ loads only as cesia.lock says: changed, added or without a lock, it stops at the use.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
mkdir -p "$top/std/rope" "$top/src" "$top/deps/someone/other/src/bad"
printf '[project]\nname = "p"\n' > "$top/cesia.toml"
cp ../../src/std/rope.ce "$top/std/rope/rope.ce"
printf 'use std/rope\nPrint(rope.Text(rope.Of("as installed")))\n' > "$top/src/main.ce"
# cesia test leaves deps/ out, as std/: this example would fail.
printf '(** Bad. *)\nBad = 1   (** Bad.\n\n      Bad --> 2 *)\n' > "$top/deps/someone/other/src/bad/bad.ce"
cd "$top"
lock() { "$root/_build/default/src/bin/main.exe" run --allow read,write "$root/tests/packages/make-lock.ce"; }
lock
cesia run $no_spec src/main.ce
cesia test $no_spec .
printf '\n' >> std/rope/rope.ce
cesia run $no_spec src/main.ce
lock
printf '(** Added. *)\nAdded = 1\n' > std/rope/added.ce
cesia run $no_spec src/main.ce
rm std/rope/added.ce cesia.lock
cesia run $no_spec src/main.ce
