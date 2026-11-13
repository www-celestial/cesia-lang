# A language whose program isn't here is skipped with a warning, and so is every tab where they can't be capped; but not
# where CI is set: there each fails. Here python3 alone is there, beside prlimit, env and unshare.
w=$(mktemp -d)
bin=$(mktemp -d)
for p in prlimit env unshare; do ln -s "$(command -v $p)" "$bin/$p"; done
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$bin/python3"
run() {
  (export PATH="$bin" CI="$1"; cesia run --allow "read,write=$w,exec=prlimit,env=CI" "$root/tools/tabs.ce" "$2" "$w"; echo "exit $?") 2>&1 |
    sed -e 's/ in [0-9.]* s$//' -e 's/ (exit [^)]*)//'
}
echo "== here"
run "" missing.json
echo "== in CI"
run true missing.json
rm "$bin/unshare"
echo "== without unshare, here"
run "" missing.json
echo "== without unshare, in CI"
run true missing.json
echo "== a site without tabs"
run "" "$w/none.json"
rm -rf "$w" "$bin"
