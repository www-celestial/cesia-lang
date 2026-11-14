# Tabs that print what their cesia block showed, in other forms: floats to their digits, an integer and the same float, True
# and true, nan and inf, a matrix as numpy prints it, a date and a text. Each runs in a folder of its own, only its owner's,
# with the files of its book, and the folder is gone after it; no variable of the environment reaches it but PATH, and its
# HOME is its folder.
w=$(mktemp -d)
(unset CI; export TABS_SECRET=hidden; cesia run --allow "read,write=$w,exec=prlimit,env=CI,env=PATH" "$root/tools/tabs.ce" agree.json "$w") 2>&1 | sed 's/ in [0-9.]* s$//'
echo "left: $(ls -A "$w" | wc -l)"
rm -rf "$w"
