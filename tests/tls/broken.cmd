dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -subj /CN=127.0.0.1 -days 2 -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
"$root/_build/default/src/bin/main.exe" run $no_spec --allow ffi=ssl,ffi=crypto,net=:18208,net=127.0.0.1:18208,net=:18209,net=127.0.0.1:18209 broken.k "$dir/cert.pem" "$dir/key.pem" 2>/dev/null
