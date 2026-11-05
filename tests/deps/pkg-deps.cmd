# cesia pkg with git repositories in a temporary folder: add, the following of uses, flat versions, install from the cache,
# a moved tag, update, move, and what fails without touching deps/ or cesia.lock.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
export XDG_CACHE_HOME="$top/cache" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 LC_ALL=C
g() { git -C "$1" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c tag.gpgsign=false "${@:2}"; }
file() { mkdir -p "$(dirname "$top/repos/$1")"; printf "$2" > "$top/repos/$1"; }
publish() { g "$top/repos/$1" add -A; g "$top/repos/$1" commit -q -m "$2"; g "$top/repos/$1" tag -f "$2" > /dev/null; }
clean() { sed -e "s|$top|TOP|g" -E -e 's/[0-9a-f]{12}/HASH/g'; }
for r in alice/shapes bob/units carol/ring dan/plain erin/tools; do mkdir -p "$top/repos/$r"; git init -q "$top/repos/$r"; done
file bob/units/cesia.toml '[project]\nname = "units"\n'
file bob/units/src/meters/meters.ce '(** Meters. *)\nName = "meters of units v1.0.0"\n'
publish bob/units v1.0.0
file bob/units/src/meters/meters.ce '(** Meters. *)\nName = "meters of units v1.2.0"\n'
publish bob/units v1.2.0
file alice/shapes/cesia.toml "[project]\nname = \"shapes\"\n\n[deps.units]\nfrom = \"file://$top/repos/bob/units\"\nversion = \"v1.0.0\"\n"
file alice/shapes/src/geometry/geometry.ce '(** Geometry. *)\nuse area\nDescribe() = Str("a square, ", area.Of(2))\n'
file alice/shapes/src/geometry/geometry.test.ce 'isNothing() = true\n'
file alice/shapes/src/area/area.ce '(** Area. *)\nuse deps/bob/units/meters\nOf(side) = Str(side * side, " ", meters.Name)\n'
file alice/shapes/src/unused/unused.ce '(** Not used. *)\nNothing = 1\n'
file alice/shapes/tests/a.ce 'Print(1)\n'
publish alice/shapes v1.0.0
file alice/shapes/src/geometry/geometry.ce '(** Geometry. *)\nuse area\nDescribe() = Str("a square of v1.1.0, ", area.Of(3))\n'
publish alice/shapes v1.1.0
file erin/tools/cesia.toml "[project]\nname = \"tools\"\n\n[deps.units]\nfrom = \"file://$top/repos/bob/units\"\nversion = \"v1.2.0\"\n"
file erin/tools/src/tool/tool.ce '(** Tool. *)\nuse deps/bob/units/meters\nName = Str("a tool on ", meters.Name)\n'
publish erin/tools v1.0.0
file carol/ring/cesia.toml '[project]\nname = "ring"\n'
file carol/ring/src/a/a.ce '(** A. *)\nuse b\nA() = 1\n'
file carol/ring/src/b/b.ce '(** B. *)\nuse a\nB() = 2\n'
publish carol/ring v1.0.0
file dan/plain/README.md 'no cesia.toml here\n'
publish dan/plain v1.0.0

mkdir -p "$top/proj/src" && cd "$top/proj"
printf '[project]\nname = "proj"\n' > cesia.toml
printf 'use deps/alice/shapes/geometry\nPrint(geometry.Describe())\n' > src/main.ce
echo "== add: geometry, and what it uses"
cesia pkg add "file://$top/repos/alice/shapes@v1.0.0" geometry | clean
find deps -type f | sort
tail -5 cesia.toml | clean
cesia run $no_spec src/main.ce
echo "== a second project asks for units v1.2.0: the highest"
cesia pkg add "file://$top/repos/erin/tools@v1.0.0" | clean
cesia run $no_spec src/main.ce
cesia pkg
echo "== install from the cache, after a clone"
rm -rf deps
cesia pkg install | clean
cesia pkg install
echo "nothing to do: $?"
echo "== what fails leaves deps/ and cesia.lock as they were"
cp cesia.lock "$top/lock-before"
cesia pkg add "file://$top/repos/dan/plain@v1.0.0" 2>&1 | clean
cesia pkg add "file://$top/repos/carol/ring@v1.0.0" nope 2>&1 | clean
cesia pkg add "file://$top/repos/carol/ring@v9.9.9" 2>&1 | clean
echo "== what could leave deps/ or give git an option is refused before git runs"
cesia pkg add "github.com/alice/../../../outside@v1.0.0" 2>&1 | clean
cesia pkg add "--upload-pack=touch $top/ran;://x/y@v1.0.0" 2>&1 | clean
cesia pkg add "file://$top/repos/carol/ring@--help" 2>&1 | clean
ls "$top/ran" "$top/outside" 2> /dev/null || echo "nothing ran, nothing written outside"
cmp cesia.lock "$top/lock-before" && echo "lock unchanged"
find deps -maxdepth 2 -type d | sort
echo "== a ring of uses ends"
cesia pkg add "file://$top/repos/carol/ring@v1.0.0" a | clean
cp cesia.lock "$top/lock-ring"
echo "== a moved tag"
file alice/shapes/src/unused/unused.ce '(** Changed. *)\nNothing = 2\n'
publish alice/shapes v1.0.0
rm -rf deps "$XDG_CACHE_HOME"
cesia pkg install 2>&1 | clean
cmp cesia.lock "$top/lock-ring" && echo "lock unchanged"
ls deps 2> /dev/null || echo "no deps/, as before"
cesia pkg update shapes --to v1.0.0 | clean
echo "== update to the newest tag"
cesia pkg update shapes | clean
grep version cesia.toml
cesia run $no_spec src/main.ce
echo "== move to a fork"
cp -R "$top/repos/alice" "$top/repos/frank"
cesia pkg move alice/shapes frank/shapes | clean
grep from cesia.toml | clean
cat src/main.ce
ls deps
cesia run $no_spec src/main.ce
cesia pkg | clean
echo "== newer tags"
file carol/ring/src/b/b.ce '(** B. *)\nuse a\nB() = 3\n'
publish carol/ring v1.1.0
cesia pkg --check
