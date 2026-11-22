# sys.Write with new = true makes only a new file: a file or a link planted at the name, even one that leads nowhere, is
# an Err and stays as it was, under a grant of the folder and under one of the file itself; it goes with sync, mode,
# group and private.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp write-new.ce "$dir"
cd "$dir"
umask 022
mkdir out outside
printf 'planted\n' > out/planted.txt
printf 'victim\n' > outside/victim.txt
ln -s ../outside/victim.txt out/to-victim
ln -s ../outside/nothing.txt out/to-nothing
echo "== write=out"
cesia run $no_spec --allow read=out,write=out write-new.ce folder "$(id -g)" 2> /dev/null
echo "exit $?"
echo "== write=out/fresh.txt, write=out/to-victim, write=out/to-nothing"
cesia run $no_spec --allow read=out,write=out/fresh.txt,write=out/to-victim,write=out/to-nothing write-new.ce file "$(id -g)" 2> /dev/null
echo "exit $?"
echo "== out holds"
LC_ALL=C ls -l out | awk 'NR > 1 { print substr($1, 1, 10), $NF }'
echo "== outside holds: $(LC_ALL=C ls outside | tr '\n' ' ')$(cat outside/victim.txt)"
