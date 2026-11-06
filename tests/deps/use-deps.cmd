# use deps/OWNER/REPO/PATH: a folder of another project, from its root; its code reads its own project from there,
# and std/ and deps/ from the project that runs.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
dep="$top/deps/www-celestial/cemacs"
mkdir -p "$top/src" "$top/std/rope" "$dep/src/folders" "$dep/core/commands" "$top/deps/gitlab.com/x/y/src/z"
printf '[project]\nname = "p"\n\n[deps.cemacs]\nfrom = "github.com/www-celestial/cemacs"\nversion = "v0.3.0"\ntake = ["src/folders"]\n\n[tasks.run]\nfile = "src/main.ce"\n' > "$top/cesia.toml"
printf '[project]\nname = "cemacs"\nsrc = ["core", "src"]\n' > "$dep/cesia.toml"
printf 'use core/commands\nuse std/rope\n(** Folders. *)\nName() = Str("folders, then ", commands.Name(), ", then ", rope.Text(rope.Of("a rope")))\n' > "$dep/src/folders/folders.ce"
printf '(** Commands. *)\nName() = "commands"\n' > "$dep/core/commands/commands.ce"
printf '[project]\nname = "y"\n' > "$top/deps/gitlab.com/x/y/cesia.toml"
printf '(** Z. *)\nName = "z, from gitlab.com"\n' > "$top/deps/gitlab.com/x/y/src/z/z.ce"
{ cat ../../src/std/rope.ce; printf '\nPrint("the rope of the project")\n'; } > "$top/std/rope/rope.ce"
printf 'use deps/www-celestial/cemacs/src/folders\nuse deps/gitlab.com/x/y/src/z\nPrint(folders.Name())\nPrint(z.Name)\n' > "$top/src/main.ce"
cd "$top"
"$root/_build/default/src/bin/main.exe" run --allow read,write "$root/tests/packages/make-lock.ce"
cesia run $no_spec src/main.ce
cesia do run
echo "do: $?"
# Their code is theirs: the project can't use it as its own.
printf 'use commands\n' > src/theirs.ce
cesia run $no_spec src/theirs.ce
printf 'use deps/www-celestial/cemacs\n' > src/short.ce
cesia run $no_spec src/short.ce
rm -r deps/gitlab.com
cesia run $no_spec src/main.ce
printf '[project]\nname = "p"\n\n[deps.cemacs]\nfrom = "github.com/www-celestial/cemacs"\nnope = "x"\n\n[tasks.run]\nfile = "src/main.ce"\n' > cesia.toml
cesia do run
