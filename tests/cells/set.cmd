# The side of the session for a slider: set gives a name that holds a number a new one in place, and refuses a function, a
# text, a name that holds nothing and a number that isn't finite; a loop compiled while the name held an Int reads the
# Float given in its place. The time each cell took varies, and the byte that starts a message shows as @.
cesia run $no_spec --cells knobs.ce | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' | tr '\001' '@'
