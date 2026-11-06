# A time that no clock can place is a panic of Cesia, as a date out of range is, never an error of the system.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
for x in 1e300 math.Nan "0 - 1e15" "(1.0 / 0.0)"; do
  printf 'use std/date\nuse std/io\nuse std/math\nio.Print(date.Local(%s))\n' "$x" > "$dir/t.ce"
  (cd "$dir" && cesia run $no_spec t.ce)
done
printf 'use std/date\nuse std/io\nio.Print(date.Format(date.Utc(date.Local(999999999999999))))\n' > "$dir/edge.ce"
(cd "$dir" && TZ=UTC cesia run $no_spec edge.ce)
