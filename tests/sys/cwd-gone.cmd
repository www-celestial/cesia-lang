# cwd-gone.ce run from a folder removed before it starts, as another process may remove it while it runs; then a grant
# of read=., a folder relative to one that is gone: it holds nothing, and the read is denied, where the program ended.
dir=$(mktemp -d)
trap 'cd / && rm -rf "$dir"' EXIT
cp cwd-gone.ce "$dir"
mkdir "$dir/gone"
cd "$dir/gone"
rmdir "$dir/gone"
cesia run $no_spec --allow read,exec "$dir/cwd-gone.ce" 2> /dev/null
echo "exit $?"
printf 'use std/sys\nuse std/io\nio.Print(sys.Exists("a.txt"))\n' > "$dir/read.ce"
{ cesia run $no_spec --allow read=. "$dir/read.ce"; echo "exit $?"; } 2>&1 | sed "s#$dir#DIR#g"
