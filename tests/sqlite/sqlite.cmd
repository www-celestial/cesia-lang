d=$(mktemp -d); run() { cesia run $no_spec --allow "read=.,read=$1,write=$1" sqlite.ce "$@" 2>/dev/null; }; run memory & run "$d"; s=$?; wait; rm -rf "$d"; (exit $s)
