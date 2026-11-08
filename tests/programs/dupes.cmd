# The chapter of the book that finds duplicate files shows every line of its test and of its timed program: a line it
# doesn't show is printed here.
for f in dupes.test.ce ../../bench/dupes.ce; do
  grep -v '^$' "$f" | grep -vxF -f ../../docs/book/duplicates.md | sed "s#^#$f: #"
done
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp dupes.test.ce "$dir"
cd "$dir"
# The shortcut by size fails and shrinks, as the chapter shows; the two ways that read the files hold on 100 folders each.
TMPDIR="$dir" cesia test $no_spec --seed 1 dupes.test.ce | sed -E "s#$dir/cesia-test-[0-9a-f-]+/#TEMP/#"
echo "exit ${PIPESTATUS[0]}"
