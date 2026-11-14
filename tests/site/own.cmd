# A book uses the project's own packages as another project does, use deps/OWNER/REPO/..., OWNER/REPO being those of the
# source of [site]: the site reads them from the project itself, with no copy in deps/. A norun block is checked and never
# run, not even the top of a package it uses: the engine of a native package never loads. No block is ever given the
# native permission, neither one of the project's own book, nor one that asks for it, nor one that uses a dependency.
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
export XDG_CACHE_HOME="$t/cache"
f='```'
p="$t/echo"
# The native package of tests/native, with no engine at all: a native called would stop the build. Its package top calls
# one at its top, as a vocabulary made when the package loads.
cp -R "$root/tests/native/echo" "$p"
mkdir -p "$p/docs/book" "$p/src/greet" "$p/cesia/echo/top"
printf '%s\n' '(** Greetings. *)' 'Hello(name) = "Hello, $name!"  (** A greeting for a name. *)' > "$p/src/greet/greet.ce"
printf '%s\n' '(** A thing made when the package loads. *)' 'use cesia/echo' 'Made = echo.Thing(1)  (** The thing. *)' > "$p/cesia/echo/top/top.ce"
printf '%s\n' '' '[site]' 'source = "https://github.com/someone/echo/blob/main/"' >> "$p/cesia.toml"
page() {  # what goes wrong, then the lines of docs/book/index.md
  echo "== $1"
  shift
  printf '%s\n' "# Echo" "" "$@" > "$p/docs/book/index.md"
  (cd "$p" && cesia doc --site; echo "exit $?") 2>&1 | grep -v ' files: file://' | sed "s#$t#TMP#g"
}
page "the book uses the project as a dependency: run and checked" \
  "${f}cesia" "use deps/someone/echo/src/greet" 'greet.Hello("Ana") -->' "$f" \
  "${f}cesia norun" "use deps/someone/echo/src/greet" "use deps/someone/echo/cesia/echo/top" 'greet.Hello(top.Made)' "$f"
grep -o 'Hello, Ana!' "$p/site/index.html" | head -1
page "a norun block with a mistake, in a package of the project" \
  "${f}cesia norun" "use deps/someone/echo/cesia/echo/top" 'top.Nothing' "$f"
page "another owner is no address of the project" \
  "${f}cesia" "use deps/other/echo/src/greet" 'greet.Hello("Ana")' "$f"
page "a block that runs a native of the project's own package" \
  "${f}cesia" "use deps/someone/echo/cesia/echo/top" 'top.Made' "$f"
page "a block that asks for the native permission" \
  "${f}cesia allow=native=echo" "1" "$f"
sed '/^source = /d' "$p/cesia.toml" > "$t/toml" && mv "$t/toml" "$p/cesia.toml"
page "without the source of [site], the same use is of a dependency" \
  "${f}cesia" "use deps/someone/echo/src/greet" 'greet.Hello("Ana")' "$f"
# A project that takes the package from deps/, as cesia pkg installs it: its natives get no permission either.
a="$t/app"
mkdir -p "$a/deps/someone/echo" "$a/docs/book"
cp -R "$p/cesia" "$p/src" "$p/cesia.toml" "$a/deps/someone/echo/"
printf '[project]\nname = "app"\n\n[deps.echoes]\nfrom = "github.com/someone/echo"\nversion = "v0.1.0"\ntake = ["cesia/echo", "cesia/echo/top"]\n' > "$a/cesia.toml"
(cd "$a" && cesia run --allow read,write "$root/tests/native/lock.ce")
p=$a
page "a dependency's native package: checked in a norun block, refused in a block that runs" \
  "${f}cesia norun" "use deps/someone/echo/cesia/echo/top" 'top.Made' "$f" \
  "${f}cesia" "use deps/someone/echo/cesia/echo/top" 'top.Made' "$f"
