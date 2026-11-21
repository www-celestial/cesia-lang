# What cesia pkg takes from where: a fetched project that holds a link is refused before a byte of it is copied, so that
# no file of the person out of it reaches deps/; two repositories that end in the same folders are two in the cache; a
# source fetched without encryption is refused before git runs.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
export XDG_CACHE_HOME="$top/cache" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 LC_ALL=C
g() { git -C "$1" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c tag.gpgsign=false "${@:2}"; }
file() { mkdir -p "$(dirname "$top/$1")"; printf "$2" > "$top/$1"; }
publish() { g "$top/$1" add -A; g "$top/$1" commit -q -m "$2"; g "$top/$1" tag -f "$2" > /dev/null; }
clean() { sed -e "s|$top|TOP|g" -E -e 's/[0-9a-f]{12}/HASH/g'; }
project() { mkdir -p "$top/$1/src" && printf "[project]\nname = \"p\"\n\n[deps.geometry]\nfrom = \"%s\"\nversion = \"v1.0.0\"\n" "$2" > "$top/$1/cesia.toml"; }
file secret.txt 'SECRET of the person\n'
for r in links/someone/geometry codelink/someone/geometry evil/someone/geometry genuine/someone/geometry; do mkdir -p "$top/$r"; git init -q "$top/$r"; done
ln -s "$top/secret.txt" "$top/links/someone/geometry/cesia.toml"
file links/someone/geometry/src/shapes/shapes.ce '(** Shapes. *)\nName = "shapes"\n'
publish links/someone/geometry v1.0.0
file codelink/someone/geometry/cesia.toml '[project]\nname = "geometry"\n'
mkdir -p "$top/codelink/someone/geometry/src/shapes"
ln -s "$top/secret.txt" "$top/codelink/someone/geometry/src/shapes/shapes.ce"
publish codelink/someone/geometry v1.0.0
for r in evil genuine; do
  file $r/someone/geometry/cesia.toml '[project]\nname = "geometry"\n'
  file $r/someone/geometry/src/shapes/shapes.ce "(** Shapes. *)\nName = \"shapes of $r\"\n"
  publish $r/someone/geometry v1.0.0
done
echo "== a cesia.toml that is a link"
project p1 "file://$top/links/someone/geometry"
cd "$top/p1" && cesia pkg install 2>&1 | clean
ls deps 2> /dev/null || echo "no deps/"
echo "== code that is a link"
project p2 "file://$top/codelink/someone/geometry"
cd "$top/p2" && cesia pkg install 2>&1 | clean
grep -r SECRET deps 2> /dev/null || echo "the secret is not in deps/"
echo "== two repositories that end in the same folders"
project p3 "file://$top/evil/someone/geometry"
cd "$top/p3" && cesia pkg install 2>&1 | clean
project p4 "file://$top/genuine/someone/geometry"
cd "$top/p4" && cesia pkg install 2>&1 | clean
grep Name deps/someone/geometry/src/shapes/shapes.ce
echo "== without encryption"
for from in http://github.com/someone/geometry git://github.com/someone/geometry HTTP://github.com/someone/geometry; do
  project p5 "$from"
  cd "$top/p5" && cesia pkg install 2>&1 | clean
done
ls "$XDG_CACHE_HOME/cesia/git" | wc -l
