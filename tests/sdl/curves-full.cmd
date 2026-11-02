SDL_VIDEODRIVER=dummy "$root/_build/default/bin/main.exe" run $no_spec --allow ffi=SDL3,ffi=SDL3_ttf curves-full.k 2>&1 | head -1 | sed "s/^[^ ]* //"
