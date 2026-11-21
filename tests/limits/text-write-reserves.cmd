# Each way of writing values as a text, past the limit of memory; the line of each message.
for way in value interpolation print json csv; do
  out=$(cesia run $no_spec --limit memory=16M text-write-reserves.ce $way 2>&1); code=$?
  echo "$way $code ${out%%$'\n'*}"
done
