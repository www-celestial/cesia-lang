KEPLER_BLAS=none "$root/_build/default/bin/main.exe" run $no_spec lapack_none.k
KEPLER_BLAS=/no/such/library.so "$root/_build/default/bin/main.exe" run $no_spec lapack_none.k | head -1
