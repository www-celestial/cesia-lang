# sys.RemoveTree while another process swaps the folder it removes, or one inside, for a link to a folder out of it: it
# walks by descriptors, so nothing the link leads to is ever removed.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp remove-race.ce remove-race-swap.ce "$dir"
cd "$dir"
mkdir -p shared victim/sub
for k in $(seq 50); do : > "victim/v$k"; : > "victim/sub/v$k"; done
touch go
cesia run --allow read,write remove-race-swap.ce &
swap=$!
# All rights, as a file manager has: only the walk by descriptors keeps the victim's files.
cesia run $no_spec --allow read,write remove-race.ce 2> /dev/null
echo "exit $?"
rm go
wait $swap
echo "victim holds $(find victim -type f -name 'v*' | wc -l | tr -d ' ') of its files"
