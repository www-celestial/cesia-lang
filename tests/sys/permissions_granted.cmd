mkdir -p perm_work
KEPLER_PERM=1 "$root/_build/default/bin/main.exe" run $no_spec --allow read=./perm_work,write=./perm_work,exec=true,env=KEPLER_PERM,net=:18102,net=127.0.0.1:18102 permissions.kp 2>/dev/null
code=$?
rm -r perm_work
(exit $code)
