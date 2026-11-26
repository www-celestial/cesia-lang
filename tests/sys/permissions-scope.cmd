# The grants name another port than the one the program asks for.
port=$("$root/_build/default/src/bin/main.exe" run --allow net=own "$root/tests/free-port.ce")
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read=./perm_other,write=./perm_other,exec=false,env=OTHER,net=:$((port - 1)),net=127.0.0.1:$((port - 1)) permissions.ce $port 2>/dev/null
