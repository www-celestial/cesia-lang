# Code typed at a prompt of a session gives in place a variable that code typed there before gave a value, the variable of
# a for too: machine code keeps those its loops assign in registers, and writes them back at the end of a run, at each
# checkpoint, where another fiber reads them, and at an error, after which a variable is as it was when it was raised; a
# slider's variable that set changed, assigned in a loop. The interpreter's answers with machine code from hot loops and
# from the first run. The time each cell took varies, and so does the token of the session, told first and held by each
# message; the byte that starts a message shows as @.
answers() { CESIA_JIT=$1 cesia run $no_spec --cells cells-loops.ce < cells-loops.stdin | tr '\001' '@' | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' -e 's/"Mark":"[0-9a-f]*"/"Mark":"TOKEN"/' -e 's/^@token [0-9a-f]*$/@token TOKEN/'; }
first=$(answers hot)
echo "$first"
[ "$first" = "$(answers off)" ] && echo "the same with the JIT off"
[ "$first" = "$(answers always)" ] && echo "the same with machine code from the first run"
