#!/usr/bin/env bash
# The figures of the book that show what a command prints or how a mechanism goes, in docs/book/images, an English
# one and a French one (NAME-fr.svg) each: tools/figures.ce draws them, from commands that it runs in a folder of their
# own with the cesia of _build and Node, and from the programs of the pages themselves. Needs Node 22 or later, and
# libsodium for the hash of a password. ONLY=name draws the figures whose name holds it.
#   tools/figures.sh
set -eu
cd "$(dirname "$0")/.."
cesia="$PWD/_build/default/src/bin/main.exe"
command -v node > /dev/null || { echo "figures: no node" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
XDG_CACHE_HOME="$work/cache" CESIA="$cesia" WORK="$work" OUT=docs/book/images "$cesia" run \
  --allow "exec,read=docs/book,read=$work,write=$work,write=docs/book/images,env=CESIA,env=WORK,env=OUT,env=ONLY,ffi=sodium" tools/figures.ce
du -cb docs/book/images/{commands-session,files-streams,messages-anatomy,types-boundary,texts-positions,toml-sections,wasm-build,crypto-password}*.svg | tail -1
