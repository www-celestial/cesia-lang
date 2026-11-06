# No path: the source folders of cesia.toml, each folder a package with its tests; examples/ is left out. A file of a
# package is read with the other files of its folder, and only its own errors are shown.
cd project
cesia check
echo "exit $?"
cesia check examples
echo "exit $?"
cesia check src/geo/more.ce
