# The last Fetch finds a port where nothing listens: one that the system gave free a moment before, which the program
# may connect to as well as its own listeners.
closed=$(cesia run --allow net=own "$root/tests/free-port.ce")
cesia run $no_spec --allow net=own,net=127.0.0.1:$closed http-get-bad.ce $closed
