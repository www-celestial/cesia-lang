dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp shout.hpp "$dir"
"$root/_build/default/bin/main.exe" run $no_spec --allow "read=$dir,write=$dir,exec=g++,ffi=$dir/libdemo_kepler.so" vector.kp "$dir" 2>/dev/null
