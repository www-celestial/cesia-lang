cd "$root"
# A stop signal becomes a quit event once the window is open. One sent before ends the program at once, as it would any
# program, killed with nothing printed, which a loaded machine can make happen after 0.2 s: then the test waits longer.
for delay in 0.2 0.5 1 2 4; do
  out=$(SDL_VIDEODRIVER=dummy timeout --preserve-status -s TERM "$delay" "$root/_build/default/src/bin/main.exe" run $no_spec --allow ffi=SDL3,ffi=SDL3_ttf examples/window.ce 2>&1)
  code=$?
  [ "$code" -eq 143 ] && [ -z "$out" ] || break
done
echo "$out"
(exit "$code")
