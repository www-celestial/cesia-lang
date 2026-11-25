# The time, the milliseconds and the port of each line change from run to run: they are written as T, M and P here.
"$root/_build/default/src/bin/main.exe" run $no_spec --allow net=own observe.ce 2>&1 | sed -E 's/"time":"[0-9T:.Z-]+"/"time":T/; s/"Ms":[0-9.e-]+/"Ms":M/; s/"Port":[0-9]+/"Port":P/'
