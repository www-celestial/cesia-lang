# The side of the session: cesia run --cells runs none of session.ce, and the commands of session.stdin, as std/cells sends
# them, run its cells. The time each cell took varies, and so does the token of the session, told first and held by each message; the byte
# that starts a message shows as @.
cesia run $no_spec --cells session.ce | tr '\001' '@' | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' -e 's/"Mark":"[0-9a-f]*"/"Mark":"TOKEN"/' -e 's/^@token [0-9a-f]*$/@token TOKEN/'
