mkdir -p planted.framework
cp "$root/_build/default/tests/c/libfixture.so" planted.framework/planted
"$root/_build/default/src/bin/main.exe" run $no_spec --allow ffi=planted planted.k
code=$?
rm -r planted.framework
(exit $code)
