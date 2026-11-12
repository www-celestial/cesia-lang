cd orphans
cesia test $no_spec tests
echo "exit $?"
# The test of a system with no pgrep passes: it has nothing to look with.
if command -v pgrep > /dev/null && pgrep -f "^sleep 30[1-4]$" > /dev/null; then echo "a program outlived its test"; else echo "no program left"; fi
