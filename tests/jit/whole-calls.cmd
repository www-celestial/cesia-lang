# The interpreter, native code when hot, and from the first call, each under a young heap of 4,096 words: the same
# values, the same error with the same trace, the same limit of depth. On the typed path, machine code made at once calls
# through OCaml.
for case in error depth; do
  for mode in off default always; do
    echo "$case $mode:"
    CESIA_JIT=$mode OCAMLRUNPARAM=s=4k cesia run $no_spec --limit depth=2000 whole-calls.ce $case 2>&1 | head -12
  done
done
[ -n "$no_spec" ] || [ "$(CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run whole-calls.ce error 2>&1 | grep -c 'call pnat, cesia_jit_native')" -gt 10 ] && echo "machine code calls through OCaml"
