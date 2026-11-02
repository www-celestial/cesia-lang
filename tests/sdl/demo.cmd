cd "$root"
SDL_VIDEODRIVER=dummy timeout --preserve-status -s TERM 0.2 "$root/_build/default/bin/main.exe" run $no_spec --allow ffi=SDL3,ffi=SDL3_ttf examples/window.k
