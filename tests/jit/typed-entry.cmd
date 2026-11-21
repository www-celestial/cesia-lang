# A typed parameter's check holds in each mode, CESIA_JIT=always too: the interpreter's answer.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec typed-entry.ce 2>&1 | head -2
done
