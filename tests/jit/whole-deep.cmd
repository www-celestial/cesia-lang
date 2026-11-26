# A machine's stack of 1 MB, which a recursion of 60,000 calls passes: the interpreter, native code when hot and from the
# first call, under a young heap of 4,096 words, give the same values, the same error and trace, and the same limit of
# depth, reached past the stack; native code took the stack to its end, then the interpreter made the calls deeper.
ulimit -s 1024 2> /dev/null
for case in numbers values callback error limit; do
  for mode in off default always; do
    echo "$case $mode:"
    limit=1000000
    [ "$case" = limit ] && limit=30000
    CESIA_JIT=$mode OCAMLRUNPARAM=s=4k cesia run $no_spec --limit depth=$limit whole-deep.ce $case 2>&1 | head -14
  done
done
# Both ways taken: a unit of numbers that stops, on the typed path, and one that calls on through OCaml, on each path.
short=yes
for case in numbers values; do
  [ -n "$no_spec" ] && [ $case = numbers ] && continue
  CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run $no_spec --limit depth=1000000 whole-deep.ce $case 2>&1 | grep -q "the machine's stack short" || short=no
done
echo "the machine's stack short: $short"
