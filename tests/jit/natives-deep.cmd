# The same depths, and the same limit of depth with the same trace, in each mode; on the typed path, machine code made
# at once calls the natives.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec --allow env natives-deep.ce 3000
  CESIA_JIT=$mode cesia run $no_spec --allow env --limit depth=200000 natives-deep.ce 40000
  CESIA_JIT=$mode cesia run $no_spec --allow env --limit depth=999 natives-deep.ce 3000
done
[ -n "$no_spec" ] || [ "$(CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run --allow env natives-deep.ce 10 2>&1 | grep -c 'call pnat, cesia_jit_native')" -gt 0 ] && echo "machine code calls natives"
