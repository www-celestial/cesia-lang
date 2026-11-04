top=$(mktemp -d)
mkdir -p "$top/pkg/heap" "$top/pkg/date" "$top/src/shapes" "$top/apps/tools"
printf '[project]\nname = "p"\nsrc = ["src", "apps"]\n' > "$top/cesia.toml"
{ cat ../../src/std/heap.ce; printf '\nPrint("the copy of heap")\n'; } > "$top/pkg/heap/heap.ce"
printf '(** A copy. *)\nToday() = "the copy of date"\n' > "$top/pkg/date/date.ce"
printf '(** In src. *)\nName = "shapes, in src"\n' > "$top/src/shapes/shapes.ce"
printf '(** In apps. *)\nName = "tools, in apps"\n' > "$top/apps/tools/tools.ce"
printf 'use pkg/date\nuse pkg/algo\nuse shapes\nuse tools\nPrint(date.Today())\nPrint(algo.Gcd(12, 18))\nPrint(shapes.Name)\nPrint(tools.Name)\n' > "$top/src/main.ce"
cd "$top"
cesia run $no_spec src/main.ce
cesia test $no_spec .
cesia test $no_spec pkg/heap | tail -1
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
