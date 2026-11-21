# The side of the session for a slider: set gives a name that holds a number a new one in place, and refuses a function, a
# text, a name that holds nothing and a number that isn't finite; a loop compiled while the name held an Int reads the
# Float given in its place. The time each cell took varies, and so does the token of the session, told first and held by each message; the byte
# that starts a message shows as @.
cesia run $no_spec --cells knobs.ce | tr '\001' '@' | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' -e 's/"Mark":"[0-9a-f]*"/"Mark":"TOKEN"/' -e 's/^@token [0-9a-f]*$/@token TOKEN/'
