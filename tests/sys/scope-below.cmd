# read= and write= when the act opens from the folder of its grant, which the kernel keeps it below (openat2 on Linux):
# a path that leaves on the way and comes back in, by an absolute link or by .., or that goes into another folder
# granted, is taken where it leads; one that leads out is denied, as on every system.
dir=$(mktemp -d)
trap 'chmod -R u+rwx "$dir"; rm -rf "$dir"' EXIT
cp scope-below.ce "$dir"
cd "$dir"
top=$(pwd -P)
mkdir a b outside a/locked
printf 'in\n' > a/in.txt
printf 'b\n' > b/x.txt
printf 'secret\n' > outside/s.txt
printf 'l\n' > a/locked/l.txt
ln -s "$top/a/in.txt" a/abs-in
ln -s "$top/b/x.txt" a/to-b
ln -s "$top/outside/s.txt" a/abs-out
ln -s new.txt a/dangling
chmod 300 a/locked
cesia run $no_spec --allow "read=a,read=b,write=$top/a" scope-below.ce "$top" 2> /dev/null
echo "exit $?"
chmod 700 a/locked
echo "== a holds"
find a | LC_ALL=C sort
echo "== b and outside: $(cat b/x.txt outside/s.txt | tr '\n' ' ')"
