# The interpreter, native code when hot, and from the first call, each under a young heap of 4,096 words: the same
# values, and the same errors at the same sites with the same traces. On the typed path, machine code made at once reads
# fields through its caches.
for case in key list big text order; do
  for mode in off default always; do
    echo "$case $mode:"
    CESIA_JIT=$mode OCAMLRUNPARAM=s=4k cesia run $no_spec whole-values.ce $case
  done
done
[ -n "$no_spec" ] || [ "$(CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run whole-values.ce key 2>&1 | grep -c '^  mov r[0-9]*, 3$')" -gt 10 ] && echo "machine code reads fields through caches"
