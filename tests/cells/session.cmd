# The side of the session: cesia run --cells runs none of session.ce, and the commands of session.stdin, as std/cells sends
# them, run its cells. The time each cell took varies, and the byte that starts a message shows as @.
cesia run $no_spec --cells session.ce | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' | tr '\001' '@'
