# A version of digits and dots only: one with a / was a path from the current folder, which opened a library that
# --allow ffi=m doesn't grant.
mkdir -p vplant/libm.so.6 vplant/other
cp "$root/_build/default/tests/c/libfixture.so" vplant/other/libother.so
cd vplant
out=$("$root/_build/default/src/bin/main.exe" run $no_spec --allow ffi=m ../version-path.ce 2>&1); code=$?
cd ..
rm -r vplant
echo "${out%%$'\n'*}"
(exit $code)
