# Code typed at a prompt of a session, line 0, and a cell, each a loop that gives a variable its value, then a function
# that reads it: the last value, which the variables show too, with machine code from hot loops and from the first run.
# The time each cell took varies, and so does the token of the session, told first and held by each message; the byte
# that starts a message shows as @.
answers() { CESIA_JIT=$1 cesia run $no_spec --cells cells-top.ce < cells-top.stdin | tr '\001' '@' | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' -e 's/"Mark":"[0-9a-f]*"/"Mark":"TOKEN"/' -e 's/^@token [0-9a-f]*$/@token TOKEN/'; }
first=$(answers hot)
echo "$first"
[ "$first" = "$(answers off)" ] && echo "the same with the JIT off"
[ "$first" = "$(answers always)" ] && echo "the same with machine code from the first run"
