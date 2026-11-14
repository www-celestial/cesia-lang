# A tab that runs past its time is stopped, at the line of its page, and its folder is gone after it. Slow by nature: it
# spins its 2 seconds of the processor.
w=$(mktemp -d)
(unset CI; cesia run --allow "read,write=$w,exec=prlimit,env=CI,env=PATH" "$root/tools/tabs.ce" time.json "$w" --seconds 2; echo "exit $?") 2>&1 |
  sed 's/ in [0-9.]* s$//'
echo "left: $(ls -A "$w" | wc -l)"
rm -rf "$w"
