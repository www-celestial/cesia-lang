# cesia fmt on a copy of every file of Cesia's src, tests and examples, and of Ceres, Centauri and Cemacs when they are
# beside this checkout in the family's folder: fmt names no file as its bug, each formatted file keeps its tree (same.ce),
# a file that doesn't read stays as it is, and fmt on its own output changes nothing.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
# The .ce files under the folders given, from the folder $1, into $2: no _build, dot folder, deps or std copy.
copy() {
  from=$1 to=$2
  shift 2
  mkdir -p "$to"
  (cd "$from" && find "$@" \( -name _build -o -name '.?*' -o -path ./deps -o -path ./std \) -prune -o -name '*.ce' -print0 | tar -cf - --null -T -) | tar -xf - -C "$to"
}
copy "$root" "$top/a/cesia" src tests examples
# The family's folder holds the main checkout, whose worktrees may be elsewhere.
family=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2> /dev/null)
family=${family%/.git}
family=${family%/*}
for p in ceres centauri cemacs; do
  if [ -n "$family" ] && [ -f "$family/$p/cesia.toml" ]; then copy "$family/$p" "$top/a/$p" .; fi
done
cp -R "$top/a" "$top/b"
cesia fmt "$top/b" > /dev/null 2> "$top/fmt.err"
# A file that doesn't read is named, and left: any other word of fmt is a bug.
grep -v 'fmt leaves the file as it is\.$' "$top/fmt.err" | sed "s|$top/b/||"
cesia run --allow read="$top" same.ce "$top/a" "$top/b"
cesia fmt --check "$top/b" 2> /dev/null | sed "s|^$top/b/|changed again: |"
echo "fmt twice: done"
