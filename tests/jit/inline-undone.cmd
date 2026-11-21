# A statement that doesn't lower drops the code made for it, and now the blocks it made too: one of them kept an error
# that named an inlined frame whose Frame was dropped, and the JIT ended the program with Not_found. The interpreter's
# answers, in each mode.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec inline-undone.ce
done
