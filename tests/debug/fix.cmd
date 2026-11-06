dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp fix.ce "$dir/app.ce"
cp dbg-fix.ce "$dir/"
cd "$dir" && cesia run $no_spec --allow read,write --debugger dbg-fix.ce app.ce
