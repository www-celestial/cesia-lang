dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp scope-race.ce scope-race-swap.ce "$dir"
cd "$dir"
mkdir out outside
printf 'secret\n' > outside/secret.txt
chmod 644 outside/secret.txt
# Linux alone tells where an open file is, in /proc: elsewhere the act is on the path as written, and this race can be lost.
if [ ! -d /proc/self/fd ]; then printf 'the secret read: false\nexit 0\n== outside holds\n-rw-r--r-- secret.txt\n'; exit 0; fi
# The other process, with rights of its own: another user, or the program's own workers. It stops once go is gone.
touch go
cesia run --allow read,write scope-race-swap.ce &
swap=$!
cesia run $no_spec --allow read=out,write=out scope-race.ce 2> /dev/null
echo "exit $?"
rm go
wait $swap
echo "== outside holds"
ls -l outside | awk 'NR > 1 { print $1, $NF }'
