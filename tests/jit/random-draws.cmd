# The interpreter, native code from the first run, then from when it gets hot, with two seeds: the same numbers.
for seed in 7 -1; do
  for mode in off always hot; do
    echo "$mode $seed:"
    CESIA_JIT=$mode cesia run $no_spec --seed $seed random-draws.ce
  done
done
