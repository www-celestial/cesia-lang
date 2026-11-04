SDL_VIDEODRIVER=dummy timeout -s KILL 5 "$root/_build/default/src/bin/main.exe" run $no_spec --allow ffi=SDL3,ffi=SDL3_ttf run-fibers.ce
