KEPLER_BLAS=none "$root/_build/default/src/bin/main.exe" run $no_spec lapack-none.k
KEPLER_BLAS=/no/such/library.so "$root/_build/default/src/bin/main.exe" run $no_spec lapack-none.k | head -1
