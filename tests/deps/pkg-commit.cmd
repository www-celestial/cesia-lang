# cesia pkg at the hash of a commit, for a project that has no tag yet: add, install from the cache, and a hash that no
# commit has, which leaves deps/ as it was.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
export XDG_CACHE_HOME="$top/cache" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 LC_ALL=C
g() { git -C "$1" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "${@:2}"; }
clean() { sed -e "s|$top|TOP|g" -E -e 's/[0-9a-f]{12,64}/HASH/g'; }
units="$top/repos/bob/units"
mkdir -p "$units/src/meters" && git init -q "$units"
printf '[project]\nname = "units"\n' > "$units/cesia.toml"
printf '(** Meters. *)\nName = "meters, first commit"\n' > "$units/src/meters/meters.ce"
g "$units" add -A; g "$units" commit -q -m one
first=$(g "$units" rev-parse HEAD)
printf '(** Meters. *)\nName = "meters, second commit"\n' > "$units/src/meters/meters.ce"
g "$units" commit -q -am two
mkdir -p "$top/proj/src" && cd "$top/proj"
printf '[project]\nname = "proj"\n' > cesia.toml
printf 'use deps/bob/units/src/meters\nuse std/io\nio.Print(meters.Name)\n' > src/main.ce
echo "== add at the first commit, which no tag names"
cesia pkg add "file://$units@$first" | clean
tail -3 cesia.toml | clean
cesia run $no_spec src/main.ce
echo "== install from the cache"
rm -rf deps
cesia pkg install | clean
cesia run $no_spec src/main.ce
echo "== a hash that no commit has"
# git's own reason comes last, in words that vary from one run to the next: the line stops before it.
cesia pkg update units --to 0123456789abcdef0123456789abcdef01234567 2>&1 | clean | sed -E 's/(at HASH): .*/\1: .../'
cesia run $no_spec src/main.ce
