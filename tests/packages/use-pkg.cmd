top=$(mktemp -d)
mkdir -p "$top/std/heap" "$top/std/date" "$top/src/shapes" "$top/apps/tools"
printf '[project]\nname = "p"\nsrc = ["src", "apps"]\n' > "$top/cesia.toml"
{ cat ../../src/std/heap.ce; printf '\nPrint("the copy of heap")\n'; } > "$top/std/heap/heap.ce"
printf '(** A copy. *)\nToday() = "the copy of date"\n' > "$top/std/date/date.ce"
printf '(** In src. *)\nName = "shapes, in src"\n' > "$top/src/shapes/shapes.ce"
printf '(** In apps. *)\nName = "tools, in apps"\n' > "$top/apps/tools/tools.ce"
printf 'use std/date\nuse std/algo\nuse src/shapes\nuse apps/tools\nPrint(date.Today())\nPrint(algo.Gcd(12, 18))\nPrint(shapes.Name)\nPrint(tools.Name)\n' > "$top/src/main.ce"
cd "$top"
"$root/_build/default/src/bin/main.exe" run --allow read,write "$root/tests/packages/make-lock.ce"
cesia run $no_spec src/main.ce
cesia test $no_spec .
cesia test $no_spec std/heap | tail -1
printf 'use pkg/nope\n' > src/nope.ce
cesia run $no_spec src/nope.ce
printf 'use pkg/json\n' > src/binary.ce
cesia run $no_spec src/binary.ce
printf '[project]\nname = "p"\nsrc = ["src",\n  "nope"]\n' > cesia.toml
cesia run $no_spec src/main.ce
code=$?
cd /
rm -rf "$top"
(exit $code)
