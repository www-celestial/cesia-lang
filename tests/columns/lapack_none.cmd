KEPLER_BLAS=none "$root/_build/default/bin/main.exe" run $no_spec lapack_none.kp
KEPLER_BLAS=/no/such/library.so "$root/_build/default/bin/main.exe" run $no_spec lapack_none.kp | head -1
