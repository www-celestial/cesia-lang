# The interpreter, native code when hot, and from the first call, each under a young heap of 4,096 words: the same
# values, and the natives' errors at the same sites. On the typed path, machine code made at once reads keys through its
# caches.
for case in struct bytes; do
  for mode in off default always; do
    echo "$case $mode:"
    CESIA_JIT=$mode OCAMLRUNPARAM=s=4k cesia run $no_spec whole-keys.ce $case
  done
done
[ -n "$no_spec" ] || [ "$(CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run whole-keys.ce bytes 2>&1 | grep -c '^  mov r[0-9]*, 9$')" -gt 4 ] && echo "machine code reads keys through caches"
