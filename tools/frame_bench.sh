#!/usr/bin/env bash
# The speed gate: frames per second in a real window, so a window appears for a few seconds. Never use the dummy driver
# here: it draws in software, which says nothing about a real screen.
set -u
cd "$(dirname "$0")/.."
dune build --profile release 2>&1 | head -20
timeout -s KILL 60 _build/default/bin/main.exe run --allow ffi=SDL3,ffi=SDL3_ttf bench/frame.k
timeout -s KILL 60 _build/default/bin/main.exe run --allow ffi=SDL3,ffi=SDL3_ttf,read bench/ui_frame.k
