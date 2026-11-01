mkdir -p planted.framework
cp "$root/_build/default/tests/c/libfixture.so" planted.framework/planted
"$root/_build/default/bin/main.exe" run $no_spec --allow ffi=planted planted.kp
code=$?
rm -r planted.framework
(exit $code)
