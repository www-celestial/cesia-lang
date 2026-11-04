CESIA_BLAS=none "$root/_build/default/src/bin/main.exe" run $no_spec lapack-none.ce
CESIA_BLAS=/no/such/library.so "$root/_build/default/src/bin/main.exe" run $no_spec lapack-none.ce | head -1
