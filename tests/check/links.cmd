# A link to a folder is never followed, so a loop ends; a link that leads nowhere is left out; an error is its message.
dir=$(mktemp -d)
trap 'chmod -R u+rwx "$dir" 2> /dev/null; rm -rf "$dir"' EXIT
mkdir "$dir/src" "$dir/locked"
printf 'use std/io\nio.Print(y)\n' > "$dir/src/a.ce"
ln -s .. "$dir/src/up"
ln -s /nonexistent "$dir/src/e.ce"
ln -s a.ce "$dir/src/b.ce"
cd "$dir"
cesia check src
echo "exit $?"
chmod 000 locked
cesia check locked
