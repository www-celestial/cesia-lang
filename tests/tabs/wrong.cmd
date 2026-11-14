# Each way a tab goes wrong, at the line of its page: other values, a stop, the network, past 1 GiB of memory, a file past
# 64 MiB, past its time. The lines of a stop are Python's, which change with its version: its last line alone is kept.
w=$(mktemp -d)
(unset CI; cesia run --allow "read,write=$w,exec=prlimit,env=CI,env=PATH" "$root/tools/tabs.ce" wrong.json "$w" --seconds 2; echo "exit $?") 2>&1 |
  sed 's/ in [0-9.]* s$//' | grep -E -v '^    ' 
(unset CI; cesia run --allow "read,write=$w,exec=prlimit,env=CI,env=PATH" "$root/tools/tabs.ce" wrong.json "$w" --seconds 2) 2>&1 |
  grep -E '^    (ValueError|OSError|MemoryError)'
echo "left: $(ls -A "$w" | wc -l)"
echo '[{"Page": 1}]' > "$w/bad.json"
cesia run --allow "read,write=$w,exec=prlimit,env=CI,env=PATH" "$root/tools/tabs.ce" "$w/bad.json" "$w" 2>&1 | sed "s#$w#TMP#"
echo "exit ${PIPESTATUS[0]}"
cesia run --allow "read,write=$w,exec=prlimit,env=CI,env=PATH" "$root/tools/tabs.ce" agree.json "$w" --seconds x 2>&1 | sed "s#$w#TMP#"
echo "exit ${PIPESTATUS[0]}"
rm -rf "$w"
