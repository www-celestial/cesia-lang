dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp stat-kinds.ce "$dir"
cd "$dir"
mkfifo pipe
mkdir folder
ln -s text.txt link-text
ln -s folder link-folder
ln -s /dev/zero link-device
ln -s pipe link-pipe
ln -s nothing link-broken
# A Stat that opened the FIFO would hang here.
timeout -s KILL 5 "$root/_build/default/src/bin/main.exe" run $no_spec --allow read,write=. stat-kinds.ce
