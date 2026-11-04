SDL_VIDEODRIVER=dummy "$root/_build/default/src/bin/main.exe" run $no_spec --allow ffi=SDL3,ffi=SDL3_ttf font-unknown.ce 2>&1 | head -1 | sed "s/^[^ ]* //"
