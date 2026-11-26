port=$("$root/_build/default/src/bin/main.exe" run --allow net=own "$root/tests/free-port.ce")
mkdir -p perm_ro/perm_work
echo x > perm_ro/perm_work/a
cd perm_ro
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read=./perm_work ../permissions.ce $port 2>/dev/null
code=$?
cd ..
rm -r perm_ro
(exit $code)
