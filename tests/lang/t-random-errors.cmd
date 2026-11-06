# What random refuses, and a seed that isn't a number.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
printf 'use std/random\nrandom.Int(3, 1)\n' > "$dir/range.ce"
printf 'use std/random\nrandom.Pick([])\n' > "$dir/empty.ce"
printf 'use std/random\nuse std/io\nio.Print(random.Seed())\n' > "$dir/seed.ce"
cd "$dir"
cesia run $no_spec range.ce
cesia run $no_spec empty.ce
cesia run $no_spec --seed -12 seed.ce
cesia run $no_spec --seed twelve seed.ce
