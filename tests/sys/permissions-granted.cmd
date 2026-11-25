port=$("$root/_build/default/src/bin/main.exe" run --allow net=own "$root/tests/free-port.ce")
mkdir -p perm_work
CESIA_PERM=1 "$root/_build/default/src/bin/main.exe" run $no_spec --allow read=./perm_work,write=./perm_work,exec=true,env=CESIA_PERM,net=:$port,net=127.0.0.1:$port permissions.ce $port 2>/dev/null
code=$?
rm -r perm_work
(exit $code)
