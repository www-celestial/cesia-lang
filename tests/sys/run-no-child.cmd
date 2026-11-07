# Cesia started with SIGCHLD ignored, which a shell's trap '' passes on to what it runs: env --ignore-signal is GNU's alone.
(trap '' CHLD; exec "$root/_build/default/src/bin/main.exe" run $no_spec --allow exec=true run-no-child.ce)
