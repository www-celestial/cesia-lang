mkdir -p perm_ro/perm_work
echo x > perm_ro/perm_work/a
cd perm_ro
"$root/_build/default/bin/main.exe" run $no_spec --allow read=./perm_work ../permissions.k 2>/dev/null
code=$?
cd ..
rm -r perm_ro
(exit $code)
