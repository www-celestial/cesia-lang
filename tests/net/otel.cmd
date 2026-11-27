# The time and the ids of a trace in each line of std/log change from run to run: they are written as T and I here.
"$root/_build/default/src/bin/main.exe" run $no_spec --allow net=own otel.ce 2>&1 | sed -E 's/"time":"[0-9T:.Z-]+"/"time":T/; s/"(trace_id|span_id)":"[0-9a-f]+"/"\1":I/g'
