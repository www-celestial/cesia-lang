# sys.CopyTree while another process swaps a folder it copies, in the source or in the copy, for a link to a folder out
# of it: it walks by descriptors on both sides, so the link never leads a read or a write elsewhere.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp copy-race.ce copy-race-swap.ce "$dir"
cd "$dir"
mkdir -p shared/tree/sub keep victim victim2
for k in $(seq 100); do
  printf 'copy\n' > "shared/tree/f$k"
  printf 'copy\n' > "shared/tree/sub/f$k"
  printf 'secret\n' > "victim/f$k"
  printf 'old\n' > "victim2/f$k"
done
touch go
cesia run --allow read,write copy-race-swap.ce &
swap=$!
# All rights, as a file manager has: only the walk by descriptors keeps the victims' files.
cesia run $no_spec --allow read,write copy-race.ce 2> /dev/null
echo "exit $?"
rm go
wait $swap
echo "files of the copies that hold the secret: $(find keep -type f -exec grep -l secret {} + | wc -l | tr -d ' ')"
echo "victim2 holds $(find victim2 -type f | wc -l | tr -d ' ') files, $(cat victim2/* | grep -c old) of them old"
