# Random redefinitions in a session, three seeds: each answer the same under the JIT as with the JIT off.
for seed in 1 2 3; do
  hot=$(cesia run $no_spec --seed $seed --allow exec,read twins-fuzz.ce 2>&1)
  off=$(CESIA_JIT=off cesia run $no_spec --seed $seed --allow exec,read twins-fuzz.ce 2>&1)
  if [ "$hot" = "$off" ]; then echo "seed $seed: the same, $(echo "$hot" | wc -l) lines"; else diff <(echo "$off") <(echo "$hot"); fi
done
