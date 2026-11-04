one=$(CESIA_BLAS=none CESIA_CORES=1 "$root/_build/default/src/bin/main.exe" run $no_spec cores.ce 2>&1)
three=$(CESIA_BLAS=none CESIA_CORES=3 "$root/_build/default/src/bin/main.exe" run $no_spec cores.ce 2>&1)
echo "$one" | head -1
echo "$three" | head -1
[ "$(echo "$one" | tail -n +2)" = "$(echo "$three" | tail -n +2)" ] && echo same
echo "$three" | tail -4
