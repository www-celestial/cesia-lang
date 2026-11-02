one=$(KEPLER_BLAS=none KEPLER_CORES=1 "$root/_build/default/bin/main.exe" run $no_spec cores.k 2>&1)
three=$(KEPLER_BLAS=none KEPLER_CORES=3 "$root/_build/default/bin/main.exe" run $no_spec cores.k 2>&1)
echo "$one" | head -1
echo "$three" | head -1
[ "$(echo "$one" | tail -n +2)" = "$(echo "$three" | tail -n +2)" ] && echo same
echo "$three" | tail -4
