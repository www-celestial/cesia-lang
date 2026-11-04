cd "$root"
SDL_VIDEODRIVER=dummy timeout --preserve-status -s TERM 0.3 "$root/_build/default/src/bin/main.exe" run $no_spec --allow ffi=SDL3,ffi=SDL3_ttf examples/material.ce
