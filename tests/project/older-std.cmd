# A project whose std/ Cesia 1.1.0 installed, its std/websocket as 1.1.0 wrote it: each of its names is still there for
# it, the native that unmasks a frame too, so a mistake in the program is named as it is, not one in std/.
cd older_std || exit 1
cesia run $no_spec src/main.ce
cesia run $no_spec src/wrong.ce
