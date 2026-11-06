dir=$(mktemp -d)
trap 'chmod -R u+rwx "$dir" 2> /dev/null; rm -rf "$dir"' EXIT
cp walk.ce "$dir"
cd "$dir"
cesia run $no_spec --allow read=.,write=. walk.ce
# A link to a folder is listed, not entered, and a broken one is listed too.
ln -s b tree/link
ln -s nowhere tree/broken
printf 'use std/sys\nuse std/io\nio.Print(sys.Walk("tree"))\n' > links.ce
cesia run $no_spec --allow read=. links.ce
printf 'use std/sys\nuse std/io\nio.Print(sys.Walk("."))\n' > here.ce
(cd tree && cesia run $no_spec --allow read=. ../here.ce)
# A folder that can't be read is the one the Err names.
chmod 000 tree/b/c
cesia run $no_spec --allow read=. links.ce
cesia run $no_spec links.ce
