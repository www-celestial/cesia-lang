# The variables of a file's top that loops computed, read by another file: the interpreter's values with machine code from
# hot loops and from the first run. A loop over many quanta of steps, one shorter than a quantum, floats, a list.
for mode in off hot always; do
  echo "$mode: $(CESIA_JIT=$mode cesia run $no_spec top-export.ce)"
done
