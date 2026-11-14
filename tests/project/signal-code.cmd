cd signal_code
# A task it needs killed by a signal stops cesia do with 1: what came after didn't run.
cesia do a
echo "exit $?"
# The last task becomes cesia do: killed by TERM, it gives the shell's 128 + 15, as cesia run would. Bash may tell of
# the death on its own stderr, which the redirection holds, with the line cesia do prints.
{ cesia do b; } 2> /dev/null
