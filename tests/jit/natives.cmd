# Each mode under a young heap of 4,096 words, which collects in nearly every call of a native: the same values. Then
# machine code that calls natives, made at once, on the typed path (the other one makes less machine code).
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode OCAMLRUNPARAM=s=4k cesia run $no_spec natives.ce
done
[ -n "$no_spec" ] || [ "$(CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run natives.ce 2>&1 | grep -c 'call pnat, cesia_jit_native')" -gt 3 ] && echo "machine code calls natives"
