# cpp.Wrap makes its library again when a header of the project changes, and never loads a library that it didn't make,
# even beside the very .cpp it wrote: the fingerprint of what it made is kept in the person's own cache.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
export XDG_CACHE_HOME="$dir/cache"
run() { "$root/_build/default/src/bin/main.exe" run $no_spec --allow "read=$dir,write=$dir,exec=g++,ffi=$dir/libstale_cesia.so" rebuild.ce "$dir" 2> /dev/null; }
printf 'inline long baseVal() { return 1; }\n' > "$dir/val.hpp"
run
printf 'inline long baseVal() { return 2; }\n' > "$dir/val.hpp"
echo "== the header changed"
run
echo "== another library put in the folder, beside the .cpp that Wrap wrote"
printf '#include <stdint.h>\nextern "C" { const char *kp_take_error(void) { return 0; } int64_t val(void) { return 666; } }\n' > "$dir/planted.cpp"
g++ -shared -fPIC -o "$dir/libstale_cesia.so" "$dir/planted.cpp"
run
echo "== nothing changed: the same library"
before=$(ls -i "$dir/libstale_cesia.so")
run
[ "$(ls -i "$dir/libstale_cesia.so")" = "$before" ] && echo "not made again"
ls -A "$dir" | grep -c '^\.lib' || true
