# Where the limit is seen differs between the paths, so only the message is compared.
for p in "" --no-spec; do
  out=$(cesia run $p --limit memory=16M memory-comprehension.ce 2>&1)
  echo "$? ${out#*: }" | head -1
done
