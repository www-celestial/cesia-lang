dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp link-rights.ce scope-forms.ce "$dir"
cd "$dir"
mkdir readable out outside
printf 'decoy\n' > readable/decoy.txt
printf 'secret\n' > outside/secret.txt
chmod 644 readable/decoy.txt
printf '1970\n' > out/epoch.txt
touch -d @0 out/epoch.txt
cesia run $no_spec --allow read=readable,read=out,write=out link-rights.ce 2> /dev/null
echo "== readable holds"
cat readable/decoy.txt
ls -l readable | awk 'NR > 1 { print $1, $NF }'
# A folder granted by its absolute path holds the same file named by a relative path, and the reverse.
here=$(pwd)
cesia run $no_spec --allow "read=$here/readable" scope-forms.ce readable/decoy.txt
cesia run $no_spec --allow read=readable scope-forms.ce "$here/readable/decoy.txt"
