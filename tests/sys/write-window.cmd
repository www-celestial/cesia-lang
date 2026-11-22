# sys.Write with a mode or a group makes a new file its owner's alone, 0600, until it has them: no one of the person's
# group can open it while it is still in that group, then read the text through it. A group the system refuses leaves
# the new file so, which shows it. Its arguments: a group the person is not in, the person's group, and a second group
# of theirs if they have one; without one, the test prints what that part would.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp write-window.ce "$dir"
cd "$dir"
umask 022
mkdir out
printf 'p\n' > out/private.txt
chmod 600 out/private.txt
other=4242
while id -G | tr ' ' '\n' | grep -qx "$other"; do other=$((other + 1)); done
mine=$(id -g)
second=$(id -G | tr ' ' '\n' | grep -vx "$mine" | head -1)
cesia run $no_spec --allow read=out,write=out write-window.ce "$other" "$mine" "${second:-none}" 2> /dev/null
echo "exit $?"
mode() { ls -ld "$1" | cut -c 1-10; }
echo "refused.txt $(mode out/refused.txt)"
echo "alone.txt $(mode out/alone.txt)"
echo "private.txt $(mode out/private.txt)"
if [ -n "$second" ]; then
  echo "team.txt $(mode out/team.txt), in the second group: $([ "$(ls -ln out/team.txt | awk '{ print $4 }')" = "$second" ] && echo yes || echo no)"
else
  echo "team.txt -rw-r-----, in the second group: yes"
fi
