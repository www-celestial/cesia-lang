# A port that the system gave free, written PORT in what the program says.
port=$(cesia run --allow net=own "$root/tests/free-port.ce")
{
  cesia run $no_spec --allow net=:$port listen-scope.ce 127.0.0.1 $port
  cesia run $no_spec --allow net=:$port listen-scope.ce localhost $port
  cesia run $no_spec --allow net=:$port listen-scope.ce ::1 $port
  cesia run $no_spec --allow net=:$port listen-scope.ce 0.0.0.0 $port
  cesia run $no_spec --allow net=:$port listen-scope.ce :: $port
  cesia run $no_spec --allow net=0.0.0.0:$port listen-scope.ce 0.0.0.0 $port
  cesia run $no_spec --allow net=[::]:$port listen-scope.ce :: $port
  cesia run $no_spec --allow net=127.0.0.1:$port listen-scope.ce 127.0.0.1 $port
  cesia run $no_spec --allow net=127.0.0.1:$port listen-scope.ce 0.0.0.0 $port
  cesia run $no_spec --allow net listen-scope.ce 0.0.0.0 $port
} 2>&1 | sed "s/$port/PORT/g"
