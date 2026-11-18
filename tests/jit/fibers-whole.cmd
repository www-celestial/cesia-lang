# The top code changes k while another fiber is inside a call whose machine code is the whole function: no error in any
# mode, and each count one that the values of k give.
for mode in off hot always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec fibers-whole.ce
done
