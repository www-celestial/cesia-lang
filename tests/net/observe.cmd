# The time and the milliseconds of each line change from run to run: they are written as T and M here.
"$root/_build/default/src/bin/main.exe" run $no_spec --allow net=own observe.ce 2>&1 | sed -E 's/"time":"[0-9T:.Z-]+"/"time":T/; s/"Ms":[0-9.e-]+/"Ms":M/'
