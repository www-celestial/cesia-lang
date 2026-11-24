# The STL written, then read under a limit of 32 MB; what the program prints, without where the limit stopped it. The
# folder of the file is made here and taken away after.
dir=$(mktemp -d)
cesia run $no_spec --allow write="$dir" stl-memory.ce make "$dir/big.stl"
cesia run $no_spec --limit memory=32M --allow read="$dir" stl-memory.ce read "$dir/big.stl" 2> /dev/null
echo "exit $?"
rm -r "$dir"
