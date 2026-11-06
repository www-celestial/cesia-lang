# A file of std/ loads only as cesia.lock says: changed, added or without a lock, it stops at the use.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
mkdir -p "$top/std/csv" "$top/src" "$top/deps/someone/other/src/bad"
printf '[project]\nname = "p"\n' > "$top/cesia.toml"
cp ../../src/std/csv.ce "$top/std/csv/csv.ce"
printf 'use std/csv\nuse std/io\nio.Print(csv.Parse("as installed")[1][1])\n' > "$top/src/main.ce"
# cesia test leaves deps/ out, as std/: this example would fail.
printf '(** Bad. *)\nBad = 1   (** Bad.\n\n      Bad --> 2 *)\n' > "$top/deps/someone/other/src/bad/bad.ce"
cd "$top"
lock() { "$root/_build/default/src/bin/main.exe" run --allow read,write "$root/tests/packages/make-lock.ce"; }
lock
cesia run $no_spec src/main.ce
cesia test $no_spec .
printf '\n' >> std/csv/csv.ce
cesia run $no_spec src/main.ce
lock
printf '(** Added. *)\nAdded = 1\n' > std/csv/added.ce
cesia run $no_spec src/main.ce
rm std/csv/added.ce cesia.lock
cesia run $no_spec src/main.ce
