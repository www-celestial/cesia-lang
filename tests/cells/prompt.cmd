# Code typed at a prompt of a session, at line 0, gives a name that holds a value its new one in place: x = x + 1 reads
# the x before, and so do an element of a list, a field of a struct and a sum in a loop, values of a kind or another; an
# error leaves the name as it was when it was raised; the functions defined before read the new value, a loop compiled
# with an Int too; a slider's name stays one that set changes in place, while it holds a number; a cell run again
# forgets its names, as before. The same answers with machine code from the first run. The time each cell took varies,
# and so does the token of the session, told first and held by each message; the byte that starts a message shows as @.
answers() { CESIA_JIT=$1 cesia run $no_spec --cells knobs.ce < prompt.stdin | tr '\001' '@' | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' -e 's/"Mark":"[0-9a-f]*"/"Mark":"TOKEN"/' -e 's/^@token [0-9a-f]*$/@token TOKEN/'; }
first=$(answers "")
echo "$first"
[ "$first" = "$(answers always)" ] && echo "the same with machine code from the first run"
