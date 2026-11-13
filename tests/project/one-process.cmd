cd stop
# The program of the last task runs in the process of cesia do: the shell's $$ is the pid that started cesia do.
pids=$("$root/_build/default/src/bin/main.exe" do pid 2> /dev/null & wait $!; echo "$!")
set -- $pids
if [ "$1" = "$2" ]; then echo "one process"; else echo "two processes: $pids"; fi
