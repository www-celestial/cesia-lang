# An editor sends a buffer not saved yet: the file on the disk, if any, isn't read.
printf 'use std/io\nio.Prnt(1)\n' | cesia check --stdin unsaved.ce
echo "exit $?"
printf 'use std/io\nio.Print(1)\n' | cesia check --stdin names.ce
