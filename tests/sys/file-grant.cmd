# A grant that names a file is that file alone, for the acts that came after Cesia 4e5c0d8 too.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp file-grant.ce "$dir"
cd "$dir"
umask 022
printf 'src\n' > src.txt
printf 'old\n' > doc.txt
cesia run $no_spec --allow read=src.txt,write=doc.txt,write=new.txt file-grant.ce 2> /dev/null
echo "exit $?"
LC_ALL=C ls -l | awk 'NR > 1 { print substr($1, 1, 10), $NF }'
cat doc.txt new.txt
