cesia run $no_spec t-print-error.ce 2> /dev/null
echo "only the errors:"
cesia run $no_spec t-print-error.ce > /dev/null
echo "both:"
cesia run $no_spec t-print-error.ce 2>&1
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
printf 'use std/text\ntext.Decimals(2.5, 1)\n' > "$dir/count.ce"
printf 'use std/text\ntext.Decimals(2, "1")\n' > "$dir/number.ce"
cd "$dir"
cesia run $no_spec count.ce
cesia run $no_spec number.ce
